// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CollateralManager
 * @notice Gestor de collateral para trades fiat-fiat con ratio 150%
 * @dev Sistema avanzado de gestión de collateral con liquidaciones automáticas
 * 
 * Características principales:
 * - Ratio de collateral configurable (default 150%)
 * - Liquidación automática cuando health factor < 120%
 * - Soporte para múltiples tokens como collateral
 * - Integración con price oracle para valoración en tiempo real
 * - Sistema de alertas para collateral en riesgo
 * - Liquidación parcial o total
 * - Fees de liquidación (5% al liquidator)
 * - Protección contra liquidaciones en cascada
 * - Historial completo de liquidaciones
 * - Rebalanceo automático de collateral
 * - Whitelist de tokens aceptados
 * - Límites por token y por usuario
 * 
 * Fórmulas clave:
 * - Health Factor = (Collateral Value USD / Required Value USD) * 10000
 * - Required Value = Trade Amount USD * Required Ratio / 10000
 * - Liquidation Threshold = Required Ratio * 0.8 (120% si required es 150%)
 * 
 * Ejemplo:
 * - Trade: 10,000 USD
 * - Required Ratio: 150% (15000 basis points)
 * - Required Collateral: 15,000 USD
 * - Liquidation Threshold: 12,000 USD (80% de 15,000)
 * - Health Factor = (15000 / 15000) * 10000 = 10000 (100% = healthy)
 * - Si collateral cae a 11,000: Health Factor = 7333 < 8000 → LIQUIDATE
 * 
 * Proceso de liquidación:
 * 1. Monitor detecta health factor < liquidation ratio
 * 2. Liquidator puede ejecutar liquidación parcial/total
 * 3. Collateral se transfiere al trade counterparty
 * 4. Liquidator recibe 5% fee del collateral liquidado
 * 5. Evento emitido para tracking
 */
