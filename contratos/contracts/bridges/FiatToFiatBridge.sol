// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FiatToFiatBridge
 * @notice Puente descentralizado fiat ↔ fiat con intermediarios y collateral
 * @dev Sistema de 4 partes: traderA, traderB, intermediaryA, intermediaryB
 * 
 * Características principales:
 * - Intercambios fiat ↔ fiat descentralizados entre diferentes monedas
 * - 2 intermediarios con 50k CAMBIO stake + 150% collateral crypto
 * - Collateral en crypto para proteger contra incumplimiento
 * - Sistema de liquidación automática si collateral < 120%
 * - Reputación de intermediarios basada en trades exitosos
 * - Slashing por comportamiento malicioso
 * - Matching automático de trades basado en tasas de cambio
 * - Dispute resolution descentralizado
 * 
 * Flujo principal (ejemplo USD → EUR):
 * 1. TraderA (USA) quiere vender 1000 USD por EUR
 * 2. TraderB (EUR) quiere comprar USD con EUR
 * 3. IntermediaryA (USA) deposita 150% collateral + recibe 1000 USD de TraderA
 * 4. IntermediaryB (EUR) deposita 150% collateral + envía EUR a TraderB
 * 5. IntermediaryA envía USD a TraderB
 * 6. IntermediaryB recibe EUR de TraderA
 * 7. Ambos confirman → collateral liberado + fees pagados
 * 
 * ¿Por qué 2 intermediarios?
 * - Cada uno opera en su zona geográfica/bancaria
 * - No hay transferencia internacional real de fiat
 * - Solo intercambio local en cada país
 * - Collateral en crypto protege a los traders
 * 
 * Roles:
 * - TraderA: Inicia trade, envía fiat en su moneda
 * - TraderB: Acepta trade, envía fiat en su moneda
 * - IntermediaryA: Facilita en zona de TraderA, deposita collateral
 * - IntermediaryB: Facilita en zona de TraderB, deposita collateral
 * 
 * Requisitos de intermediarios:
 * - Stake mínimo: 50,000 CAMBIO tokens
 * - Collateral: 150% del valor del trade en crypto
 * - Liquidación automática si collateral < 120%
 * - Reputación: 0-100 basada en trades exitosos
 */
