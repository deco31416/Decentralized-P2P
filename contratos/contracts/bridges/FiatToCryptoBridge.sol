// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IAssetManager.sol";

/**
 * @title FiatToCryptoBridge
 * @notice Puente descentralizado fiat → crypto con sistema de validación
 * @dev Sistema de 3 partes: buyer (fiat), seller (crypto), validator
 * 
 * Características principales:
 * - Intercambios fiat → crypto descentralizados
 * - Sellers depositan crypto en escrow primero
 * - Buyers pagan fiat off-chain
 * - Validadores confirman recepción de fiat
 * - Sistema de reputación para validadores
 * - Slashing por comportamiento malicioso
 * - Timeouts para prevenir bloqueo de fondos
 * - Dispute resolution con votación
 * 
 * Flujo principal:
 * 1. Seller crea oferta → deposita crypto → escrow activado
 * 2. Buyer acepta oferta → promete pagar fiat off-chain
 * 3. Buyer envía fiat off-chain (banco, transferencia, etc)
 * 4. Validator confirma recepción de fiat → libera crypto a buyer
 * 5. Si hay disputa → votación de validadores → resolver
 * 
 * Roles:
 * - Seller: Vende crypto por fiat (deposita crypto primero)
 * - Buyer: Compra crypto con fiat (paga fiat off-chain)
 * - Validator: Confirma pago fiat (requiere 10k CAMBIO stake)
 * 
 * Diferencias con CryptoToFiatBridge:
 * - Seller deposita crypto primero (no buyer)
 * - Buyer no necesita depositar nada on-chain
 * - Más común para on-ramping (fiat → crypto)
 */