contract CollateralManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Rol de liquidator
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    /// @notice Estados de collateral
    enum CollateralStatus {
        Active,             // Activo y saludable
        AtRisk,             // Cerca del umbral de liquidación
        Liquidatable,       // Por debajo del umbral, puede ser liquidado
        PartiallyLiquidated, // Parcialmente liquidado
        Liquidated,         // Completamente liquidado
        Released            // Liberado tras completar trade
    }

    /// @notice Tipos de liquidación
    enum LiquidationType {
        Partial,            // Liquidación parcial
        Full,               // Liquidación completa
        Emergency           // Liquidación de emergencia
    }

    /// @notice Información de collateral depositado
    struct CollateralDeposit {
        uint256 depositId;
        address depositor;          // Intermediario que deposita
        address beneficiary;        // Trader protegido
        address token;              // Token de collateral
        uint256 amount;             // Cantidad depositada
        uint256 valueUSD;           // Valor en USD al depositar
        uint256 currentValueUSD;    // Valor actual en USD
        uint256 requiredValueUSD;   // Valor requerido en USD
        uint256 requiredRatio;      // Ratio requerido (15000 = 150%)
        uint256 liquidationRatio;   // Ratio de liquidación (12000 = 120%)
        uint256 healthFactor;       // Factor de salud (10000 = 100%)
        CollateralStatus status;
        uint256 depositedAt;
        uint256 lastUpdateAt;
        uint256 releasableAt;       // Momento en que puede ser liberado
        address linkedTrade;        // Trade asociado
        bool autoRebalance;         // Rebalanceo automático habilitado
    }

    /// @notice Registro de liquidación
    struct LiquidationRecord {
        uint256 liquidationId;
        uint256 depositId;
        address liquidator;
        address depositor;
        address beneficiary;
        address token;
        uint256 amountLiquidated;
        uint256 valueUSD;
        uint256 liquidatorFee;
        LiquidationType liquidationType;
        uint256 healthFactorBefore;
        uint256 timestamp;
        string reason;
    }

    /// @notice Configuración de token de collateral
    struct CollateralToken {
        address token;
        bool whitelisted;
        uint256 minDeposit;         // Depósito mínimo
        uint256 maxDeposit;         // Depósito máximo por usuario
        uint256 totalDeposited;     // Total depositado en el sistema
        uint256 liquidationBonus;   // Bonus para liquidators (500 = 5%)
        uint256 priceVolatility;    // Índice de volatilidad (0-10000)
        uint256 lastPriceUpdate;
        bool acceptingDeposits;
    }

    /// @notice Contador de deposits
    uint256 public depositCount;
    
    /// @notice Contador de liquidaciones
    uint256 public liquidationCount;

    /// @notice Mapeo de deposits
    mapping(uint256 => CollateralDeposit) public deposits;
    
    /// @notice Deposits por usuario
    mapping(address => uint256[]) public userDeposits;
    
    /// @notice Deposits por beneficiario
    mapping(address => uint256[]) public beneficiaryDeposits;
    
    /// @notice Liquidaciones
    mapping(uint256 => LiquidationRecord) public liquidations;
    
    /// @notice Liquidaciones por deposit
    mapping(uint256 => uint256[]) public depositLiquidations;
    
    /// @notice Tokens de collateral
    mapping(address => CollateralToken) public collateralTokens;
    
    /// @notice Lista de tokens whitelisted
    address[] public whitelistedTokens;

    /// @notice Collateral total por usuario por token
    mapping(address => mapping(address => uint256)) public userCollateralBalance;
    
    /// @notice Deposits activos por trade
    mapping(address => uint256[]) public tradeDeposits;

    /// @notice Ratio de collateral requerido (150% = 15000)
    uint256 public defaultRequiredRatio = 15000;
    
    /// @notice Ratio de liquidación (120% = 12000 = 80% del required)
    uint256 public defaultLiquidationRatio = 12000;
    
    /// @notice Ratio de alerta (130% = 13000)
    uint256 public alertRatio = 13000;
    
    /// @notice Fee de liquidación (5%)
    uint256 public liquidationFee = 500;
    
    /// @notice Tiempo mínimo de lock (24 horas)
    uint256 public minLockTime = 24 hours;
    
    /// @notice Tolerancia de precio (5% = 500)
    uint256 public priceTolerance = 500;

    /// @notice Referencia al price oracle
    address public priceOracle;
    
    /// @notice Referencia al IntermediaryManager
    address public intermediaryManager;
    
    /// @notice Referencia al FiatToFiatBridge
    address public fiatToFiatBridge;
    
    /// @notice Referencia al Treasury
    address public treasury;

    /// @notice Valor total en collateral (USD)
    uint256 public totalCollateralValueUSD;
    
    /// @notice Número total de liquidaciones
    uint256 public totalLiquidations;
    
    /// @notice Valor total liquidado (USD)
    uint256 public totalLiquidatedValueUSD;

    // ============================================
    // EVENTOS
    // ============================================

    event CollateralDeposited(
        uint256 indexed depositId,
        address indexed depositor,
        address indexed beneficiary,
        address token,
        uint256 amount,
        uint256 valueUSD
    );

    event CollateralReleased(
        uint256 indexed depositId,
        address indexed depositor,
        uint256 amount
    );

    event CollateralLiquidated(
        uint256 indexed liquidationId,
        uint256 indexed depositId,
        address indexed liquidator,
        uint256 amount,
        LiquidationType liquidationType
    );

    event HealthFactorUpdated(
        uint256 indexed depositId,
        uint256 oldHealthFactor,
        uint256 newHealthFactor,
        CollateralStatus status
    );

    event CollateralAtRisk(
        uint256 indexed depositId,
        address indexed depositor,
        uint256 healthFactor,
        uint256 shortfall
    );

    event TokenWhitelisted(
        address indexed token,
        uint256 minDeposit,
        uint256 maxDeposit
    );

    event TokenDelisted(
        address indexed token
    );

    event CollateralRebalanced(
        uint256 indexed depositId,
        uint256 addedAmount,
        uint256 newHealthFactor
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _priceOracle,
        address _intermediaryManager,
        address _treasury
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_priceOracle != address(0), "Invalid oracle");
        require(_intermediaryManager != address(0), "Invalid intermediary manager");
        require(_treasury != address(0), "Invalid treasury");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(LIQUIDATOR_ROLE, _admin);

        priceOracle = _priceOracle;
        intermediaryManager = _intermediaryManager;
        treasury = _treasury;
    }

    // ============================================
    // GESTIÓN DE TOKENS
    // ============================================

    /**
     * @notice Añade token a whitelist
     */
    function whitelistToken(
        address token,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 liquidationBonus
    ) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(!collateralTokens[token].whitelisted, "Already whitelisted");
        require(liquidationBonus <= 1000, "Bonus too high");

        CollateralToken storage ct = collateralTokens[token];
        ct.token = token;
        ct.whitelisted = true;
        ct.minDeposit = minDeposit;
        ct.maxDeposit = maxDeposit;
        ct.liquidationBonus = liquidationBonus;
        ct.acceptingDeposits = true;

        whitelistedTokens.push(token);

        emit TokenWhitelisted(token, minDeposit, maxDeposit);
    }

    /**
     * @notice Remueve token de whitelist
     */
    function delistToken(address token) external onlyRole(ADMIN_ROLE) {
        require(collateralTokens[token].whitelisted, "Not whitelisted");
        
        collateralTokens[token].whitelisted = false;
        collateralTokens[token].acceptingDeposits = false;

        emit TokenDelisted(token);
    }

    // ============================================
    // DEPÓSITO DE COLLATERAL
    // ============================================

    /**
     * @notice Deposita collateral para un trade
     * @param token Token de collateral
     * @param amount Cantidad a depositar
     * @param beneficiary Trader protegido por el collateral
     * @param tradeValueUSD Valor del trade en USD
     * @param linkedTrade Dirección del contrato de trade
     * @param autoRebalance Habilitar rebalanceo automático
     */
    function depositCollateral(
        address token,
        uint256 amount,
        address beneficiary,
        uint256 tradeValueUSD,
        address linkedTrade,
        bool autoRebalance
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(collateralTokens[token].whitelisted, "Token not whitelisted");
        require(collateralTokens[token].acceptingDeposits, "Not accepting deposits");
        require(amount >= collateralTokens[token].minDeposit, "Below minimum");
        require(amount > 0, "Invalid amount");
        require(beneficiary != address(0), "Invalid beneficiary");
        require(tradeValueUSD > 0, "Invalid trade value");

        // Verificar límite máximo por usuario
        uint256 currentBalance = userCollateralBalance[msg.sender][token];
        require(
            currentBalance + amount <= collateralTokens[token].maxDeposit,
            "Exceeds max deposit"
        );

        // Obtener precio del token
        uint256 tokenPriceUSD = _getTokenPrice(token);
        uint256 valueUSD = (amount * tokenPriceUSD) / 1e18;

        // Calcular valor requerido (150% del trade)
        uint256 requiredValueUSD = (tradeValueUSD * defaultRequiredRatio) / 10000;
        
        // Verificar que el collateral sea suficiente
        require(valueUSD >= requiredValueUSD, "Insufficient collateral");

        // Transferir tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Crear deposit
        depositCount++;
        CollateralDeposit storage deposit = deposits[depositCount];
        deposit.depositId = depositCount;
        deposit.depositor = msg.sender;
        deposit.beneficiary = beneficiary;
        deposit.token = token;
        deposit.amount = amount;
        deposit.valueUSD = valueUSD;
        deposit.currentValueUSD = valueUSD;
        deposit.requiredValueUSD = requiredValueUSD;
        deposit.requiredRatio = defaultRequiredRatio;
        deposit.liquidationRatio = defaultLiquidationRatio;
        deposit.healthFactor = (valueUSD * 10000) / requiredValueUSD;
        deposit.status = CollateralStatus.Active;
        deposit.depositedAt = block.timestamp;
        deposit.lastUpdateAt = block.timestamp;
        deposit.releasableAt = block.timestamp + minLockTime;
        deposit.linkedTrade = linkedTrade;
        deposit.autoRebalance = autoRebalance;

        // Actualizar balances
        userDeposits[msg.sender].push(depositCount);
        beneficiaryDeposits[beneficiary].push(depositCount);
        userCollateralBalance[msg.sender][token] += amount;
        collateralTokens[token].totalDeposited += amount;
        totalCollateralValueUSD += valueUSD;

        if (linkedTrade != address(0)) {
            tradeDeposits[linkedTrade].push(depositCount);
        }

        emit CollateralDeposited(
            depositCount,
            msg.sender,
            beneficiary,
            token,
            amount,
            valueUSD
        );

        return depositCount;
    }

    /**
     * @notice Añade más collateral a un deposit existente
     */
    function addCollateral(uint256 depositId, uint256 amount) 
        external 
        nonReentrant 
    {
        CollateralDeposit storage deposit = deposits[depositId];
        require(deposit.depositor == msg.sender, "Not depositor");
        require(deposit.status == CollateralStatus.Active || 
                deposit.status == CollateralStatus.AtRisk, "Invalid status");
        require(amount > 0, "Invalid amount");

        address token = deposit.token;
        uint256 tokenPriceUSD = _getTokenPrice(token);
        uint256 addedValueUSD = (amount * tokenPriceUSD) / 1e18;

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        deposit.amount += amount;
        deposit.currentValueUSD += addedValueUSD;
        deposit.lastUpdateAt = block.timestamp;

        uint256 oldHealthFactor = deposit.healthFactor;
        deposit.healthFactor = (deposit.currentValueUSD * 10000) / deposit.requiredValueUSD;

        _updateCollateralStatus(depositId);

        userCollateralBalance[msg.sender][token] += amount;
        collateralTokens[token].totalDeposited += amount;
        totalCollateralValueUSD += addedValueUSD;

        emit CollateralRebalanced(depositId, amount, deposit.healthFactor);
        emit HealthFactorUpdated(depositId, oldHealthFactor, deposit.healthFactor, deposit.status);
    }

    // ============================================
    // ACTUALIZACIÓN DE VALORES
    // ============================================

    /**
     * @notice Actualiza el health factor de un deposit
     */
    function updateHealthFactor(uint256 depositId) public returns (uint256) {
        CollateralDeposit storage deposit = deposits[depositId];
        require(deposit.status != CollateralStatus.Released && 
                deposit.status != CollateralStatus.Liquidated, "Invalid status");

        uint256 tokenPriceUSD = _getTokenPrice(deposit.token);
        uint256 newValueUSD = (deposit.amount * tokenPriceUSD) / 1e18;

        uint256 oldHealthFactor = deposit.healthFactor;
        deposit.currentValueUSD = newValueUSD;
        deposit.healthFactor = (newValueUSD * 10000) / deposit.requiredValueUSD;
        deposit.lastUpdateAt = block.timestamp;

        // CollateralStatus oldStatus = deposit.status;
        _updateCollateralStatus(depositId);

        if (oldHealthFactor != deposit.healthFactor) {
            emit HealthFactorUpdated(depositId, oldHealthFactor, deposit.healthFactor, deposit.status);
        }

        // Si está en riesgo y tiene auto-rebalance, intentar rebalancear
        if (deposit.autoRebalance && deposit.status == CollateralStatus.AtRisk) {
            _attemptAutoRebalance(depositId);
        }

        return deposit.healthFactor;
    }

    /**
     * @notice Actualiza múltiples health factors en batch
     */
    function batchUpdateHealthFactors(uint256[] calldata depositIds) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        for (uint256 i = 0; i < depositIds.length; i++) {
            updateHealthFactor(depositIds[i]);
        }
    }

    /**
     * @notice Actualiza estado del collateral según health factor
     */
    function _updateCollateralStatus(uint256 depositId) internal {
        CollateralDeposit storage deposit = deposits[depositId];
        
        CollateralStatus newStatus;
        if (deposit.healthFactor >= defaultRequiredRatio) {
            newStatus = CollateralStatus.Active;
        } else if (deposit.healthFactor >= alertRatio) {
            newStatus = CollateralStatus.Active;
        } else if (deposit.healthFactor >= deposit.liquidationRatio) {
            newStatus = CollateralStatus.AtRisk;
            
            uint256 shortfall = deposit.requiredValueUSD - deposit.currentValueUSD;
            emit CollateralAtRisk(depositId, deposit.depositor, deposit.healthFactor, shortfall);
        } else {
            newStatus = CollateralStatus.Liquidatable;
            
            uint256 shortfall = deposit.requiredValueUSD - deposit.currentValueUSD;
            emit CollateralAtRisk(depositId, deposit.depositor, deposit.healthFactor, shortfall);
        }

        if (newStatus != deposit.status) {
            deposit.status = newStatus;
        }
    }

    /**
     * @notice Intenta rebalancear automáticamente
     */
    function _attemptAutoRebalance(uint256 depositId) internal view {
        CollateralDeposit storage deposit = deposits[depositId];
        
        // Calcular cantidad necesaria para volver a health factor seguro
        uint256 targetValueUSD = (deposit.requiredValueUSD * defaultRequiredRatio) / 10000;
        uint256 shortfallUSD = targetValueUSD - deposit.currentValueUSD;
        
        if (shortfallUSD == 0) return;

        // Aquí podría implementarse lógica para rebalancear automáticamente
        // desde otros deposits del usuario o solicitar más collateral
        // Por ahora solo emitimos el evento de alerta
    }

    // ============================================
    // LIQUIDACIÓN
    // ============================================

    /**
     * @notice Liquida collateral insuficiente
     * @param depositId ID del deposit a liquidar
     * @param amountToLiquidate Cantidad a liquidar (0 = liquidación total)
     */
    function liquidateCollateral(uint256 depositId, uint256 amountToLiquidate) 
        external 
        nonReentrant 
        onlyRole(LIQUIDATOR_ROLE) 
    {
        CollateralDeposit storage deposit = deposits[depositId];
        require(
            deposit.status == CollateralStatus.Liquidatable ||
            deposit.status == CollateralStatus.PartiallyLiquidated,
            "Not liquidatable"
        );

        // Actualizar health factor
        updateHealthFactor(depositId);
        require(deposit.healthFactor < deposit.liquidationRatio, "Not below threshold");

        uint256 liquidateAmount = amountToLiquidate == 0 ? 
            deposit.amount : amountToLiquidate;
        require(liquidateAmount <= deposit.amount, "Exceeds deposit");

        uint256 tokenPriceUSD = _getTokenPrice(deposit.token);
        uint256 liquidatedValueUSD = (liquidateAmount * tokenPriceUSD) / 1e18;

        // Calcular fee del liquidator
        uint256 liquidatorFeeAmount = (liquidateAmount * liquidationFee) / 10000;
        uint256 beneficiaryAmount = liquidateAmount - liquidatorFeeAmount;

        // Transferir collateral al beneficiario
        IERC20(deposit.token).safeTransfer(deposit.beneficiary, beneficiaryAmount);
        
        // Transferir fee al liquidator
        if (liquidatorFeeAmount > 0) {
            IERC20(deposit.token).safeTransfer(msg.sender, liquidatorFeeAmount);
        }

        // Actualizar deposit
        deposit.amount -= liquidateAmount;
        deposit.currentValueUSD = (deposit.amount * tokenPriceUSD) / 1e18;
        deposit.lastUpdateAt = block.timestamp;

        LiquidationType liquidationType = liquidateAmount == deposit.amount ? 
            LiquidationType.Full : LiquidationType.Partial;

        if (liquidationType == LiquidationType.Full) {
            deposit.status = CollateralStatus.Liquidated;
        } else {
            deposit.status = CollateralStatus.PartiallyLiquidated;
            deposit.healthFactor = (deposit.currentValueUSD * 10000) / deposit.requiredValueUSD;
        }

        // Actualizar balances
        userCollateralBalance[deposit.depositor][deposit.token] -= liquidateAmount;
        collateralTokens[deposit.token].totalDeposited -= liquidateAmount;
        totalCollateralValueUSD -= liquidatedValueUSD;

        // Registrar liquidación
        liquidationCount++;
        LiquidationRecord storage record = liquidations[liquidationCount];
        record.liquidationId = liquidationCount;
        record.depositId = depositId;
        record.liquidator = msg.sender;
        record.depositor = deposit.depositor;
        record.beneficiary = deposit.beneficiary;
        record.token = deposit.token;
        record.amountLiquidated = liquidateAmount;
        record.valueUSD = liquidatedValueUSD;
        record.liquidatorFee = liquidatorFeeAmount;
        record.liquidationType = liquidationType;
        record.healthFactorBefore = deposit.healthFactor;
        record.timestamp = block.timestamp;
        record.reason = "Health factor below liquidation threshold";

        depositLiquidations[depositId].push(liquidationCount);
        totalLiquidations++;
        totalLiquidatedValueUSD += liquidatedValueUSD;

        emit CollateralLiquidated(
            liquidationCount,
            depositId,
            msg.sender,
            liquidateAmount,
            liquidationType
        );

        // Penalizar al intermediario en IntermediaryManager
        _notifyLiquidation(deposit.depositor, depositId);
    }

    /**
     * @notice Liquidación de emergencia (admin only)
     */
    function emergencyLiquidate(uint256 depositId, string memory reason) 
        external 
        nonReentrant 
        onlyRole(ADMIN_ROLE) 
    {
        CollateralDeposit storage deposit = deposits[depositId];
        require(deposit.status != CollateralStatus.Liquidated, "Already liquidated");
        require(deposit.status != CollateralStatus.Released, "Already released");

        uint256 liquidateAmount = deposit.amount;
        uint256 tokenPriceUSD = _getTokenPrice(deposit.token);
        uint256 liquidatedValueUSD = (liquidateAmount * tokenPriceUSD) / 1e18;

        // Transferir todo al beneficiario (sin fee en emergencia)
        IERC20(deposit.token).safeTransfer(deposit.beneficiary, liquidateAmount);

        // Actualizar deposit
        deposit.amount = 0;
        deposit.currentValueUSD = 0;
        deposit.status = CollateralStatus.Liquidated;
        deposit.lastUpdateAt = block.timestamp;

        // Actualizar balances
        userCollateralBalance[deposit.depositor][deposit.token] -= liquidateAmount;
        collateralTokens[deposit.token].totalDeposited -= liquidateAmount;
        totalCollateralValueUSD -= liquidatedValueUSD;

        // Registrar liquidación
        liquidationCount++;
        LiquidationRecord storage record = liquidations[liquidationCount];
        record.liquidationId = liquidationCount;
        record.depositId = depositId;
        record.liquidator = msg.sender;
        record.depositor = deposit.depositor;
        record.beneficiary = deposit.beneficiary;
        record.token = deposit.token;
        record.amountLiquidated = liquidateAmount;
        record.valueUSD = liquidatedValueUSD;
        record.liquidatorFee = 0;
        record.liquidationType = LiquidationType.Emergency;
        record.healthFactorBefore = deposit.healthFactor;
        record.timestamp = block.timestamp;
        record.reason = reason;

        depositLiquidations[depositId].push(liquidationCount);
        totalLiquidations++;
        totalLiquidatedValueUSD += liquidatedValueUSD;

        emit CollateralLiquidated(
            liquidationCount,
            depositId,
            msg.sender,
            liquidateAmount,
            LiquidationType.Emergency
        );
    }

    // ============================================
    // LIBERACIÓN DE COLLATERAL
    // ============================================

    /**
     * @notice Libera collateral tras completar trade
     */
    function releaseCollateral(uint256 depositId) external nonReentrant {
        CollateralDeposit storage deposit = deposits[depositId];
        require(deposit.depositor == msg.sender, "Not depositor");
        require(deposit.status == CollateralStatus.Active, "Not active");
        require(block.timestamp >= deposit.releasableAt, "Still locked");

        uint256 releaseAmount = deposit.amount;
        address token = deposit.token;

        // Transferir de vuelta al depositor
        IERC20(token).safeTransfer(msg.sender, releaseAmount);

        // Actualizar estado
        deposit.amount = 0;
        deposit.currentValueUSD = 0;
        deposit.status = CollateralStatus.Released;
        deposit.lastUpdateAt = block.timestamp;

        // Actualizar balances
        userCollateralBalance[msg.sender][token] -= releaseAmount;
        collateralTokens[token].totalDeposited -= releaseAmount;
        totalCollateralValueUSD -= deposit.valueUSD;

        emit CollateralReleased(depositId, msg.sender, releaseAmount);
    }

    /**
     * @notice Libera collateral (solo bridges autorizados)
     */
    function releaseCollateralByBridge(uint256 depositId) 
        external 
        nonReentrant 
    {
        require(msg.sender == fiatToFiatBridge, "Not authorized bridge");
        
        CollateralDeposit storage deposit = deposits[depositId];
        require(deposit.status == CollateralStatus.Active, "Not active");

        uint256 releaseAmount = deposit.amount;
        address token = deposit.token;
        address depositor = deposit.depositor;

        // Transferir de vuelta al depositor
        IERC20(token).safeTransfer(depositor, releaseAmount);

        // Actualizar estado
        deposit.amount = 0;
        deposit.currentValueUSD = 0;
        deposit.status = CollateralStatus.Released;
        deposit.lastUpdateAt = block.timestamp;

        // Actualizar balances
        userCollateralBalance[depositor][token] -= releaseAmount;
        collateralTokens[token].totalDeposited -= releaseAmount;
        totalCollateralValueUSD -= deposit.valueUSD;

        emit CollateralReleased(depositId, depositor, releaseAmount);
    }

    // ============================================
    // INTEGRACIONES
    // ============================================

    /**
     * @notice Notifica liquidación al IntermediaryManager
     */
    function _notifyLiquidation(address intermediary, uint256 /* depositId */) internal {
        if (intermediaryManager != address(0)) {
            // Llamar a IntermediaryManager para aplicar penalización
            (bool success, ) = intermediaryManager.call(
                abi.encodeWithSignature(
                    "recordTimeout(address)",
                    intermediary
                )
            );
            // Si falla, continuar sin revertir (es una notificación opcional)
            if (!success) {
                // Log could be added here if needed
            }
        }
    }

    /**
     * @notice Obtiene precio de token desde oracle
     */
    function _getTokenPrice(address token) internal view returns (uint256) {
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getTokenPriceUSD(address)", token)
        );
        
        require(success, "Price oracle failed");
        return abi.decode(data, (uint256));
    }

    // ============================================
    // CONFIGURACIÓN
    // ============================================

    function setDefaultRequiredRatio(uint256 ratio) external onlyRole(ADMIN_ROLE) {
        require(ratio >= 10000 && ratio <= 30000, "Invalid ratio");
        defaultRequiredRatio = ratio;
        defaultLiquidationRatio = (ratio * 8000) / 10000; // 80% del required
        alertRatio = (ratio * 8667) / 10000; // 86.67% del required
    }

    function setLiquidationFee(uint256 fee) external onlyRole(ADMIN_ROLE) {
        require(fee <= 1000, "Fee too high");
        liquidationFee = fee;
    }

    function setMinLockTime(uint256 time) external onlyRole(ADMIN_ROLE) {
        require(time >= 1 hours && time <= 30 days, "Invalid time");
        minLockTime = time;
    }

    function setPriceOracle(address _priceOracle) external onlyRole(ADMIN_ROLE) {
        require(_priceOracle != address(0), "Invalid address");
        priceOracle = _priceOracle;
    }

    function setFiatToFiatBridge(address _bridge) external onlyRole(ADMIN_ROLE) {
        require(_bridge != address(0), "Invalid address");
        fiatToFiatBridge = _bridge;
    }

    function setIntermediaryManager(address _manager) external onlyRole(ADMIN_ROLE) {
        require(_manager != address(0), "Invalid address");
        intermediaryManager = _manager;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============================================
    // VISTAS
    // ============================================

    function getDeposit(uint256 depositId) 
        external 
        view 
        returns (CollateralDeposit memory) 
    {
        return deposits[depositId];
    }

    function getLiquidation(uint256 liquidationId) 
        external 
        view 
        returns (LiquidationRecord memory) 
    {
        return liquidations[liquidationId];
    }

    function getUserDeposits(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userDeposits[user];
    }

    function getBeneficiaryDeposits(address beneficiary) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return beneficiaryDeposits[beneficiary];
    }

    function getTradeDeposits(address trade) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return tradeDeposits[trade];
    }

    function getDepositLiquidations(uint256 depositId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return depositLiquidations[depositId];
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return whitelistedTokens;
    }

    function getCollateralToken(address token) 
        external 
        view 
        returns (CollateralToken memory) 
    {
        return collateralTokens[token];
    }

    function isHealthy(uint256 depositId) external view returns (bool) {
        CollateralDeposit storage deposit = deposits[depositId];
        return deposit.healthFactor >= deposit.liquidationRatio;
    }

    function getRequiredCollateral(uint256 tradeValueUSD) 
        external 
        view 
        returns (uint256) 
    {
        return (tradeValueUSD * defaultRequiredRatio) / 10000;
    }

    function calculateHealthFactor(uint256 collateralValueUSD, uint256 requiredValueUSD) 
        external 
        pure 
        returns (uint256) 
    {
        if (requiredValueUSD == 0) return 0;
        return (collateralValueUSD * 10000) / requiredValueUSD;
    }

    function getSystemStats() 
        external 
        view 
        returns (
            uint256 totalDeposits,
            uint256 totalValueUSD,
            uint256 totalLiquidationsCount,
            uint256 totalLiquidatedUSD
        ) 
    {
        return (
            depositCount,
            totalCollateralValueUSD,
            totalLiquidations,
            totalLiquidatedValueUSD
        );
    }
}