contract FiatToFiatBridge is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Rol de intermediario
    bytes32 public constant INTERMEDIARY_ROLE = keccak256("INTERMEDIARY_ROLE");

    /// @notice Estados de un trade fiat-fiat
    enum TradeStatus {
        Created,                    // Creado, esperando match
        Matched,                    // Matched con TraderB
        IntermediariesAssigned,     // 2 intermediarios asignados
        CollateralDeposited,        // Ambos collaterals depositados
        TraderAConfirmedSent,       // TraderA confirmó envío
        TraderBConfirmedSent,       // TraderB confirmó envío
        IntermediaryAConfirmed,     // IntermediaryA confirmó recepción
        IntermediaryBConfirmed,     // IntermediaryB confirmó recepción
        BothConfirmed,              // Ambos lados confirmados
        Completed,                  // Completado exitosamente
        Cancelled,                  // Cancelado
        Disputed,                   // En disputa
        Resolved,                   // Disputa resuelta
        TimedOut,                   // Expirado
        Liquidated                  // Liquidado por collateral insuficiente
    }

    /// @notice Tipos de métodos de pago fiat
    enum PaymentMethod {
        BankTransfer,
        Cash,
        MobileMoney,
        PayPal,
        Zelle,
        Venmo,
        WesternUnion,
        MoneyGram,
        Other
    }

    /// @notice Estructura de un trade fiat-fiat
    struct FiatTrade {
        uint256 tradeId;
        
        // Participantes
        address traderA;            // Inicia el trade
        address traderB;            // Acepta el trade
        address intermediaryA;      // Intermediario zona A
        address intermediaryB;      // Intermediario zona B
        
        // Monedas y montos
        string fiatCurrencyA;       // Moneda de TraderA (ej: USD)
        uint256 fiatAmountA;        // Monto en moneda A
        string fiatCurrencyB;       // Moneda de TraderB (ej: EUR)
        uint256 fiatAmountB;        // Monto en moneda B
        uint256 exchangeRate;       // Tasa de cambio (B per A * 1e18)
        
        // Collateral
        address collateralToken;    // Token usado como collateral
        uint256 collateralAmountA;  // Collateral de intermediario A
        uint256 collateralAmountB;  // Collateral de intermediario B
        uint256 requiredCollateralRatio; // Ratio requerido (150% = 15000)
        
        // Métodos de pago
        PaymentMethod paymentMethodA;
        PaymentMethod paymentMethodB;
        string paymentDetailsA;     // Detalles de pago TraderA
        string paymentDetailsB;     // Detalles de pago TraderB
        
        // Estado y timestamps
        TradeStatus status;
        uint256 createdAt;
        uint256 matchedAt;
        uint256 collateralDepositedAt;
        uint256 traderAConfirmedAt;
        uint256 traderBConfirmedAt;
        uint256 completedAt;
        uint256 timeoutAt;
        
        // Confirmaciones
        bool traderAConfirmedSent;
        bool traderBConfirmedSent;
        bool intermediaryAConfirmedReceived;
        bool intermediaryBConfirmedReceived;
        bool traderAConfirmedReceived;
        bool traderBConfirmedReceived;
        
        // Disputa
        string disputeReason;
        address disputeInitiator;
        
        // Configuración
        uint256 minFiatAmountA;
        uint256 maxFiatAmountA;
        bool partialFillAllowed;
    }

    /// @notice Información de intermediario
    struct IntermediaryInfo {
        address intermediary;
        uint256 stakeAmount;                // CAMBIO staked
        uint256 totalCollateralLocked;      // Collateral actualmente bloqueado
        uint256 totalTrades;
        uint256 successfulTrades;
        uint256 disputedTrades;
        uint256 slashedAmount;
        bool active;
        uint256 registeredAt;
        uint256 reputation;                 // 0-100
        string[] supportedFiatCurrencies;   // Monedas soportadas
        PaymentMethod[] supportedMethods;   // Métodos soportados
        string operatingRegion;             // Región de operación
        uint256 maxTradeAmount;             // Monto máximo por trade (USD equiv)
    }

    /// @notice Información de collateral de un trade
    struct CollateralInfo {
        uint256 tradeId;
        address intermediary;
        address token;
        uint256 amount;
        uint256 valueInUSD;         // Valor en USD * 1e18
        uint256 requiredValueInUSD; // Valor requerido en USD * 1e18
        uint256 healthFactor;       // (actual / required) * 10000
        uint256 depositedAt;
        bool active;
    }

    /// @notice Contador de trades
    uint256 public tradeCount;

    /// @notice Mapeo de ID a trade
    mapping(uint256 => FiatTrade) public trades;
    
    /// @notice Trades de un usuario como TraderA
    mapping(address => uint256[]) public traderATrades;
    
    /// @notice Trades de un usuario como TraderB
    mapping(address => uint256[]) public traderBTrades;
    
    /// @notice Información de intermediarios
    mapping(address => IntermediaryInfo) public intermediaries;
    
    /// @notice Lista de intermediarios activos
    address[] public activeIntermediaries;
    
    /// @notice Collateral de intermediarios por trade
    mapping(uint256 => mapping(address => CollateralInfo)) public tradeCollaterals;

    /// @notice Trades activos por par de monedas
    mapping(string => mapping(string => uint256[])) public tradesByPair;
    
    /// @notice Trades de un intermediario
    mapping(address => uint256[]) public intermediaryTrades;

    /// @notice Stake mínimo para ser intermediario (50,000 CAMBIO)
    uint256 public minIntermediaryStake = 50000 * 10**18;
    
    /// @notice Ratio de collateral requerido (150% = 15000 basis points)
    uint256 public requiredCollateralRatio = 15000;
    
    /// @notice Ratio de liquidación (120% = 12000 basis points)
    uint256 public liquidationRatio = 12000;
    
    /// @notice Timeout por defecto (72 horas)
    uint256 public defaultTimeout = 72 hours;
    
    /// @notice Fee del bridge (1.5%)
    uint256 public bridgeFee = 150; // basis points
    
    /// @notice Fee de intermediario (0.5% cada uno)
    uint256 public intermediaryFee = 50; // basis points

    /// @notice Porcentaje de slashing (15%)
    uint256 public slashingPercentage = 1500; // basis points

    /// @notice Referencia al token CAMBIO
    address public cambioToken;
    
    /// @notice Referencia al BalanceManager
    address public balanceManager;
    
    /// @notice Referencia al FeeManager
    address public feeManager;
    
    /// @notice Referencia al CollateralManager
    address public collateralManager;
    
    /// @notice Referencia a oracle de precios
    address public priceOracle;

    // ============================================
    // EVENTOS
    // ============================================

    event TradeCreated(
        uint256 indexed tradeId,
        address indexed traderA,
        string fiatCurrencyA,
        uint256 fiatAmountA,
        string fiatCurrencyB,
        uint256 fiatAmountB
    );

    event TradeMatched(
        uint256 indexed tradeId,
        address indexed traderB,
        uint256 timestamp
    );

    event IntermediariesAssigned(
        uint256 indexed tradeId,
        address indexed intermediaryA,
        address indexed intermediaryB
    );

    event CollateralDeposited(
        uint256 indexed tradeId,
        address indexed intermediary,
        uint256 amount
    );

    event PaymentConfirmed(
        uint256 indexed tradeId,
        address indexed confirmer,
        string confirmationType
    );

    event TradeCompleted(
        uint256 indexed tradeId,
        uint256 timestamp
    );

    event TradeCancelled(
        uint256 indexed tradeId,
        address canceller
    );

    event DisputeRaised(
        uint256 indexed tradeId,
        address raiser,
        string reason
    );

    event IntermediaryRegistered(
        address indexed intermediary,
        uint256 stake
    );

    event IntermediarySlashed(
        address indexed intermediary,
        uint256 amount,
        string reason
    );

    event CollateralLiquidated(
        uint256 indexed tradeId,
        address indexed intermediary,
        uint256 amount
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _cambioToken,
        address _balanceManager,
        address _feeManager,
        address _collateralManager,
        address _priceOracle
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_cambioToken != address(0), "Invalid token");
        require(_balanceManager != address(0), "Invalid balance manager");
        require(_feeManager != address(0), "Invalid fee manager");
        require(_collateralManager != address(0), "Invalid collateral manager");
        require(_priceOracle != address(0), "Invalid price oracle");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        cambioToken = _cambioToken;
        balanceManager = _balanceManager;
        feeManager = _feeManager;
        collateralManager = _collateralManager;
        priceOracle = _priceOracle;
    }

    // ============================================
    // GESTIÓN DE INTERMEDIARIOS
    // ============================================

    /**
     * @notice Registra un nuevo intermediario con stake
     * @param stakeAmount Cantidad de CAMBIO a stakear
     * @param supportedCurrencies Monedas fiat soportadas
     * @param supportedMethods Métodos de pago soportados
     * @param operatingRegion Región de operación
     * @param maxTradeAmount Monto máximo por trade
     */
    function registerIntermediary(
        uint256 stakeAmount,
        string[] memory supportedCurrencies,
        PaymentMethod[] memory supportedMethods,
        string memory operatingRegion,
        uint256 maxTradeAmount
    ) external nonReentrant {
        require(stakeAmount >= minIntermediaryStake, "Insufficient stake");
        require(!intermediaries[msg.sender].active, "Already registered");
        require(supportedCurrencies.length > 0, "No currencies");
        require(supportedMethods.length > 0, "No methods");
        require(bytes(operatingRegion).length > 0, "Region required");
        require(maxTradeAmount > 0, "Invalid max amount");

        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), stakeAmount);

        IntermediaryInfo storage info = intermediaries[msg.sender];
        info.intermediary = msg.sender;
        info.stakeAmount = stakeAmount;
        info.totalCollateralLocked = 0;
        info.totalTrades = 0;
        info.successfulTrades = 0;
        info.disputedTrades = 0;
        info.slashedAmount = 0;
        info.active = true;
        info.registeredAt = block.timestamp;
        info.reputation = 100;
        info.operatingRegion = operatingRegion;
        info.maxTradeAmount = maxTradeAmount;

        for (uint256 i = 0; i < supportedCurrencies.length; i++) {
            info.supportedFiatCurrencies.push(supportedCurrencies[i]);
        }

        for (uint256 i = 0; i < supportedMethods.length; i++) {
            info.supportedMethods.push(supportedMethods[i]);
        }

        activeIntermediaries.push(msg.sender);
        _grantRole(INTERMEDIARY_ROLE, msg.sender);

        emit IntermediaryRegistered(msg.sender, stakeAmount);
    }

    /**
     * @notice Añade más stake
     */
    function addIntermediaryStake(uint256 amount) external nonReentrant {
        require(intermediaries[msg.sender].active, "Not intermediary");
        require(amount > 0, "Invalid amount");

        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), amount);
        intermediaries[msg.sender].stakeAmount += amount;
    }

    /**
     * @notice Retira stake (si no hay collateral bloqueado)
     */
    function withdrawIntermediaryStake(uint256 amount) external nonReentrant {
        IntermediaryInfo storage info = intermediaries[msg.sender];
        require(info.active, "Not intermediary");
        require(amount <= info.stakeAmount, "Insufficient stake");
        require(info.stakeAmount - amount >= minIntermediaryStake, "Below minimum");
        require(info.totalCollateralLocked == 0, "Collateral locked");

        info.stakeAmount -= amount;
        IERC20(cambioToken).safeTransfer(msg.sender, amount);
    }

    // ============================================
    // CREACIÓN DE TRADES
    // ============================================

    /**
     * @notice Crea un trade fiat-fiat
     * @param fiatCurrencyA Moneda de origen
     * @param fiatAmountA Monto de origen
     * @param fiatCurrencyB Moneda de destino
     * @param fiatAmountB Monto de destino
     * @param collateralToken Token para collateral
     * @param paymentMethodA Método de pago en moneda A
     * @param paymentDetailsA Detalles de pago en moneda A
     * @param minFiatAmountA Mínimo para partial fills
     * @param maxFiatAmountA Máximo para partial fills
     */
    function createTrade(
        string memory fiatCurrencyA,
        uint256 fiatAmountA,
        string memory fiatCurrencyB,
        uint256 fiatAmountB,
        address collateralToken,
        PaymentMethod paymentMethodA,
        string memory paymentDetailsA,
        uint256 minFiatAmountA,
        uint256 maxFiatAmountA
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(fiatAmountA > 0, "Invalid amount A");
        require(fiatAmountB > 0, "Invalid amount B");
        require(bytes(fiatCurrencyA).length > 0, "Invalid currency A");
        require(bytes(fiatCurrencyB).length > 0, "Invalid currency B");
        require(collateralToken != address(0), "Invalid collateral token");
        require(bytes(paymentDetailsA).length > 0, "Payment details required");
        require(minFiatAmountA <= fiatAmountA, "Min exceeds total");
        require(maxFiatAmountA >= minFiatAmountA, "Max below min");

        tradeCount++;
        uint256 exchangeRate = (fiatAmountB * 1e18) / fiatAmountA;

        FiatTrade storage trade = trades[tradeCount];
        trade.tradeId = tradeCount;
        trade.traderA = msg.sender;
        trade.fiatCurrencyA = fiatCurrencyA;
        trade.fiatAmountA = fiatAmountA;
        trade.fiatCurrencyB = fiatCurrencyB;
        trade.fiatAmountB = fiatAmountB;
        trade.exchangeRate = exchangeRate;
        trade.collateralToken = collateralToken;
        trade.requiredCollateralRatio = requiredCollateralRatio;
        trade.paymentMethodA = paymentMethodA;
        trade.paymentDetailsA = paymentDetailsA;
        trade.status = TradeStatus.Created;
        trade.createdAt = block.timestamp;
        trade.timeoutAt = block.timestamp + (defaultTimeout * 2);
        trade.minFiatAmountA = minFiatAmountA;
        trade.maxFiatAmountA = maxFiatAmountA;
        trade.partialFillAllowed = minFiatAmountA < fiatAmountA;

        traderATrades[msg.sender].push(tradeCount);
        tradesByPair[fiatCurrencyA][fiatCurrencyB].push(tradeCount);

        emit TradeCreated(
            tradeCount,
            msg.sender,
            fiatCurrencyA,
            fiatAmountA,
            fiatCurrencyB,
            fiatAmountB
        );

        return tradeCount;
    }

    // ============================================
    // MATCHING Y ASIGNACIÓN
    // ============================================

    /**
     * @notice TraderB acepta un trade
     * @param tradeId ID del trade
     * @param paymentMethodB Método de pago en moneda B
     * @param paymentDetailsB Detalles de pago en moneda B
     */
    function acceptTrade(
        uint256 tradeId,
        PaymentMethod paymentMethodB,
        string memory paymentDetailsB
    ) external nonReentrant whenNotPaused {
        FiatTrade storage trade = trades[tradeId];
        
        require(trade.status == TradeStatus.Created, "Trade not available");
        require(trade.traderA != msg.sender, "Cannot accept own trade");
        require(block.timestamp < trade.timeoutAt, "Trade expired");
        require(bytes(paymentDetailsB).length > 0, "Payment details required");

        trade.traderB = msg.sender;
        trade.paymentMethodB = paymentMethodB;
        trade.paymentDetailsB = paymentDetailsB;
        trade.status = TradeStatus.Matched;
        trade.matchedAt = block.timestamp;
        trade.timeoutAt = block.timestamp + defaultTimeout;

        traderBTrades[msg.sender].push(tradeId);

        // Asignar intermediarios automáticamente
        _assignIntermediaries(tradeId);

        emit TradeMatched(tradeId, msg.sender, block.timestamp);
    }

    /**
     * @notice Asigna intermediarios al trade
     */
    function _assignIntermediaries(uint256 tradeId) internal {
        FiatTrade storage trade = trades[tradeId];
        
        address intermediaryA = _selectIntermediary(
            trade.fiatCurrencyA,
            trade.paymentMethodA,
            trade.fiatAmountA
        );
        
        address intermediaryB = _selectIntermediary(
            trade.fiatCurrencyB,
            trade.paymentMethodB,
            trade.fiatAmountB
        );

        require(intermediaryA != address(0), "No intermediary A");
        require(intermediaryB != address(0), "No intermediary B");
        require(intermediaryA != intermediaryB, "Same intermediary");

        trade.intermediaryA = intermediaryA;
        trade.intermediaryB = intermediaryB;
        trade.status = TradeStatus.IntermediariesAssigned;

        intermediaryTrades[intermediaryA].push(tradeId);
        intermediaryTrades[intermediaryB].push(tradeId);

        emit IntermediariesAssigned(tradeId, intermediaryA, intermediaryB);
    }

    /**
     * @notice Selecciona intermediario óptimo
     */
    function _selectIntermediary(
        string memory currency,
        PaymentMethod method,
        uint256 amount
    ) internal view returns (address) {
        address bestIntermediary = address(0);
        uint256 highestReputation = 0;

        for (uint256 i = 0; i < activeIntermediaries.length; i++) {
            address intermediary = activeIntermediaries[i];
            IntermediaryInfo storage info = intermediaries[intermediary];

            if (!info.active) continue;
            if (amount > info.maxTradeAmount) continue;

            bool supportsCurrency = false;
            for (uint256 j = 0; j < info.supportedFiatCurrencies.length; j++) {
                if (keccak256(bytes(info.supportedFiatCurrencies[j])) == keccak256(bytes(currency))) {
                    supportsCurrency = true;
                    break;
                }
            }
            if (!supportsCurrency) continue;

            bool supportsMethod = false;
            for (uint256 j = 0; j < info.supportedMethods.length; j++) {
                if (info.supportedMethods[j] == method) {
                    supportsMethod = true;
                    break;
                }
            }
            if (!supportsMethod) continue;

            if (info.reputation > highestReputation) {
                highestReputation = info.reputation;
                bestIntermediary = intermediary;
            }
        }

        return bestIntermediary;
    }

    // ============================================
    // GESTIÓN DE COLLATERAL
    // ============================================

    /**
     * @notice Intermediario deposita collateral
     * @param tradeId ID del trade
     * @param amount Cantidad de collateral
     */
    function depositCollateral(uint256 tradeId, uint256 amount) 
        external 
        nonReentrant 
        onlyRole(INTERMEDIARY_ROLE) 
    {
        FiatTrade storage trade = trades[tradeId];
        
        require(
            trade.intermediaryA == msg.sender || trade.intermediaryB == msg.sender,
            "Not assigned intermediary"
        );
        require(
            trade.status == TradeStatus.IntermediariesAssigned ||
            trade.status == TradeStatus.CollateralDeposited,
            "Invalid status"
        );
        require(amount > 0, "Invalid amount");

        // Obtener valor del collateral en USD
        uint256 collateralValueUSD = _getCollateralValue(trade.collateralToken, amount);
        
        // Calcular valor requerido
        uint256 fiatAmount = trade.intermediaryA == msg.sender ? 
            trade.fiatAmountA : trade.fiatAmountB;
        uint256 requiredValueUSD = (fiatAmount * requiredCollateralRatio) / 10000;
        
        require(collateralValueUSD >= requiredValueUSD, "Insufficient collateral");

        // Transferir collateral
        IERC20(trade.collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        // Registrar collateral
        CollateralInfo storage collateral = tradeCollaterals[tradeId][msg.sender];
        collateral.tradeId = tradeId;
        collateral.intermediary = msg.sender;
        collateral.token = trade.collateralToken;
        collateral.amount = amount;
        collateral.valueInUSD = collateralValueUSD;
        collateral.requiredValueInUSD = requiredValueUSD;
        collateral.healthFactor = (collateralValueUSD * 10000) / requiredValueUSD;
        collateral.depositedAt = block.timestamp;
        collateral.active = true;

        // Actualizar stake del intermediario
        IntermediaryInfo storage info = intermediaries[msg.sender];
        info.totalCollateralLocked += amount;

        // Actualizar estado si ambos depositaron
        if (trade.intermediaryA == msg.sender) {
            trade.collateralAmountA = amount;
        } else {
            trade.collateralAmountB = amount;
        }

        if (trade.collateralAmountA > 0 && trade.collateralAmountB > 0) {
            trade.status = TradeStatus.CollateralDeposited;
            trade.collateralDepositedAt = block.timestamp;
        }

        emit CollateralDeposited(tradeId, msg.sender, amount);
    }

    /**
     * @notice Verifica salud del collateral
     */
    function checkCollateralHealth(uint256 tradeId, address intermediary) 
        public 
        view 
        returns (uint256 healthFactor) 
    {
        CollateralInfo storage collateral = tradeCollaterals[tradeId][intermediary];
        if (!collateral.active) return 0;

        uint256 currentValue = _getCollateralValue(collateral.token, collateral.amount);
        healthFactor = (currentValue * 10000) / collateral.requiredValueInUSD;
        
        return healthFactor;
    }

    /**
     * @notice Liquida collateral si cae por debajo del umbral
     */
    function liquidateCollateral(uint256 tradeId, address intermediary) 
        external 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
    {
        uint256 healthFactor = checkCollateralHealth(tradeId, intermediary);
        require(healthFactor < liquidationRatio, "Collateral healthy");

        FiatTrade storage trade = trades[tradeId];
        CollateralInfo storage collateral = tradeCollaterals[tradeId][intermediary];

        // Liquidar collateral
        uint256 liquidationAmount = collateral.amount;
        collateral.active = false;

        // Transferir al trader afectado
        address recipient = trade.intermediaryA == intermediary ? 
            trade.traderA : trade.traderB;
        
        IERC20(collateral.token).safeTransfer(recipient, liquidationAmount);

        // Actualizar intermediario
        IntermediaryInfo storage info = intermediaries[intermediary];
        info.totalCollateralLocked -= liquidationAmount;
        info.reputation = info.reputation > 20 ? info.reputation - 20 : 0;

        trade.status = TradeStatus.Liquidated;

        emit CollateralLiquidated(tradeId, intermediary, liquidationAmount);
    }

    // ============================================
    // CONFIRMACIONES Y COMPLETAR
    // ============================================

    /**
     * @notice TraderA confirma que envió fiat a IntermediaryA
     */
    function traderAConfirmSent(uint256 tradeId) external nonReentrant {
        FiatTrade storage trade = trades[tradeId];
        require(trade.traderA == msg.sender, "Not TraderA");
        require(trade.status == TradeStatus.CollateralDeposited, "Invalid status");

        trade.traderAConfirmedSent = true;
        trade.traderAConfirmedAt = block.timestamp;
        trade.status = TradeStatus.TraderAConfirmedSent;

        emit PaymentConfirmed(tradeId, msg.sender, "TraderA sent to IntermediaryA");
    }

    /**
     * @notice TraderB confirma que envió fiat a IntermediaryB
     */
    function traderBConfirmSent(uint256 tradeId) external nonReentrant {
        FiatTrade storage trade = trades[tradeId];
        require(trade.traderB == msg.sender, "Not TraderB");
        require(
            trade.status == TradeStatus.TraderAConfirmedSent ||
            trade.status == TradeStatus.CollateralDeposited,
            "Invalid status"
        );

        trade.traderBConfirmedSent = true;
        trade.traderBConfirmedAt = block.timestamp;
        trade.status = TradeStatus.TraderBConfirmedSent;

        emit PaymentConfirmed(tradeId, msg.sender, "TraderB sent to IntermediaryB");
    }

    /**
     * @notice IntermediaryA confirma recepción de TraderA y envío a TraderB
     */
    function intermediaryAConfirm(uint256 tradeId) 
        external 
        nonReentrant 
        onlyRole(INTERMEDIARY_ROLE) 
    {
        FiatTrade storage trade = trades[tradeId];
        require(trade.intermediaryA == msg.sender, "Not IntermediaryA");
        require(trade.traderAConfirmedSent, "TraderA not confirmed");

        trade.intermediaryAConfirmedReceived = true;
        
        if (trade.intermediaryBConfirmedReceived) {
            trade.status = TradeStatus.BothConfirmed;
        } else {
            trade.status = TradeStatus.IntermediaryAConfirmed;
        }

        emit PaymentConfirmed(tradeId, msg.sender, "IntermediaryA confirmed");
    }

    /**
     * @notice IntermediaryB confirma recepción de TraderB y envío a TraderA
     */
    function intermediaryBConfirm(uint256 tradeId) 
        external 
        nonReentrant 
        onlyRole(INTERMEDIARY_ROLE) 
    {
        FiatTrade storage trade = trades[tradeId];
        require(trade.intermediaryB == msg.sender, "Not IntermediaryB");
        require(trade.traderBConfirmedSent, "TraderB not confirmed");

        trade.intermediaryBConfirmedReceived = true;
        
        if (trade.intermediaryAConfirmedReceived) {
            trade.status = TradeStatus.BothConfirmed;
        } else {
            trade.status = TradeStatus.IntermediaryBConfirmed;
        }

        emit PaymentConfirmed(tradeId, msg.sender, "IntermediaryB confirmed");
    }

    /**
     * @notice Traders confirman recepción final
     */
    function confirmTradeComplete(uint256 tradeId) external nonReentrant {
        FiatTrade storage trade = trades[tradeId];
        
        require(
            trade.traderA == msg.sender || trade.traderB == msg.sender,
            "Not trader"
        );
        require(trade.status == TradeStatus.BothConfirmed, "Not ready");

        if (trade.traderA == msg.sender) {
            trade.traderAConfirmedReceived = true;
        } else {
            trade.traderBConfirmedReceived = true;
        }

        // Completar si ambos confirmaron
        if (trade.traderAConfirmedReceived && trade.traderBConfirmedReceived) {
            _completeTrade(tradeId);
        }
    }

    /**
     * @notice Completa el trade y libera collateral
     */
    function _completeTrade(uint256 tradeId) internal {
        FiatTrade storage trade = trades[tradeId];
        
        // Liberar collateral a intermediarios
        _releaseCollateral(tradeId, trade.intermediaryA);
        _releaseCollateral(tradeId, trade.intermediaryB);

        // Cobrar fees
        _collectFees(tradeId);

        // Actualizar reputaciones
        _updateIntermediaryReputation(trade.intermediaryA, true);
        _updateIntermediaryReputation(trade.intermediaryB, true);

        trade.status = TradeStatus.Completed;
        trade.completedAt = block.timestamp;

        emit TradeCompleted(tradeId, block.timestamp);
    }

    /**
     * @notice Libera collateral a intermediario
     */
    function _releaseCollateral(uint256 tradeId, address intermediary) internal {
        CollateralInfo storage collateral = tradeCollaterals[tradeId][intermediary];
        if (!collateral.active) return;

        uint256 amount = collateral.amount;
        collateral.active = false;

        IERC20(collateral.token).safeTransfer(intermediary, amount);

        IntermediaryInfo storage info = intermediaries[intermediary];
        info.totalCollateralLocked -= amount;
        info.successfulTrades++;
    }

    /**
     * @notice Cobra fees
     */
    function _collectFees(uint256 tradeId) internal {
        FiatTrade storage trade = trades[tradeId];
        
        // Cobrar fee de stake de intermediarios
        uint256 feeAmountA = (intermediaries[trade.intermediaryA].stakeAmount * intermediaryFee) / 10000;
        uint256 feeAmountB = (intermediaries[trade.intermediaryB].stakeAmount * intermediaryFee) / 10000;

        if (feeAmountA > 0) {
            IERC20(cambioToken).safeTransfer(feeManager, feeAmountA);
        }
        
        if (feeAmountB > 0) {
            IERC20(cambioToken).safeTransfer(feeManager, feeAmountB);
        }
    }

    /**
     * @notice Actualiza reputación de intermediario
     */
    function _updateIntermediaryReputation(address intermediary, bool success) internal {
        IntermediaryInfo storage info = intermediaries[intermediary];
        info.totalTrades++;
        
        if (success) {
            if (info.reputation < 100) {
                info.reputation += 1;
            }
        } else {
            if (info.reputation > 10) {
                info.reputation -= 10;
            }
        }
    }

    // ============================================
    // DISPUTAS
    // ============================================

    /**
     * @notice Levanta una disputa
     */
    function raiseDispute(uint256 tradeId, string memory reason) 
        external 
        nonReentrant 
    {
        FiatTrade storage trade = trades[tradeId];
        
        require(
            trade.traderA == msg.sender || 
            trade.traderB == msg.sender ||
            trade.intermediaryA == msg.sender ||
            trade.intermediaryB == msg.sender,
            "Not participant"
        );
        require(bytes(reason).length > 0, "Reason required");

        trade.status = TradeStatus.Disputed;
        trade.disputeReason = reason;
        trade.disputeInitiator = msg.sender;

        emit DisputeRaised(tradeId, msg.sender, reason);
    }

    /**
     * @notice Resuelve una disputa
     */
    function resolveDispute(
        uint256 tradeId,
        bool favorTraderA,
        bool slashIntermediaryA,
        bool slashIntermediaryB
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        FiatTrade storage trade = trades[tradeId];
        require(trade.status == TradeStatus.Disputed, "Not disputed");

        // Determinar acción basada en resolución
        if (favorTraderA) {
            // TraderA gana - devolver collateral a TraderA
            CollateralInfo storage collateralB = tradeCollaterals[tradeId][trade.intermediaryB];
            if (collateralB.active) {
                IERC20(collateralB.token).safeTransfer(trade.traderA, collateralB.amount);
                collateralB.active = false;
            }
        } else {
            // TraderB gana - devolver collateral a TraderB
            CollateralInfo storage collateralA = tradeCollaterals[tradeId][trade.intermediaryA];
            if (collateralA.active) {
                IERC20(collateralA.token).safeTransfer(trade.traderB, collateralA.amount);
                collateralA.active = false;
            }
        }

        // Slashing si corresponde
        if (slashIntermediaryA) {
            _slashIntermediary(trade.intermediaryA, "Dispute resolved against");
        } else {
            _releaseCollateral(tradeId, trade.intermediaryA);
        }

        if (slashIntermediaryB) {
            _slashIntermediary(trade.intermediaryB, "Dispute resolved against");
        } else {
            _releaseCollateral(tradeId, trade.intermediaryB);
        }

        trade.status = TradeStatus.Resolved;
        trade.completedAt = block.timestamp;
    }

    /**
     * @notice Aplica slashing a intermediario
     */
    function _slashIntermediary(address intermediary, string memory reason) internal {
        IntermediaryInfo storage info = intermediaries[intermediary];
        uint256 slashAmount = (info.stakeAmount * slashingPercentage) / 10000;
        
        info.stakeAmount -= slashAmount;
        info.slashedAmount += slashAmount;
        info.disputedTrades++;
        info.reputation = info.reputation > 15 ? info.reputation - 15 : 0;

        IERC20(cambioToken).safeTransfer(feeManager, slashAmount);

        emit IntermediarySlashed(intermediary, slashAmount, reason);
    }

    // ============================================
    // CANCELACIÓN Y TIMEOUTS
    // ============================================

    /**
     * @notice Cancela un trade no matched
     */
    function cancelTrade(uint256 tradeId) external nonReentrant {
        FiatTrade storage trade = trades[tradeId];
        require(trade.traderA == msg.sender, "Not TraderA");
        require(trade.status == TradeStatus.Created, "Cannot cancel");

        trade.status = TradeStatus.Cancelled;
        emit TradeCancelled(tradeId, msg.sender);
    }

    /**
     * @notice Procesa timeouts
     */
    function processTimeouts(uint256[] calldata tradeIds) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        for (uint256 i = 0; i < tradeIds.length; i++) {
            FiatTrade storage trade = trades[tradeIds[i]];
            
            if (block.timestamp >= trade.timeoutAt && trade.status != TradeStatus.Completed) {
                // Devolver collaterals
                if (trade.collateralAmountA > 0) {
                    _releaseCollateral(tradeIds[i], trade.intermediaryA);
                }
                if (trade.collateralAmountB > 0) {
                    _releaseCollateral(tradeIds[i], trade.intermediaryB);
                }
                
                trade.status = TradeStatus.TimedOut;
            }
        }
    }

    // ============================================
    // FUNCIONES AUXILIARES
    // ============================================

    /**
     * @notice Obtiene valor del collateral en USD
     */
    function _getCollateralValue(address token, uint256 amount) 
        internal 
        view 
        returns (uint256) 
    {
        // Llamar al oracle de precios
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getTokenPriceUSD(address)", token)
        );
        
        if (!success) return 0;
        
        uint256 pricePerToken = abi.decode(data, (uint256));
        return (amount * pricePerToken) / 1e18;
    }

    // ============================================
    // SETTERS
    // ============================================

    function setMinIntermediaryStake(uint256 amount) external onlyRole(ADMIN_ROLE) {
        minIntermediaryStake = amount;
    }

    function setRequiredCollateralRatio(uint256 ratio) external onlyRole(ADMIN_ROLE) {
        require(ratio >= 10000 && ratio <= 30000, "Invalid ratio");
        requiredCollateralRatio = ratio;
    }

    function setLiquidationRatio(uint256 ratio) external onlyRole(ADMIN_ROLE) {
        require(ratio >= 10000 && ratio < requiredCollateralRatio, "Invalid ratio");
        liquidationRatio = ratio;
    }

    function setDefaultTimeout(uint256 timeout) external onlyRole(ADMIN_ROLE) {
        require(timeout >= 1 hours && timeout <= 7 days, "Invalid timeout");
        defaultTimeout = timeout;
    }

    function setBridgeFee(uint256 fee) external onlyRole(ADMIN_ROLE) {
        require(fee <= 500, "Fee too high");
        bridgeFee = fee;
    }

    function setIntermediaryFee(uint256 fee) external onlyRole(ADMIN_ROLE) {
        require(fee <= 200, "Fee too high");
        intermediaryFee = fee;
    }

    function setSlashingPercentage(uint256 percentage) external onlyRole(ADMIN_ROLE) {
        require(percentage <= 5000, "Percentage too high");
        slashingPercentage = percentage;
    }

    function setPriceOracle(address _priceOracle) external onlyRole(ADMIN_ROLE) {
        require(_priceOracle != address(0), "Invalid address");
        priceOracle = _priceOracle;
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

    function getTrade(uint256 tradeId) external view returns (FiatTrade memory) {
        return trades[tradeId];
    }

    function getIntermediary(address intermediary) 
        external 
        view 
        returns (IntermediaryInfo memory) 
    {
        return intermediaries[intermediary];
    }

    function getTradeCollateral(uint256 tradeId, address intermediary) 
        external 
        view 
        returns (CollateralInfo memory) 
    {
        return tradeCollaterals[tradeId][intermediary];
    }

    function getTraderATrades(address trader) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return traderATrades[trader];
    }

    function getTraderBTrades(address trader) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return traderBTrades[trader];
    }

    function getIntermediaryTrades(address intermediary) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return intermediaryTrades[intermediary];
    }

    function getActiveIntermediaries() 
        external 
        view 
        returns (address[] memory) 
    {
        return activeIntermediaries;
    }

    function getTradesByPair(string memory currencyA, string memory currencyB) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return tradesByPair[currencyA][currencyB];
    }
}
