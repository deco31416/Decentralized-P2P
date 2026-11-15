// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IAssetManager.sol";

/**
 * @title P2PExchange
 * @notice Sistema de intercambio P2P crypto-crypto descentralizado
 * @dev Implementa atomic swaps con escrow automático
 * 
 * Características principales:
 * - Intercambios directos crypto-crypto sin intermediarios
 * - Atomic swaps garantizados con escrow
 * - Ofertas públicas y privadas (peer-specific)
 * - Negociación de precios entre pares
 * - Timeouts automáticos para prevenir bloqueo de fondos
 * - Dispute resolution integrado
 * - Rating system para usuarios
 * - Multi-token support
 * 
 * Flujos principales:
 * 1. Crear oferta → Bloquear fondos → Publicar en marketplace
 * 2. Aceptar oferta → Bloquear contrapartida → Iniciar swap
 * 3. Confirmar swap ambas partes → Liberar fondos cruzados
 * 4. Timeout/disputa → Resolver según evidencia → Liberar fondos
 * 
 * Estados de swap:
 * Created → Accepted → InProgress → Completed
 *           ↓          ↓
 *         Cancelled  Disputed → Resolved
 */
contract P2PExchange is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Rol de resolver disputas
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    /// @notice Estados de una oferta
    enum OfferStatus {
        Active,         // Activa, esperando aceptación
        Accepted,       // Aceptada, iniciando swap
        InProgress,     // Swap en progreso
        Completed,      // Completada exitosamente
        Cancelled,      // Cancelada por el creador
        Expired,        // Expirada por timeout
        Disputed        // En disputa
    }

    /// @notice Tipos de oferta
    enum OfferType {
        Public,         // Visible para todos
        Private         // Solo para un usuario específico
    }

    /// @notice Estados de confirmación del swap
    enum ConfirmationStatus {
        Pending,        // Esperando confirmación
        MakerConfirmed, // Maker confirmó
        TakerConfirmed, // Taker confirmó
        BothConfirmed   // Ambos confirmaron
    }

    /// @notice Estructura de una oferta P2P
    struct Offer {
        uint256 offerId;
        address maker;              // Creador de la oferta
        address taker;              // Aceptante (address(0) si es pública)
        address tokenOffered;       // Token que ofrece
        address tokenWanted;        // Token que quiere
        uint256 amountOffered;      // Cantidad que ofrece
        uint256 amountWanted;       // Cantidad que quiere
        uint256 minAmount;          // Cantidad mínima (para partial fills)
        uint256 maxAmount;          // Cantidad máxima
        OfferType offerType;
        OfferStatus status;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 acceptedAt;
        uint256 completedAt;
        bool partialFillAllowed;
        string description;         // Descripción opcional
        string paymentMethod;       // Método de pago (metadata)
    }

    /// @notice Estructura de un swap en progreso
    struct Swap {
        uint256 swapId;
        uint256 offerId;
        address maker;
        address taker;
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
        ConfirmationStatus confirmation;
        bool makerFundsLocked;
        bool takerFundsLocked;
        uint256 startedAt;
        uint256 timeoutAt;
        uint256 completedAt;
        OfferStatus status;
    }

    /// @notice Estructura de rating de usuario
    struct UserRating {
        uint256 totalTrades;
        uint256 successfulTrades;
        uint256 disputedTrades;
        uint256 totalRating;        // Suma de todas las calificaciones
        uint256 ratingCount;        // Número de calificaciones
        bool banned;
    }

    /// @notice Contador de ofertas
    uint256 public offerCount;
    
    /// @notice Contador de swaps
    uint256 public swapCount;

    /// @notice Mapeo de ID a oferta
    mapping(uint256 => Offer) public offers;
    
    /// @notice Mapeo de ID a swap
    mapping(uint256 => Swap) public swaps;
    
    /// @notice Ofertas de un usuario
    mapping(address => uint256[]) public userOffers;
    
    /// @notice Swaps de un usuario
    mapping(address => uint256[]) public userSwaps;
    
    /// @notice Ratings de usuarios
    mapping(address => UserRating) public userRatings;

    /// @notice Ofertas activas por par de tokens
    mapping(bytes32 => uint256[]) public offersByPair;

    /// @notice Referencia al AssetManager
    address public assetManager;

    /// @notice Referencia al BalanceManager
    address public balanceManager;
    
    /// @notice Referencia al FeeManager
    address public feeManager;
    
    /// @notice Referencia al DisputeManager
    address public disputeManager;
    
    /// @notice Referencia al CambiaCriptoMain
    address public mainContract;

    /// @notice Timeout por defecto para swaps (24 horas)
    uint256 public defaultSwapTimeout = 24 hours;
    
    /// @notice Tiempo máximo de expiración de ofertas (90 días)
    uint256 public constant MAX_OFFER_EXPIRATION = 90 days;
    
    /// @notice Rating mínimo para crear ofertas
    uint256 public minRatingToOffer = 0; // Sin restricción inicial

    // ============================================
    // EVENTOS
    // ============================================

    event OfferCreated(
        uint256 indexed offerId,
        address indexed maker,
        address tokenOffered,
        address tokenWanted,
        uint256 amountOffered,
        uint256 amountWanted,
        OfferType offerType
    );

    event OfferAccepted(
        uint256 indexed offerId,
        uint256 indexed swapId,
        address indexed taker,
        uint256 amountA,
        uint256 amountB
    );

    event SwapStarted(
        uint256 indexed swapId,
        uint256 indexed offerId,
        address maker,
        address taker
    );

    event SwapConfirmed(
        uint256 indexed swapId,
        address indexed confirmer,
        ConfirmationStatus status
    );

    event SwapCompleted(
        uint256 indexed swapId,
        uint256 indexed offerId,
        address maker,
        address taker,
        uint256 amountA,
        uint256 amountB
    );

    event OfferCancelled(
        uint256 indexed offerId,
        address indexed maker
    );

    event SwapTimedOut(
        uint256 indexed swapId,
        uint256 indexed offerId
    );

    event DisputeRaised(
        uint256 indexed swapId,
        address indexed raiser,
        string reason
    );

    event UserRated(
        address indexed user,
        address indexed rater,
        uint256 rating,
        uint256 swapId
    );

    event UserBanned(
        address indexed user,
        string reason
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _balanceManager,
        address _feeManager
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_balanceManager != address(0), "Invalid balance manager");
        require(_feeManager != address(0), "Invalid fee manager");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(RESOLVER_ROLE, _admin);

        balanceManager = _balanceManager;
        feeManager = _feeManager;
    }

    // ============================================
    // CREACIÓN DE OFERTAS
    // ============================================

    /**
     * @notice Crea una oferta pública
     * @param tokenOffered Token que ofrece
     * @param tokenWanted Token que quiere
     * @param amountOffered Cantidad que ofrece
     * @param amountWanted Cantidad que quiere
     * @param expiresIn Tiempo hasta expiración (segundos)
     * @param partialFillAllowed Permitir intercambios parciales
     * @param description Descripción de la oferta
     */
    function createPublicOffer(
        address tokenOffered,
        address tokenWanted,
        uint256 amountOffered,
        uint256 amountWanted,
        uint256 expiresIn,
        bool partialFillAllowed,
        string memory description
    ) external nonReentrant whenNotPaused returns (uint256) {
        return _createOffer(
            tokenOffered,
            tokenWanted,
            amountOffered,
            amountWanted,
            address(0),
            expiresIn,
            partialFillAllowed,
            description,
            OfferType.Public
        );
    }

    /**
     * @notice Crea una oferta privada para un usuario específico
     * @param tokenOffered Token que ofrece
     * @param tokenWanted Token que quiere
     * @param amountOffered Cantidad que ofrece
     * @param amountWanted Cantidad que quiere
     * @param specificTaker Usuario específico que puede aceptar
     * @param expiresIn Tiempo hasta expiración
     * @param description Descripción de la oferta
     */
    function createPrivateOffer(
        address tokenOffered,
        address tokenWanted,
        uint256 amountOffered,
        uint256 amountWanted,
        address specificTaker,
        uint256 expiresIn,
        string memory description
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(specificTaker != address(0), "Invalid taker");
        require(specificTaker != msg.sender, "Cannot offer to self");

        return _createOffer(
            tokenOffered,
            tokenWanted,
            amountOffered,
            amountWanted,
            specificTaker,
            expiresIn,
            false, // Private offers no partial fills
            description,
            OfferType.Private
        );
    }

    /**
     * @notice Función interna para crear ofertas
     */
    function _createOffer(
        address tokenOffered,
        address tokenWanted,
        uint256 amountOffered,
        uint256 amountWanted,
        address specificTaker,
        uint256 expiresIn,
        bool partialFillAllowed,
        string memory description,
        OfferType offerType
    ) internal returns (uint256) {
        require(tokenOffered != address(0) && tokenWanted != address(0), "Invalid tokens");
        require(tokenOffered != tokenWanted, "Same token");
        require(amountOffered > 0 && amountWanted > 0, "Invalid amounts");
        require(expiresIn <= MAX_OFFER_EXPIRATION, "Expiration too long");
        require(!userRatings[msg.sender].banned, "User banned");

        // Validar con AssetManager si está configurado
        if (assetManager != address(0)) {
            require(
                IAssetManager(assetManager).canTokenBeTraded(tokenOffered),
                "Token offered not tradeable"
            );
            require(
                IAssetManager(assetManager).canTokenBeTraded(tokenWanted),
                "Token wanted not tradeable"
            );
        }

        // Verificar rating mínimo
        if (userRatings[msg.sender].ratingCount > 0) {
            uint256 avgRating = userRatings[msg.sender].totalRating / userRatings[msg.sender].ratingCount;
            require(avgRating >= minRatingToOffer, "Rating too low");
        }

        // Bloquear fondos en BalanceManager
        _lockFunds(msg.sender, tokenOffered, amountOffered);

        offerCount++;
        uint256 expiresAt = expiresIn > 0 ? block.timestamp + expiresIn : 0;

        offers[offerCount] = Offer({
            offerId: offerCount,
            maker: msg.sender,
            taker: specificTaker,
            tokenOffered: tokenOffered,
            tokenWanted: tokenWanted,
            amountOffered: amountOffered,
            amountWanted: amountWanted,
            minAmount: partialFillAllowed ? amountOffered / 10 : amountOffered, // Min 10% si partial
            maxAmount: amountOffered,
            offerType: offerType,
            status: OfferStatus.Active,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            acceptedAt: 0,
            completedAt: 0,
            partialFillAllowed: partialFillAllowed,
            description: description,
            paymentMethod: ""
        });

        userOffers[msg.sender].push(offerCount);

        // Añadir a ofertas por par
        bytes32 pairId = _getPairId(tokenOffered, tokenWanted);
        offersByPair[pairId].push(offerCount);

        emit OfferCreated(
            offerCount,
            msg.sender,
            tokenOffered,
            tokenWanted,
            amountOffered,
            amountWanted,
            offerType
        );

        return offerCount;
    }

    // ============================================
    // ACEPTACIÓN Y EJECUCIÓN
    // ============================================

    /**
     * @notice Acepta una oferta y crea un swap
     * @param offerId ID de la oferta
     * @param amount Cantidad a intercambiar (para partial fills)
     */
    function acceptOffer(uint256 offerId, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (uint256) 
    {
        Offer storage offer = offers[offerId];
        
        require(offer.status == OfferStatus.Active, "Offer not active");
        require(offer.maker != msg.sender, "Cannot accept own offer");
        require(!userRatings[msg.sender].banned, "User banned");
        
        // Verificar si es oferta privada
        if (offer.offerType == OfferType.Private) {
            require(offer.taker == msg.sender, "Not authorized");
        }
        
        // Verificar expiración
        if (offer.expiresAt > 0) {
            require(block.timestamp < offer.expiresAt, "Offer expired");
        }
        
        // Verificar cantidad
        require(amount >= offer.minAmount && amount <= offer.amountOffered, "Invalid amount");
        
        if (!offer.partialFillAllowed) {
            require(amount == offer.amountOffered, "Must take full amount");
        }

        // Calcular cantidad correspondiente de tokenWanted
        uint256 wantedAmount = (amount * offer.amountWanted) / offer.amountOffered;

        // Bloquear fondos del taker
        _lockFunds(msg.sender, offer.tokenWanted, wantedAmount);

        // Crear swap
        swapCount++;
        
        swaps[swapCount] = Swap({
            swapId: swapCount,
            offerId: offerId,
            maker: offer.maker,
            taker: msg.sender,
            tokenA: offer.tokenOffered,
            tokenB: offer.tokenWanted,
            amountA: amount,
            amountB: wantedAmount,
            confirmation: ConfirmationStatus.Pending,
            makerFundsLocked: true,
            takerFundsLocked: true,
            startedAt: block.timestamp,
            timeoutAt: block.timestamp + defaultSwapTimeout,
            completedAt: 0,
            status: OfferStatus.InProgress
        });

        offer.status = OfferStatus.Accepted;
        offer.taker = msg.sender;
        offer.acceptedAt = block.timestamp;

        userSwaps[offer.maker].push(swapCount);
        userSwaps[msg.sender].push(swapCount);

        emit OfferAccepted(offerId, swapCount, msg.sender, amount, wantedAmount);
        emit SwapStarted(swapCount, offerId, offer.maker, msg.sender);

        return swapCount;
    }

    /**
     * @notice Confirma la recepción de fondos (ambas partes deben confirmar)
     * @param swapId ID del swap
     */
    function confirmSwap(uint256 swapId) external nonReentrant {
        Swap storage swap = swaps[swapId];
        
        require(swap.status == OfferStatus.InProgress, "Swap not in progress");
        require(swap.maker == msg.sender || swap.taker == msg.sender, "Not participant");
        require(block.timestamp < swap.timeoutAt, "Swap timed out");

        if (msg.sender == swap.maker) {
            require(
                swap.confirmation == ConfirmationStatus.Pending ||
                swap.confirmation == ConfirmationStatus.TakerConfirmed,
                "Already confirmed"
            );
            
            if (swap.confirmation == ConfirmationStatus.Pending) {
                swap.confirmation = ConfirmationStatus.MakerConfirmed;
            } else {
                swap.confirmation = ConfirmationStatus.BothConfirmed;
            }
        } else {
            require(
                swap.confirmation == ConfirmationStatus.Pending ||
                swap.confirmation == ConfirmationStatus.MakerConfirmed,
                "Already confirmed"
            );
            
            if (swap.confirmation == ConfirmationStatus.Pending) {
                swap.confirmation = ConfirmationStatus.TakerConfirmed;
            } else {
                swap.confirmation = ConfirmationStatus.BothConfirmed;
            }
        }

        emit SwapConfirmed(swapId, msg.sender, swap.confirmation);

        // Si ambos confirmaron, ejecutar swap
        if (swap.confirmation == ConfirmationStatus.BothConfirmed) {
            _completeSwap(swapId);
        }
    }

    /**
     * @notice Completa un swap (transfiere fondos)
     * @param swapId ID del swap
     */
    function _completeSwap(uint256 swapId) internal {
        Swap storage swap = swaps[swapId];
        Offer storage offer = offers[swap.offerId];

        require(swap.status == OfferStatus.InProgress, "Invalid status");

        // Cobrar fees
        uint256 feeA = _calculateFee(swap.maker, swap.amountA);
        uint256 feeB = _calculateFee(swap.taker, swap.amountB);

        // Transferir fondos cruzados usando BalanceManager
        _executeSwap(
            swap.maker,
            swap.taker,
            swap.tokenA,
            swap.tokenB,
            swap.amountA - feeA,
            swap.amountB - feeB
        );

        // Actualizar estados
        swap.status = OfferStatus.Completed;
        swap.completedAt = block.timestamp;
        offer.status = OfferStatus.Completed;
        offer.completedAt = block.timestamp;

        // Actualizar ratings
        userRatings[swap.maker].totalTrades++;
        userRatings[swap.maker].successfulTrades++;
        userRatings[swap.taker].totalTrades++;
        userRatings[swap.taker].successfulTrades++;

        emit SwapCompleted(
            swapId,
            swap.offerId,
            swap.maker,
            swap.taker,
            swap.amountA,
            swap.amountB
        );
    }

    // ============================================
    // CANCELACIÓN Y TIMEOUTS
    // ============================================

    /**
     * @notice Cancela una oferta activa
     * @param offerId ID de la oferta
     */
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        
        require(offer.maker == msg.sender, "Not offer maker");
        require(offer.status == OfferStatus.Active, "Cannot cancel");

        // Liberar fondos bloqueados
        _unlockFunds(msg.sender, offer.tokenOffered, offer.amountOffered);

        offer.status = OfferStatus.Cancelled;

        emit OfferCancelled(offerId, msg.sender);
    }

    /**
     * @notice Procesa timeouts de swaps (llamado por keeper)
     * @param swapIds Array de IDs de swaps a verificar
     */
    function processTimeouts(uint256[] calldata swapIds) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        for (uint256 i = 0; i < swapIds.length; i++) {
            Swap storage swap = swaps[swapIds[i]];
            
            if (
                swap.status == OfferStatus.InProgress &&
                block.timestamp >= swap.timeoutAt
            ) {
                // Devolver fondos a ambas partes
                if (swap.makerFundsLocked) {
                    _unlockFunds(swap.maker, swap.tokenA, swap.amountA);
                }
                if (swap.takerFundsLocked) {
                    _unlockFunds(swap.taker, swap.tokenB, swap.amountB);
                }

                swap.status = OfferStatus.Expired;
                offers[swap.offerId].status = OfferStatus.Expired;

                emit SwapTimedOut(swapIds[i], swap.offerId);
            }
        }
    }

    // ============================================
    // DISPUTAS
    // ============================================

    /**
     * @notice Levanta una disputa sobre un swap
     * @param swapId ID del swap
     * @param reason Razón de la disputa
     */
    function raiseDispute(uint256 swapId, string memory reason) 
        external 
        nonReentrant 
    {
        Swap storage swap = swaps[swapId];
        
        require(swap.maker == msg.sender || swap.taker == msg.sender, "Not participant");
        require(swap.status == OfferStatus.InProgress, "Invalid status");
        require(bytes(reason).length > 0, "Reason required");

        swap.status = OfferStatus.Disputed;
        offers[swap.offerId].status = OfferStatus.Disputed;

        // Registrar disputa en DisputeManager
        if (disputeManager != address(0)) {
            (bool success, ) = disputeManager.call(
                abi.encodeWithSignature(
                    "createDispute(uint256,address,address,string)",
                    swapId,
                    swap.maker,
                    swap.taker,
                    reason
                )
            );
            require(success, "Failed to create dispute");
        }

        emit DisputeRaised(swapId, msg.sender, reason);
    }

    /**
     * @notice Resuelve una disputa (solo RESOLVER_ROLE)
     * @param swapId ID del swap
     * @param favorMaker true si se favorece al maker, false si al taker
     */
    function resolveDispute(uint256 swapId, bool favorMaker) 
        external 
        onlyRole(RESOLVER_ROLE) 
        nonReentrant 
    {
        Swap storage swap = swaps[swapId];
        
        require(swap.status == OfferStatus.Disputed, "Not disputed");

        if (favorMaker) {
            // Devolver fondos al maker, liberar taker
            _unlockFunds(swap.maker, swap.tokenA, swap.amountA);
            _unlockFunds(swap.taker, swap.tokenB, swap.amountB);
            
            // Penalizar taker
            userRatings[swap.taker].disputedTrades++;
        } else {
            // Devolver fondos al taker, liberar maker
            _unlockFunds(swap.maker, swap.tokenA, swap.amountA);
            _unlockFunds(swap.taker, swap.tokenB, swap.amountB);
            
            // Penalizar maker
            userRatings[swap.maker].disputedTrades++;
        }

        swap.status = OfferStatus.Completed;
        offers[swap.offerId].status = OfferStatus.Completed;
    }

    // ============================================
    // RATING SYSTEM
    // ============================================

    /**
     * @notice Califica a un usuario después de un swap
     * @param swapId ID del swap
     * @param rating Calificación (1-5)
     */
    function rateUser(uint256 swapId, uint256 rating) external {
        Swap storage swap = swaps[swapId];
        
        require(swap.status == OfferStatus.Completed, "Swap not completed");
        require(swap.maker == msg.sender || swap.taker == msg.sender, "Not participant");
        require(rating >= 1 && rating <= 5, "Invalid rating");

        address ratedUser = swap.maker == msg.sender ? swap.taker : swap.maker;
        
        userRatings[ratedUser].totalRating += rating;
        userRatings[ratedUser].ratingCount++;

        emit UserRated(ratedUser, msg.sender, rating, swapId);
    }

    /**
     * @notice Banea a un usuario (solo ADMIN)
     * @param user Dirección del usuario
     * @param reason Razón del ban
     */
    function banUser(address user, string memory reason) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(user != address(0), "Invalid user");
        userRatings[user].banned = true;
        emit UserBanned(user, reason);
    }

    /**
     * @notice Desbanea a un usuario (solo ADMIN)
     * @param user Dirección del usuario
     */
    function unbanUser(address user) external onlyRole(ADMIN_ROLE) {
        require(user != address(0), "Invalid user");
        userRatings[user].banned = false;
    }

    // ============================================
    // FUNCIONES AUXILIARES
    // ============================================

    function _getPairId(address tokenA, address tokenB) internal pure returns (bytes32) {
        return tokenA < tokenB 
            ? keccak256(abi.encodePacked(tokenA, tokenB))
            : keccak256(abi.encodePacked(tokenB, tokenA));
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

    function _executeSwap(
        address maker,
        address taker,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal {
        (bool success, ) = balanceManager.call(
            abi.encodeWithSignature(
                "transferLocked(address,address,address,uint256)",
                maker, taker, tokenA, amountA
            )
        );
        require(success, "Swap failed");

        (success, ) = balanceManager.call(
            abi.encodeWithSignature(
                "transferLocked(address,address,address,uint256)",
                taker, maker, tokenB, amountB
            )
        );
        require(success, "Swap failed");
    }

    function _calculateFee(address user, uint256 amount) internal view returns (uint256) {
        (bool success, bytes memory data) = feeManager.staticcall(
            abi.encodeWithSignature("calculateFee(address,uint256,uint256)", user, amount, 0)
        );
        require(success, "Fee calculation failed");
        return abi.decode(data, (uint256));
    }

    // ============================================
    // SETTERS
    // ============================================

    function setBalanceManager(address _balanceManager) external onlyRole(ADMIN_ROLE) {
        require(_balanceManager != address(0), "Invalid address");
        balanceManager = _balanceManager;
    }

    function setFeeManager(address _feeManager) external onlyRole(ADMIN_ROLE) {
        require(_feeManager != address(0), "Invalid address");
        feeManager = _feeManager;
    }

    function setDisputeManager(address _disputeManager) external onlyRole(ADMIN_ROLE) {
        require(_disputeManager != address(0), "Invalid address");
        disputeManager = _disputeManager;
    }

    function setMainContract(address _mainContract) external onlyRole(ADMIN_ROLE) {
        require(_mainContract != address(0), "Invalid address");
        mainContract = _mainContract;
    }

    function setAssetManager(address _assetManager) external onlyRole(ADMIN_ROLE) {
        require(_assetManager != address(0), "Invalid address");
        assetManager = _assetManager;
    }

    function setDefaultSwapTimeout(uint256 timeout) external onlyRole(ADMIN_ROLE) {
        require(timeout >= 1 hours && timeout <= 7 days, "Invalid timeout");
        defaultSwapTimeout = timeout;
    }

    function setMinRatingToOffer(uint256 rating) external onlyRole(ADMIN_ROLE) {
        require(rating <= 5, "Invalid rating");
        minRatingToOffer = rating;
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

    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    function getSwap(uint256 swapId) external view returns (Swap memory) {
        return swaps[swapId];
    }

    function getUserOffers(address user) external view returns (uint256[] memory) {
        return userOffers[user];
    }

    function getUserSwaps(address user) external view returns (uint256[] memory) {
        return userSwaps[user];
    }

    function getUserRating(address user) external view returns (UserRating memory) {
        return userRatings[user];
    }

    function getOffersByPair(bytes32 pairId) external view returns (uint256[] memory) {
        return offersByPair[pairId];
    }

    function getAverageRating(address user) external view returns (uint256) {
        if (userRatings[user].ratingCount == 0) return 0;
        return userRatings[user].totalRating / userRatings[user].ratingCount;
    }

    /**
     * @notice Obtiene estadísticas globales del P2P Exchange
     */
    function getStats() external view returns (
        uint256 totalOffers,
        uint256 totalSwaps,
        uint256 completedSwaps,
        uint256 activeOffers,
        uint256 totalUsers
    ) {
        totalOffers = offerCount;
        totalSwaps = swapCount;
        
        // Contar swaps completados
        uint256 completed = 0;
        for (uint256 i = 1; i <= swapCount; i++) {
            if (swaps[i].status == OfferStatus.Completed) {
                completed++;
            }
        }
        completedSwaps = completed;
        
        // Contar ofertas activas
        uint256 active = 0;
        for (uint256 i = 1; i <= offerCount; i++) {
            if (offers[i].status == OfferStatus.Active) {
                active++;
            }
        }
        activeOffers = active;
        
        // Contar usuarios únicos (aproximado basado en ratings)
        totalUsers = 0; // Se puede mejorar con un Set off-chain
    }
}