contract FiatToCryptoBridge is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Rol de validator
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    /// @notice Estados de una oferta
    enum OfferStatus {
        Created,            // Creada, esperando crypto
        Active,             // Crypto depositado, visible para buyers
        Matched,            // Buyer asignado, esperando pago fiat
        FiatPending,        // Buyer dice que pagó fiat, esperando confirmación
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

    /// @notice Estructura de una oferta fiat → crypto
    struct Offer {
        uint256 offerId;
        address seller;             // Vende crypto por fiat
        address buyer;              // Compra crypto con fiat
        address validator;          // Validador asignado
        address cryptoToken;        // Token crypto a vender
        uint256 cryptoAmount;       // Cantidad de crypto
        string fiatCurrency;        // Moneda fiat (USD, EUR, etc)
        uint256 fiatAmount;         // Cantidad de fiat
        uint256 exchangeRate;       // Tasa de cambio (fiat per crypto * 1e18)
        PaymentMethod[] acceptedMethods; // Métodos aceptados por seller
        string paymentDetails;      // Detalles de pago del seller
        OfferStatus status;
        uint256 createdAt;
        uint256 matchedAt;
        uint256 fiatSentAt;
        uint256 validatedAt;
        uint256 completedAt;
        uint256 timeoutAt;
        bool sellerConfirmed;
        bool buyerConfirmed;
        bool validatorConfirmed;
        string disputeReason;
        uint256 minFiatAmount;      // Mínimo por transacción
        uint256 maxFiatAmount;      // Máximo por transacción
        bool partialFillAllowed;    // Permitir fills parciales
    }

    /// @notice Información de validator (compartida con CryptoToFiatBridge)
    struct ValidatorInfo {
        address validator;
        uint256 stake;
        uint256 totalValidations;
        uint256 successfulValidations;
        uint256 disputedValidations;
        uint256 slashedAmount;
        bool active;
        uint256 registeredAt;
        uint256 reputation;
    }

    /// @notice Contador de ofertas
    uint256 public offerCount;

    /// @notice Mapeo de ID a oferta
    mapping(uint256 => Offer) public offers;
    
    /// @notice Ofertas de un usuario (como seller)
    mapping(address => uint256[]) public sellerOffers;
    
    /// @notice Compras de un usuario (como buyer)
    mapping(address => uint256[]) public buyerPurchases;
    
    /// @notice Información de validadores
    mapping(address => ValidatorInfo) public validators;
    
    /// @notice Lista de validadores activos
    address[] public activeValidators;

    /// @notice Ofertas activas por moneda fiat
    mapping(string => uint256[]) public offersByFiatCurrency;
    
    /// @notice Ofertas activas por método de pago
    mapping(uint8 => uint256[]) public offersByPaymentMethod;

    /// @notice Stake mínimo para ser validator (10,000 CAMBIO)
    uint256 public minValidatorStake = 10000 * 10**18;
    
    /// @notice Timeout por defecto (48 horas)
    uint256 public defaultTimeout = 48 hours;
    
    /// @notice Fee del bridge (1%)
    uint256 public bridgeFee = 100; // basis points

    /// @notice Porcentaje de slashing (10%)
    uint256 public slashingPercentage = 1000; // basis points

    /// @notice Referencia al token CAMBIO
    address public cambioToken;
    
    /// @notice Referencia al BalanceManager
    address public balanceManager;
    
    /// @notice Referencia al FeeManager
    address public feeManager;
    
    /// @notice Referencia al CryptoToFiatBridge (para compartir validators)
    address public cryptoToFiatBridge;

    /// @notice Referencia al AssetManager
    address public assetManager;

    // ============================================
    // EVENTOS
    // ============================================

    event OfferCreated(
        uint256 indexed offerId,
        address indexed seller,
        address cryptoToken,
        uint256 cryptoAmount,
        string fiatCurrency,
        uint256 fiatAmount
    );

    event OfferMatched(
        uint256 indexed offerId,
        address indexed buyer,
        address indexed validator,
        uint256 fiatAmount
    );

    event FiatPaymentSent(
        uint256 indexed offerId,
        address indexed buyer,
        uint256 timestamp
    );

    event OfferValidated(
        uint256 indexed offerId,
        address indexed validator,
        bool approved
    );

    event OfferCompleted(
        uint256 indexed offerId,
        uint256 timestamp
    );

    event OfferCancelled(
        uint256 indexed offerId,
        address canceller
    );

    event DisputeRaised(
        uint256 indexed offerId,
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
        address _feeManager
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_cambioToken != address(0), "Invalid token");
        require(_balanceManager != address(0), "Invalid balance manager");
        require(_feeManager != address(0), "Invalid fee manager");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        cambioToken = _cambioToken;
        balanceManager = _balanceManager;
        feeManager = _feeManager;
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
            reputation: 100
        });

        activeValidators.push(msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);

        emit ValidatorRegistered(msg.sender, stakeAmount);
    }

    /**
     * @notice Añade más stake
     */
    function addValidatorStake(uint256 amount) external nonReentrant {
        require(validators[msg.sender].active, "Not a validator");
        require(amount > 0, "Invalid amount");

        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), amount);
        validators[msg.sender].stake += amount;
    }

    /**
     * @notice Retira stake
     */
    function withdrawValidatorStake(uint256 amount) external nonReentrant {
        ValidatorInfo storage validator = validators[msg.sender];
        require(validator.active, "Not a validator");
        require(amount <= validator.stake, "Insufficient stake");
        require(validator.stake - amount >= minValidatorStake, "Below minimum");

        validator.stake -= amount;
        IERC20(cambioToken).safeTransfer(msg.sender, amount);
    }

    // ============================================
    // CREACIÓN DE OFERTAS
    // ============================================

    /**
     * @notice Crea una oferta fiat → crypto (seller deposita crypto)
     * @param cryptoToken Token crypto a vender
     * @param cryptoAmount Cantidad de crypto
     * @param fiatCurrency Moneda fiat
     * @param fiatAmount Cantidad de fiat
     * @param acceptedMethods Métodos de pago aceptados
     * @param paymentDetails Detalles de pago del seller
     * @param minFiatAmount Mínimo por transacción
     * @param maxFiatAmount Máximo por transacción
     */
    function createOffer(
        address cryptoToken,
        uint256 cryptoAmount,
        string memory fiatCurrency,
        uint256 fiatAmount,
        PaymentMethod[] memory acceptedMethods,
        string memory paymentDetails,
        uint256 minFiatAmount,
        uint256 maxFiatAmount
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(cryptoToken != address(0), "Invalid token");
        require(cryptoAmount > 0, "Invalid crypto amount");
        require(fiatAmount > 0, "Invalid fiat amount");
        require(bytes(fiatCurrency).length > 0, "Invalid currency");
        require(acceptedMethods.length > 0, "No payment methods");
        require(bytes(paymentDetails).length > 0, "Payment details required");
        require(minFiatAmount <= fiatAmount, "Min exceeds total");
        require(maxFiatAmount >= minFiatAmount, "Max below min");

        // Validar con AssetManager si está configurado
        if (assetManager != address(0)) {
            require(
                IAssetManager(assetManager).canTokenBeTraded(cryptoToken),
                "Token not tradeable in AssetManager"
            );
            
            // Nota: La validación de métodos de pago fiat se hace en el frontend
            // consultando AssetManager.getActiveFiatMethods() y filtrando por currency
        }

        // Bloquear crypto en escrow
        _lockFunds(msg.sender, cryptoToken, cryptoAmount);

        offerCount++;
        uint256 exchangeRate = (fiatAmount * 1e18) / cryptoAmount;

        Offer storage offer = offers[offerCount];
        offer.offerId = offerCount;
        offer.seller = msg.sender;
        offer.buyer = address(0);
        offer.validator = address(0);
        offer.cryptoToken = cryptoToken;
        offer.cryptoAmount = cryptoAmount;
        offer.fiatCurrency = fiatCurrency;
        offer.fiatAmount = fiatAmount;
        offer.exchangeRate = exchangeRate;
        offer.paymentDetails = paymentDetails;
        offer.status = OfferStatus.Active;
        offer.createdAt = block.timestamp;
        offer.timeoutAt = block.timestamp + (defaultTimeout * 2); // Más tiempo para ofertas
        offer.minFiatAmount = minFiatAmount;
        offer.maxFiatAmount = maxFiatAmount;
        offer.partialFillAllowed = minFiatAmount < fiatAmount;
        
        // Copiar métodos aceptados
        for (uint256 i = 0; i < acceptedMethods.length; i++) {
            offer.acceptedMethods.push(acceptedMethods[i]);
        }

        sellerOffers[msg.sender].push(offerCount);
        offersByFiatCurrency[fiatCurrency].push(offerCount);

        // Indexar por cada método de pago
        for (uint256 i = 0; i < acceptedMethods.length; i++) {
            offersByPaymentMethod[uint8(acceptedMethods[i])].push(offerCount);
        }

        emit OfferCreated(
            offerCount,
            msg.sender,
            cryptoToken,
            cryptoAmount,
            fiatCurrency,
            fiatAmount
        );

        return offerCount;
    }

    // ============================================
    // MATCHING Y EJECUCIÓN
    // ============================================

    /**
     * @notice Buyer acepta una oferta
     * @param offerId ID de la oferta
     * @param fiatAmount Cantidad de fiat a comprar (para partial fills)
     */
    function acceptOffer(uint256 offerId, uint256 fiatAmount) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        Offer storage offer = offers[offerId];
        
        require(offer.status == OfferStatus.Active, "Offer not active");
        require(offer.seller != msg.sender, "Cannot accept own offer");
        require(block.timestamp < offer.timeoutAt, "Offer expired");
        require(fiatAmount >= offer.minFiatAmount, "Below minimum");
        require(fiatAmount <= offer.maxFiatAmount, "Above maximum");
        require(fiatAmount <= offer.fiatAmount, "Exceeds available");

        // Asignar validator
        address selectedValidator = _selectValidator();
        require(selectedValidator != address(0), "No validators available");

        offer.buyer = msg.sender;
        offer.validator = selectedValidator;
        offer.status = OfferStatus.Matched;
        offer.matchedAt = block.timestamp;
        offer.timeoutAt = block.timestamp + defaultTimeout; // Reset timeout

        // Si es partial fill, actualizar montos
        if (fiatAmount < offer.fiatAmount) {
            require(offer.partialFillAllowed, "Partial fills not allowed");
            offer.fiatAmount = fiatAmount;
            offer.cryptoAmount = (fiatAmount * 1e18) / offer.exchangeRate;
        }

        buyerPurchases[msg.sender].push(offerId);

        emit OfferMatched(offerId, msg.sender, selectedValidator, fiatAmount);
    }

    /**
     * @notice Buyer confirma que envió el pago fiat
     * @param offerId ID de la oferta
     */
    function confirmFiatSent(uint256 offerId, string memory /* paymentProof */) 
        external 
        nonReentrant 
    {
        Offer storage offer = offers[offerId];
        
        require(offer.buyer == msg.sender, "Not buyer");
        require(offer.status == OfferStatus.Matched, "Invalid status");
        require(block.timestamp < offer.timeoutAt, "Offer expired");

        offer.status = OfferStatus.FiatPending;
        offer.fiatSentAt = block.timestamp;
        offer.buyerConfirmed = true;

        emit FiatPaymentSent(offerId, msg.sender, block.timestamp);
    }

    /**
     * @notice Seller confirma recepción de fiat (opcional, acelera proceso)
     * @param offerId ID de la oferta
     */
    function confirmFiatReceived(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        
        require(offer.seller == msg.sender, "Not seller");
        require(offer.status == OfferStatus.FiatPending, "Invalid status");

        offer.sellerConfirmed = true;
        
        // Si seller confirma, puede liberar directamente sin esperar validator
        // (opcional, según configuración de seguridad)
    }

    /**
     * @notice Validator confirma recepción de fiat y libera crypto
     * @param offerId ID de la oferta
     * @param approved true si confirma, false si rechaza
     */
    function validateOffer(
        uint256 offerId,
        bool approved,
        string memory /* evidence */
    ) external nonReentrant onlyRole(VALIDATOR_ROLE) {
        Offer storage offer = offers[offerId];
        
        require(offer.validator == msg.sender, "Not assigned validator");
        require(offer.status == OfferStatus.FiatPending, "Invalid status");

        ValidatorInfo storage validator = validators[msg.sender];
        validator.totalValidations++;

        if (approved) {
            // Liberar crypto al buyer
            uint256 fee = (offer.cryptoAmount * bridgeFee) / 10000;
            uint256 buyerAmount = offer.cryptoAmount - fee;

            _transferLocked(offer.seller, offer.buyer, offer.cryptoToken, buyerAmount);
            
            if (fee > 0) {
                _transferLocked(offer.seller, feeManager, offer.cryptoToken, fee);
            }

            offer.status = OfferStatus.Completed;
            offer.completedAt = block.timestamp;
            offer.validatorConfirmed = true;

            validator.successfulValidations++;
            
            // Reward al validator
            uint256 reward = (offer.cryptoAmount * 10) / 10000; // 0.1%
            if (reward > 0) {
                IERC20(cambioToken).safeTransfer(msg.sender, reward);
                emit ValidatorRewardPaid(msg.sender, reward);
            }

            emit OfferCompleted(offerId, block.timestamp);
        } else {
            // Rechazado - devolver crypto al seller
            _unlockFunds(offer.seller, offer.cryptoToken, offer.cryptoAmount);
            offer.status = OfferStatus.Cancelled;
        }

        offer.validatedAt = block.timestamp;
        emit OfferValidated(offerId, msg.sender, approved);
    }

    // ============================================
    // DISPUTAS
    // ============================================

    /**
     * @notice Levanta una disputa
     * @param offerId ID de la oferta
     * @param reason Razón
     */
    function raiseDispute(uint256 offerId, string memory reason) 
        external 
        nonReentrant 
    {
        Offer storage offer = offers[offerId];
        
        require(
            offer.buyer == msg.sender || offer.seller == msg.sender,
            "Not participant"
        );
        require(
            offer.status == OfferStatus.Matched ||
            offer.status == OfferStatus.FiatPending,
            "Cannot dispute"
        );
        require(bytes(reason).length > 0, "Reason required");

        offer.status = OfferStatus.Disputed;
        offer.disputeReason = reason;

        emit DisputeRaised(offerId, msg.sender, reason);
    }

    /**
     * @notice Resuelve una disputa
     * @param offerId ID de la oferta
     * @param favorSeller true si favorece al seller, false si al buyer
     * @param slashValidator true si penalizar validator
     */
    function resolveDispute(
        uint256 offerId,
        bool favorSeller,
        bool slashValidator
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.status == OfferStatus.Disputed, "Not disputed");

        if (favorSeller) {
            // Devolver crypto al seller
            _unlockFunds(offer.seller, offer.cryptoToken, offer.cryptoAmount);
        } else {
            // Liberar crypto al buyer
            uint256 fee = (offer.cryptoAmount * bridgeFee) / 10000;
            uint256 buyerAmount = offer.cryptoAmount - fee;
            _transferLocked(offer.seller, offer.buyer, offer.cryptoToken, buyerAmount);
            
            if (fee > 0) {
                _transferLocked(offer.seller, feeManager, offer.cryptoToken, fee);
            }
        }

        if (slashValidator && offer.validator != address(0)) {
            ValidatorInfo storage validator = validators[offer.validator];
            uint256 slashAmount = (validator.stake * slashingPercentage) / 10000;
            
            validator.stake -= slashAmount;
            validator.slashedAmount += slashAmount;
            validator.disputedValidations++;
            validator.reputation = validator.reputation > 10 ? validator.reputation - 10 : 0;

            IERC20(cambioToken).safeTransfer(feeManager, slashAmount);

            emit ValidatorSlashed(offer.validator, slashAmount, "Dispute resolved against");
        }

        offer.status = OfferStatus.Resolved;
        offer.completedAt = block.timestamp;
    }

    // ============================================
    // CANCELACIÓN Y TIMEOUTS
    // ============================================

    /**
     * @notice Cancela una oferta no matched
     * @param offerId ID de la oferta
     */
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        
        require(offer.seller == msg.sender, "Not seller");
        require(offer.status == OfferStatus.Active, "Cannot cancel");

        _unlockFunds(msg.sender, offer.cryptoToken, offer.cryptoAmount);
        offer.status = OfferStatus.Cancelled;

        emit OfferCancelled(offerId, msg.sender);
    }

    /**
     * @notice Procesa timeouts
     */
    function processTimeouts(uint256[] calldata offerIds) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        for (uint256 i = 0; i < offerIds.length; i++) {
            Offer storage offer = offers[offerIds[i]];
            
            if (
                block.timestamp >= offer.timeoutAt &&
                (offer.status == OfferStatus.Active ||
                 offer.status == OfferStatus.Matched ||
                 offer.status == OfferStatus.FiatPending)
            ) {
                _unlockFunds(offer.seller, offer.cryptoToken, offer.cryptoAmount);
                offer.status = OfferStatus.TimedOut;
            }
        }
    }

    // ============================================
    // FUNCIONES AUXILIARES
    // ============================================

    function _selectValidator() internal view returns (address) {
        if (activeValidators.length == 0) return address(0);
        
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            offerCount
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
        require(fee <= 500, "Fee too high");
        bridgeFee = fee;
    }

    function setSlashingPercentage(uint256 percentage) external onlyRole(ADMIN_ROLE) {
        require(percentage <= 5000, "Percentage too high");
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

    function setCryptoToFiatBridge(address _bridge) external onlyRole(ADMIN_ROLE) {
        require(_bridge != address(0), "Invalid address");
        cryptoToFiatBridge = _bridge;
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

    function getOffer(uint256 offerId) external view returns (
        uint256 id,
        address seller,
        address buyer,
        address cryptoToken,
        uint256 cryptoAmount,
        string memory fiatCurrency,
        uint256 fiatAmount,
        OfferStatus status,
        uint256 createdAt
    ) {
        Offer storage offer = offers[offerId];
        return (
            offer.offerId,
            offer.seller,
            offer.buyer,
            offer.cryptoToken,
            offer.cryptoAmount,
            offer.fiatCurrency,
            offer.fiatAmount,
            offer.status,
            offer.createdAt
        );
    }

    function getOfferPaymentMethods(uint256 offerId) 
        external 
        view 
        returns (PaymentMethod[] memory) 
    {
        return offers[offerId].acceptedMethods;
    }

    function getValidator(address validator) external view returns (ValidatorInfo memory) {
        return validators[validator];
    }

    function getSellerOffers(address seller) external view returns (uint256[] memory) {
        return sellerOffers[seller];
    }

    function getBuyerPurchases(address buyer) external view returns (uint256[] memory) {
        return buyerPurchases[buyer];
    }

    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }

    function getOffersByFiatCurrency(string memory currency) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return offersByFiatCurrency[currency];
    }

    function getOffersByPaymentMethod(PaymentMethod method) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return offersByPaymentMethod[uint8(method)];
    }
}
