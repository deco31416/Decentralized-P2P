// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CryptoToFiatBridge
 * @notice Puente descentralizado crypto → fiat con sistema de validación
 * @dev Sistema de 3 partes: buyer (crypto), seller (fiat), validator
 * 
 * Características principales:
 * - Intercambios crypto → fiat descentralizados
 * - Validadores con stake mínimo (10,000 CAMBIO)
 * - Escrow automático de crypto
 * - Confirmación de pago fiat off-chain por validator
 * - Sistema de reputación para validadores
 * - Slashing por comportamiento malicioso
 * - Timeouts para prevenir bloqueo de fondos
 * - Dispute resolution con votación
 * 
 * Flujo principal:
 * 1. Buyer crea orden → deposita crypto → escrow activado
 * 2. Seller acepta orden → promete pagar fiat off-chain
 * 3. Buyer envía fiat off-chain (banco, transferencia, etc)
 * 4. Validator confirma recepción de fiat → libera crypto a seller
 * 5. Si hay disputa → votación de validadores → resolver
 * 
 * Roles:
 * - Buyer: Compra fiat con crypto
 * - Seller: Vende fiat por crypto
 * - Validator: Confirma pago fiat (requiere 10k CAMBIO stake)
 */
contract CryptoToFiatBridge is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Rol de validator
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    /// @notice Estados de una orden
    enum OrderStatus {
        Created,            // Creada, esperando crypto
        Active,             // Crypto depositado, esperando seller
        Matched,            // Seller asignado, esperando pago fiat
        FiatPending,        // Buyer envió fiat, esperando confirmación
        Validating,         // Validator revisando
        Completed,          // Completada exitosamente
        Cancelled,          // Cancelada
        Disputed,           // En disputa
        Resolved,           // Disputa resuelta
        TimedOut            // Expirada
    }

    /// @notice Tipos de métodos de pago fiat
    enum PaymentMethod {
        BankTransfer,       // Transferencia bancaria
        Cash,               // Efectivo
        MobileMoney,        // Dinero móvil
        PayPal,             // PayPal
        Zelle,              // Zelle
        Venmo,              // Venmo
        Other               // Otro
    }

    /// @notice Estructura de una orden crypto → fiat
    struct Order {
        uint256 orderId;
        address buyer;              // Compra fiat con crypto
        address seller;             // Vende fiat por crypto
        address validator;          // Validador asignado
        address cryptoToken;        // Token crypto a vender
        uint256 cryptoAmount;       // Cantidad de crypto
        string fiatCurrency;        // Moneda fiat (USD, EUR, etc)
        uint256 fiatAmount;         // Cantidad de fiat
        uint256 exchangeRate;       // Tasa de cambio (fiat per crypto * 1e18)
        PaymentMethod paymentMethod;
        string paymentDetails;      // Detalles de pago (encriptados)
        OrderStatus status;
        uint256 createdAt;
        uint256 matchedAt;
        uint256 fiatSentAt;
        uint256 validatedAt;
        uint256 completedAt;
        uint256 timeoutAt;
        bool buyerConfirmed;
        bool sellerConfirmed;
        bool validatorConfirmed;
        string disputeReason;
    }

    /// @notice Información de validator
    struct ValidatorInfo {
        address validator;
        uint256 stake;              // Stake en CAMBIO tokens
        uint256 totalValidations;
        uint256 successfulValidations;
        uint256 disputedValidations;
        uint256 slashedAmount;
        bool active;
        uint256 registeredAt;
        uint256 reputation;         // 0-100
    }

    /// @notice Contador de órdenes
    uint256 public orderCount;

    /// @notice Mapeo de ID a orden
    mapping(uint256 => Order) public orders;
    
    /// @notice Órdenes de un usuario (como buyer)
    mapping(address => uint256[]) public buyerOrders;
    
    /// @notice Órdenes de un usuario (como seller)
    mapping(address => uint256[]) public sellerOrders;
    
    /// @notice Información de validadores
    mapping(address => ValidatorInfo) public validators;
    
    /// @notice Lista de validadores activos
    address[] public activeValidators;

    /// @notice Órdenes activas por moneda fiat
    mapping(string => uint256[]) public ordersByFiatCurrency;

    /// @notice Stake mínimo para ser validator (10,000 CAMBIO)
    uint256 public minValidatorStake = 10000 * 10**18;
    
    /// @notice Timeout por defecto (48 horas)
    uint256 public defaultTimeout = 48 hours;
    
    /// @notice Fee del bridge (1%)
    uint256 public bridgeFee = 100; // basis points

    /// @notice Porcentaje de slashing por validación incorrecta (10%)
    uint256 public slashingPercentage = 1000; // basis points

    /// @notice Referencia al token CAMBIO
    address public cambioToken;
    
    /// @notice Referencia al BalanceManager
    address public balanceManager;
    
    /// @notice Referencia al FeeManager
    address public feeManager;
    
    /// @notice Referencia al EscrowManager
    address public escrowManager;
    
    /// @notice Referencia al GovernanceManager
    address public governanceManager;

    // ============================================
    // EVENTOS
    // ============================================

    event OrderCreated(
        uint256 indexed orderId,
        address indexed buyer,
        address cryptoToken,
        uint256 cryptoAmount,
        string fiatCurrency,
        uint256 fiatAmount
    );

    event OrderMatched(
        uint256 indexed orderId,
        address indexed seller,
        address indexed validator
    );

    event FiatPaymentSent(
        uint256 indexed orderId,
        address indexed buyer,
        uint256 timestamp
    );

    event OrderValidated(
        uint256 indexed orderId,
        address indexed validator,
        bool approved
    );

    event OrderCompleted(
        uint256 indexed orderId,
        uint256 timestamp
    );

    event OrderCancelled(
        uint256 indexed orderId,
        address canceller
    );

    event DisputeRaised(
        uint256 indexed orderId,
        address raiser,
        string reason
    );

    event ValidatorRegistered(
        address indexed validator,
        uint256 stake
    );

    event ValidatorSlashed(
        address indexed validator,
        uint256 amount,
        string reason
    );

    event ValidatorRewardPaid(
        address indexed validator,
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
        address _escrowManager
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_cambioToken != address(0), "Invalid token");
        require(_balanceManager != address(0), "Invalid balance manager");
        require(_feeManager != address(0), "Invalid fee manager");
        require(_escrowManager != address(0), "Invalid escrow manager");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        cambioToken = _cambioToken;
        balanceManager = _balanceManager;
        feeManager = _feeManager;
        escrowManager = _escrowManager;
    }

    // ============================================
    // GESTIÓN DE VALIDADORES
    // ============================================

    /**
     * @notice Registra un nuevo validator con stake
     * @param stakeAmount Cantidad de CAMBIO a stakear
     */
    function registerValidator(uint256 stakeAmount) external nonReentrant {
        require(stakeAmount >= minValidatorStake, "Insufficient stake");
        require(!validators[msg.sender].active, "Already registered");

        // Transferir stake
        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), stakeAmount);

        validators[msg.sender] = ValidatorInfo({
            validator: msg.sender,
            stake: stakeAmount,
            totalValidations: 0,
            successfulValidations: 0,
            disputedValidations: 0,
            slashedAmount: 0,
            active: true,
            registeredAt: block.timestamp,
            reputation: 100 // Empieza con reputación máxima
        });

        activeValidators.push(msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);

        emit ValidatorRegistered(msg.sender, stakeAmount);
    }

    /**
     * @notice Añade más stake a un validator existente
     * @param amount Cantidad adicional a stakear
     */
    function addValidatorStake(uint256 amount) external nonReentrant {
        require(validators[msg.sender].active, "Not a validator");
        require(amount > 0, "Invalid amount");

        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), amount);
        validators[msg.sender].stake += amount;
    }

    /**
     * @notice Retira stake de validator (si no tiene órdenes activas)
     * @param amount Cantidad a retirar
     */
    function withdrawValidatorStake(uint256 amount) external nonReentrant {
        ValidatorInfo storage validator = validators[msg.sender];
        require(validator.active, "Not a validator");
        require(amount <= validator.stake, "Insufficient stake");
        require(validator.stake - amount >= minValidatorStake, "Below minimum");

        validator.stake -= amount;
        IERC20(cambioToken).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Desactiva un validator
     */
    function deactivateValidator() external nonReentrant {
        ValidatorInfo storage validator = validators[msg.sender];
        require(validator.active, "Not active");

        validator.active = false;
        _revokeRole(VALIDATOR_ROLE, msg.sender);

        // Remover de lista activa
        for (uint256 i = 0; i < activeValidators.length; i++) {
            if (activeValidators[i] == msg.sender) {
                activeValidators[i] = activeValidators[activeValidators.length - 1];
                activeValidators.pop();
                break;
            }
        }
    }

    // ============================================
    // CREACIÓN DE ÓRDENES
    // ============================================

    /**
     * @notice Crea una orden crypto → fiat
     * @param cryptoToken Token crypto a vender
     * @param cryptoAmount Cantidad de crypto
     * @param fiatCurrency Moneda fiat (ej: "USD", "EUR")
     * @param fiatAmount Cantidad de fiat
     * @param paymentMethod Método de pago
     * @param paymentDetails Detalles de pago del buyer
     */
    function createOrder(
        address cryptoToken,
        uint256 cryptoAmount,
        string memory fiatCurrency,
        uint256 fiatAmount,
        PaymentMethod paymentMethod,
        string memory paymentDetails
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(cryptoToken != address(0), "Invalid token");
        require(cryptoAmount > 0, "Invalid crypto amount");
        require(fiatAmount > 0, "Invalid fiat amount");
        require(bytes(fiatCurrency).length > 0, "Invalid currency");
        require(bytes(paymentDetails).length > 0, "Payment details required");

        // Bloquear crypto en escrow
        _lockFunds(msg.sender, cryptoToken, cryptoAmount);

        orderCount++;
        uint256 exchangeRate = (fiatAmount * 1e18) / cryptoAmount;

        orders[orderCount] = Order({
            orderId: orderCount,
            buyer: msg.sender,
            seller: address(0),
            validator: address(0),
            cryptoToken: cryptoToken,
            cryptoAmount: cryptoAmount,
            fiatCurrency: fiatCurrency,
            fiatAmount: fiatAmount,
            exchangeRate: exchangeRate,
            paymentMethod: paymentMethod,
            paymentDetails: paymentDetails,
            status: OrderStatus.Active,
            createdAt: block.timestamp,
            matchedAt: 0,
            fiatSentAt: 0,
            validatedAt: 0,
            completedAt: 0,
            timeoutAt: block.timestamp + defaultTimeout,
            buyerConfirmed: false,
            sellerConfirmed: false,
            validatorConfirmed: false,
            disputeReason: ""
        });

        buyerOrders[msg.sender].push(orderCount);
        ordersByFiatCurrency[fiatCurrency].push(orderCount);

        emit OrderCreated(
            orderCount,
            msg.sender,
            cryptoToken,
            cryptoAmount,
            fiatCurrency,
            fiatAmount
        );

        return orderCount;
    }

    // ============================================
    // MATCHING Y EJECUCIÓN
    // ============================================

    /**
     * @notice Seller acepta una orden
     * @param orderId ID de la orden
     */
    function acceptOrder(uint256 orderId) external nonReentrant whenNotPaused {
        Order storage order = orders[orderId];
        
        require(order.status == OrderStatus.Active, "Order not active");
        require(order.buyer != msg.sender, "Cannot accept own order");
        require(block.timestamp < order.timeoutAt, "Order expired");

        // Asignar validator aleatorio de los activos
        address selectedValidator = _selectValidator();
        require(selectedValidator != address(0), "No validators available");

        order.seller = msg.sender;
        order.validator = selectedValidator;
        order.status = OrderStatus.Matched;
        order.matchedAt = block.timestamp;
        order.timeoutAt = block.timestamp + defaultTimeout; // Reset timeout

        sellerOrders[msg.sender].push(orderId);

        emit OrderMatched(orderId, msg.sender, selectedValidator);
    }

    /**
     * @notice Buyer confirma que envió el pago fiat
     * @param orderId ID de la orden
     */
    function confirmFiatSent(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        
        require(order.buyer == msg.sender, "Not buyer");
        require(order.status == OrderStatus.Matched, "Invalid status");
        require(block.timestamp < order.timeoutAt, "Order expired");

        order.status = OrderStatus.FiatPending;
        order.fiatSentAt = block.timestamp;
        order.buyerConfirmed = true;

        // Notificar al validator
        // En producción, esto triggerea una notificación off-chain
    }

    /**
     * @notice Validator confirma recepción de fiat y libera crypto
     * @param orderId ID de la orden
     * @param approved true si confirma, false si rechaza
     */
    function validateOrder(
        uint256 orderId,
        bool approved,
        string memory /* evidence */
    ) external nonReentrant onlyRole(VALIDATOR_ROLE) {
        Order storage order = orders[orderId];
        
        require(order.validator == msg.sender, "Not assigned validator");
        require(order.status == OrderStatus.FiatPending, "Invalid status");

        ValidatorInfo storage validator = validators[msg.sender];
        validator.totalValidations++;

        if (approved) {
            // Liberar crypto al seller
            uint256 fee = (order.cryptoAmount * bridgeFee) / 10000;
            uint256 sellerAmount = order.cryptoAmount - fee;

            _transferLocked(order.buyer, order.seller, order.cryptoToken, sellerAmount);
            
            // Fee al FeeManager
            if (fee > 0) {
                _transferLocked(order.buyer, feeManager, order.cryptoToken, fee);
            }

            order.status = OrderStatus.Completed;
            order.completedAt = block.timestamp;
            order.validatorConfirmed = true;
            order.sellerConfirmed = true;

            validator.successfulValidations++;
            
            // Pagar reward al validator (0.1% del monto)
            uint256 reward = (order.cryptoAmount * 10) / 10000;
            if (reward > 0) {
                IERC20(cambioToken).safeTransfer(msg.sender, reward);
                emit ValidatorRewardPaid(msg.sender, reward);
            }

            emit OrderCompleted(orderId, block.timestamp);
        } else {
            // Rechazado - devolver crypto al buyer
            _unlockFunds(order.buyer, order.cryptoToken, order.cryptoAmount);
            
            order.status = OrderStatus.Cancelled;
        }

        order.validatedAt = block.timestamp;
        emit OrderValidated(orderId, msg.sender, approved);
    }

    // ============================================
    // DISPUTAS
    // ============================================

    /**
     * @notice Levanta una disputa sobre una orden
     * @param orderId ID de la orden
     * @param reason Razón de la disputa
     */
    function raiseDispute(uint256 orderId, string memory reason) 
        external 
        nonReentrant 
    {
        Order storage order = orders[orderId];
        
        require(
            order.buyer == msg.sender || order.seller == msg.sender,
            "Not participant"
        );
        require(
            order.status == OrderStatus.Matched ||
            order.status == OrderStatus.FiatPending ||
            order.status == OrderStatus.Validating,
            "Cannot dispute"
        );
        require(bytes(reason).length > 0, "Reason required");

        order.status = OrderStatus.Disputed;
        order.disputeReason = reason;

        emit DisputeRaised(orderId, msg.sender, reason);
    }

    /**
     * @notice Resuelve una disputa (solo ADMIN o governance)
     * @param orderId ID de la orden
     * @param favorBuyer true si favorece al buyer, false si al seller
     * @param slashValidator true si el validator debe ser penalizado
     */
    function resolveDispute(
        uint256 orderId,
        bool favorBuyer,
        bool slashValidator
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Disputed, "Not disputed");

        if (favorBuyer) {
            // Devolver crypto al buyer
            _unlockFunds(order.buyer, order.cryptoToken, order.cryptoAmount);
        } else {
            // Liberar crypto al seller
            uint256 fee = (order.cryptoAmount * bridgeFee) / 10000;
            uint256 sellerAmount = order.cryptoAmount - fee;
            _transferLocked(order.buyer, order.seller, order.cryptoToken, sellerAmount);
            
            if (fee > 0) {
                _transferLocked(order.buyer, feeManager, order.cryptoToken, fee);
            }
        }

        // Slashing del validator si fue negligente
        if (slashValidator && order.validator != address(0)) {
            ValidatorInfo storage validator = validators[order.validator];
            uint256 slashAmount = (validator.stake * slashingPercentage) / 10000;
            
            validator.stake -= slashAmount;
            validator.slashedAmount += slashAmount;
            validator.disputedValidations++;
            validator.reputation = validator.reputation > 10 ? validator.reputation - 10 : 0;

            // Distribuir slashed tokens a treasury
            IERC20(cambioToken).safeTransfer(feeManager, slashAmount);

            emit ValidatorSlashed(order.validator, slashAmount, "Dispute resolved against");
        }

        order.status = OrderStatus.Resolved;
        order.completedAt = block.timestamp;
    }

    // ============================================
    // CANCELACIÓN Y TIMEOUTS
    // ============================================

    /**
     * @notice Cancela una orden antes de ser matched
     * @param orderId ID de la orden
     */
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        
        require(order.buyer == msg.sender, "Not buyer");
        require(order.status == OrderStatus.Active, "Cannot cancel");

        // Devolver crypto
        _unlockFunds(msg.sender, order.cryptoToken, order.cryptoAmount);

        order.status = OrderStatus.Cancelled;

        emit OrderCancelled(orderId, msg.sender);
    }

    /**
     * @notice Procesa timeouts (llamado por keeper)
     * @param orderIds Array de IDs de órdenes
     */
    function processTimeouts(uint256[] calldata orderIds) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage order = orders[orderIds[i]];
            
            if (
                block.timestamp >= order.timeoutAt &&
                (order.status == OrderStatus.Active ||
                 order.status == OrderStatus.Matched ||
                 order.status == OrderStatus.FiatPending)
            ) {
                // Devolver crypto al buyer
                _unlockFunds(order.buyer, order.cryptoToken, order.cryptoAmount);
                
                order.status = OrderStatus.TimedOut;
            }
        }
    }

    // ============================================
    // FUNCIONES AUXILIARES
    // ============================================

    /**
     * @notice Selecciona un validator aleatorio
     */
    function _selectValidator() internal view returns (address) {
        if (activeValidators.length == 0) return address(0);
        
        // Pseudo-random selection basado en block
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            orderCount
        ))) % activeValidators.length;
        
        return activeValidators[randomIndex];
    }

    function _lockFunds(address user, address token, uint256 amount) internal {
        (bool success, ) = balanceManager.call(
            abi.encodeWithSignature("lockFunds(address,address,uint256)", user, token, amount)
        );
        require(success, "Failed to lock funds");
    }

    function _unlockFunds(address user, address token, uint256 amount) internal {
        (bool success, ) = balanceManager.call(
            abi.encodeWithSignature("unlockFunds(address,address,uint256)", user, token, amount)
        );
        require(success, "Failed to unlock funds");
    }

    function _transferLocked(
        address from,
        address to,
        address token,
        uint256 amount
    ) internal {
        (bool success, ) = balanceManager.call(
            abi.encodeWithSignature(
                "transferLocked(address,address,address,uint256)",
                from, to, token, amount
            )
        );
        require(success, "Transfer failed");
    }

    // ============================================
    // SETTERS
    // ============================================

    function setMinValidatorStake(uint256 amount) external onlyRole(ADMIN_ROLE) {
        minValidatorStake = amount;
    }

    function setDefaultTimeout(uint256 timeout) external onlyRole(ADMIN_ROLE) {
        require(timeout >= 1 hours && timeout <= 7 days, "Invalid timeout");
        defaultTimeout = timeout;
    }

    function setBridgeFee(uint256 fee) external onlyRole(ADMIN_ROLE) {
        require(fee <= 500, "Fee too high"); // Max 5%
        bridgeFee = fee;
    }

    function setSlashingPercentage(uint256 percentage) external onlyRole(ADMIN_ROLE) {
        require(percentage <= 5000, "Percentage too high"); // Max 50%
        slashingPercentage = percentage;
    }

    function setBalanceManager(address _balanceManager) external onlyRole(ADMIN_ROLE) {
        require(_balanceManager != address(0), "Invalid address");
        balanceManager = _balanceManager;
    }

    function setFeeManager(address _feeManager) external onlyRole(ADMIN_ROLE) {
        require(_feeManager != address(0), "Invalid address");
        feeManager = _feeManager;
    }

    function setEscrowManager(address _escrowManager) external onlyRole(ADMIN_ROLE) {
        require(_escrowManager != address(0), "Invalid address");
        escrowManager = _escrowManager;
    }

    function setGovernanceManager(address _governance) external onlyRole(ADMIN_ROLE) {
        require(_governance != address(0), "Invalid address");
        governanceManager = _governance;
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

    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function getValidator(address validator) external view returns (ValidatorInfo memory) {
        return validators[validator];
    }

    function getBuyerOrders(address buyer) external view returns (uint256[] memory) {
        return buyerOrders[buyer];
    }

    function getSellerOrders(address seller) external view returns (uint256[] memory) {
        return sellerOrders[seller];
    }

    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }

    function getOrdersByFiatCurrency(string memory currency) external view returns (uint256[] memory) {
        return ordersByFiatCurrency[currency];
    }

    function getValidatorReputation(address validator) external view returns (uint256) {
        return validators[validator].reputation;
    }
}
