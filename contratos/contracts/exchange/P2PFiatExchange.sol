// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IP2PFiatExchange.sol";
import "../interfaces/IFiatFeeManager.sol";
import "../interfaces/IFiatDisputeResolver.sol";

/**
 * @title P2PFiatExchange
 * @notice Sistema de intercambio P2P fiat-to-fiat descentralizado
 * @dev Implementa flujo Usuario → Intermediario → Usuario con escrow USDT
 * 
 * Características principales:
 * - Órdenes fiat-to-fiat (USD → COP, EUR → MXN, etc.)
 * - Intermediarios con liquidez USDT bloqueada
 * - Comisiones dobles configurables (entrada + salida)
 * - Sistema de comprobantes bancarios (IPFS)
 * - Timeouts automáticos (24h)
 * - Resolución de disputas por admin
 * 
 * Flujo completo:
 * 1. Usuario: createFiatToFiatOrder("USD", "COP", 1000, 5000)
 * 2. Intermediario: acceptFiatOrder(orderId) → Bloquea 1000 USDT
 * 3. Usuario: markUSDSent(orderId, "ipfs://comprobante")
 * 4. Intermediario: markCOPSent(orderId, "ipfs://comprobante")
 * 5. Usuario: confirmCOPReceived(orderId) → Libera USDT al Intermediario
 * 
 * Si timeout sin confirmación: dispute automático
 */
contract P2PFiatExchange is AccessControl, ReentrancyGuard, Pausable, IP2PFiatExchange {
    using SafeERC20 for IERC20;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    // ============================================
    // VARIABLES DE ESTADO
    // ============================================
    
    /// @notice Contador de órdenes fiat-to-fiat
    uint256 public fiatOrderCount;
    
    /// @notice Mapeo de ID a orden fiat
    mapping(uint256 => FiatToFiatOrder) public fiatOrders;
    
    /// @notice Órdenes fiat por usuario
    mapping(address => uint256[]) public userFiatOrders;
    
    /// @notice Órdenes fiat por intermediario
    mapping(address => uint256[]) public intermediaryFiatOrders;
    
    /// @notice Órdenes activas (disponibles para aceptar)
    uint256[] private activeOrderIds;
    
    /// @notice Tiempo máximo para completar orden (24 horas)
    uint256 public fiatOrderTimeout = 24 hours;
    
    /// @notice Monto mínimo para órdenes fiat (equivalente USD)
    uint256 public minimumFiatOrderUSD = 100e18; // $100
    
    /// @notice Token usado para escrow (USDT por defecto)
    IERC20 public fiatEscrowToken;
    
    /// @notice Contrato gestor de comisiones
    IFiatFeeManager public fiatFeeManager;
    
    /// @notice Contrato resolutor de disputas
    IFiatDisputeResolver public fiatDisputeResolver;
    
    /// @notice Ratings de usuarios (simple tracking)
    mapping(address => UserRating) public userRatings;
    
    struct UserRating {
        uint256 totalFiatOrders;
        uint256 completedFiatOrders;
        uint256 disputedFiatOrders;
    }
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor(
        address _admin,
        address _fiatEscrowToken,
        address _fiatFeeManager,
        address _fiatDisputeResolver
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_fiatEscrowToken != address(0), "Invalid escrow token");
        require(_fiatFeeManager != address(0), "Invalid fee manager");
        require(_fiatDisputeResolver != address(0), "Invalid dispute resolver");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        
        fiatEscrowToken = IERC20(_fiatEscrowToken);
        fiatFeeManager = IFiatFeeManager(_fiatFeeManager);
        fiatDisputeResolver = IFiatDisputeResolver(_fiatDisputeResolver);
    }
    
    // ============================================
    // FUNCIONES PRINCIPALES
    // ============================================
    
    /**
     * @notice Usuario crea orden fiat-to-fiat (USD → COP)
     * @param fiatFrom Moneda fiat de entrada ("USD", "EUR", etc.)
     * @param fiatTo Moneda fiat de salida ("COP", "MXN", etc.)
     * @param amountFrom Cantidad en fiat de entrada (ej: 1000 USD)
     * @param expectedRate Tasa de cambio esperada (ej: 1 USD = 5000 COP)
     * @return orderId ID de la orden creada
     */
    function createFiatToFiatOrder(
        string memory fiatFrom,
        string memory fiatTo,
        uint256 amountFrom,
        uint256 expectedRate
    ) external nonReentrant whenNotPaused returns (uint256 orderId) {
        require(amountFrom >= minimumFiatOrderUSD, "Amount too low");
        require(expectedRate > 0, "Invalid rate");
        
        // Verificar que ambas monedas estén soportadas
        uint256 maxFeeFrom = fiatFeeManager.getMaxFiatFee(fiatFrom);
        uint256 maxFeeTo = fiatFeeManager.getMaxFiatFee(fiatTo);
        require(maxFeeFrom > 0, "Fiat from not supported");
        require(maxFeeTo > 0, "Fiat to not supported");
        
        // SECURITY: Fix race condition - atomic increment and verify uniqueness
        orderId = ++fiatOrderCount;
        
        // SECURITY: Verify order doesn't already exist
        require(fiatOrders[orderId].user == address(0), "Order already exists");
        
        uint256 amountTo = (amountFrom * expectedRate) / 1e18;
        
        FiatToFiatOrder storage order = fiatOrders[orderId];
        order.orderId = orderId;
        order.user = msg.sender;
        order.intermediary = address(0);
        order.fiatFrom = fiatFrom;
        order.fiatTo = fiatTo;
        order.amountFrom = amountFrom;
        order.amountTo = amountTo;
        order.usdtAmount = 0;
        order.status = FiatOrderStatus.Created;
        order.createdAt = block.timestamp;
        
        userFiatOrders[msg.sender].push(orderId);
        activeOrderIds.push(orderId);
        
        emit FiatOrderCreated(orderId, msg.sender, fiatFrom, fiatTo, amountFrom);
        
        return orderId;
    }
    
    /**
     * @notice Intermediario acepta orden (bloquea USDT)
     * @param orderId ID de la orden a aceptar
     */
    function acceptFiatOrder(uint256 orderId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        FiatToFiatOrder storage order = fiatOrders[orderId];
        
        require(order.status == FiatOrderStatus.Created, "Order not available");
        require(order.user != msg.sender, "Cannot accept own order");
        require(fiatFeeManager.isApprovedIntermediary(msg.sender), "Not approved intermediary");
        
        // Calcular comisiones
        (
            uint256 entryFeePercent,
            uint256 exitFeePercent,
            uint256 entryFeeAmount,
            uint256 exitFeeAmount,
            uint256 totalFeeUSDT
        ) = fiatFeeManager.calculateFees(
            msg.sender,
            order.fiatFrom,
            order.fiatTo,
            order.amountFrom
        );
        
        // Bloquear USDT del intermediario
        fiatEscrowToken.safeTransferFrom(
            msg.sender,
            address(this),
            order.amountFrom
        );
        
        // Actualizar orden
        order.intermediary = msg.sender;
        order.usdtAmount = order.amountFrom;
        order.fees.entryFeePercent = entryFeePercent;
        order.fees.exitFeePercent = exitFeePercent;
        order.fees.entryFeeAmount = entryFeeAmount;
        order.fees.exitFeeAmount = exitFeeAmount;
        order.fees.totalFeeUSDT = totalFeeUSDT;
        order.status = FiatOrderStatus.IntermediaryAccepted;
        order.acceptedAt = block.timestamp;
        order.deadline = block.timestamp + fiatOrderTimeout;
        
        intermediaryFiatOrders[msg.sender].push(orderId);
        
        // Remover de órdenes activas
        _removeActiveOrder(orderId);
        
        emit FiatOrderAccepted(orderId, msg.sender, order.amountFrom);
    }
    
    /**
     * @notice Usuario marca USD enviado (sube comprobante)
     * @param orderId ID de la orden
     * @param bankProofIPFS Hash IPFS del comprobante bancario
     */
    function markUSDSent(uint256 orderId, string memory bankProofIPFS)
        external
        nonReentrant
    {
        FiatToFiatOrder storage order = fiatOrders[orderId];
        
        require(order.user == msg.sender, "Not order owner");
        require(order.status == FiatOrderStatus.IntermediaryAccepted, "Invalid status");
        require(block.timestamp < order.deadline, "Order timed out");
        require(bytes(bankProofIPFS).length > 0, "Bank proof required");
        
        order.status = FiatOrderStatus.USDSent;
        order.usdSentAt = block.timestamp;
        order.userBankProof = bankProofIPFS;
        
        emit USDSent(orderId, msg.sender, bankProofIPFS);
    }
    
    /**
     * @notice Intermediario marca COP enviado (sube comprobante)
     * @param orderId ID de la orden
     * @param bankProofIPFS Hash IPFS del comprobante bancario
     */
    function markCOPSent(uint256 orderId, string memory bankProofIPFS)
        external
        nonReentrant
    {
        FiatToFiatOrder storage order = fiatOrders[orderId];
        
        require(order.intermediary == msg.sender, "Not intermediary");
        require(order.status == FiatOrderStatus.USDSent, "USD not sent yet");
        require(block.timestamp < order.deadline, "Order timed out");
        require(bytes(bankProofIPFS).length > 0, "Bank proof required");
        
        order.status = FiatOrderStatus.COPSent;
        order.copSentAt = block.timestamp;
        order.intermediaryBankProof = bankProofIPFS;
        
        emit COPSent(orderId, msg.sender, bankProofIPFS);
    }
    
    /**
     * @notice Usuario confirma COP recibido (libera USDT)
     * @param orderId ID de la orden
     */
    function confirmCOPReceived(uint256 orderId)
        external
        nonReentrant
    {
        FiatToFiatOrder storage order = fiatOrders[orderId];
        
        require(order.user == msg.sender, "Not order owner");
        require(order.status == FiatOrderStatus.COPSent, "COP not sent yet");
        require(block.timestamp < order.deadline, "Order timed out");
        
        // ✅ LIBERAR USDT AL INTERMEDIARIO
        fiatEscrowToken.safeTransfer(
            order.intermediary,
            order.usdtAmount
        );
        
        order.status = FiatOrderStatus.Completed;
        order.completedAt = block.timestamp;
        
        // Actualizar ratings
        userRatings[order.user].totalFiatOrders++;
        userRatings[order.user].completedFiatOrders++;
        userRatings[order.intermediary].totalFiatOrders++;
        userRatings[order.intermediary].completedFiatOrders++;
        
        emit FiatOrderCompleted(orderId, order.intermediary, order.fees.totalFeeUSDT);
    }
    
    /**
     * @notice Cancelar orden antes de ser aceptada
     * @param orderId ID de la orden
     */
    function cancelFiatOrder(uint256 orderId) external nonReentrant {
        FiatToFiatOrder storage order = fiatOrders[orderId];
        
        require(order.user == msg.sender, "Not order owner");
        require(order.status == FiatOrderStatus.Created, "Cannot cancel");
        
        order.status = FiatOrderStatus.Cancelled;
        
        // Remover de órdenes activas
        _removeActiveOrder(orderId);
        
        emit FiatOrderCancelled(orderId, msg.sender);
    }
    
    /**
     * @notice Marcar orden como en disputa por timeout
     * @param orderId ID de la orden
     */
    function timeoutFiatOrder(uint256 orderId) external {
        FiatToFiatOrder storage order = fiatOrders[orderId];
        
        require(block.timestamp >= order.deadline, "Not timed out yet");
        require(
            order.status == FiatOrderStatus.IntermediaryAccepted ||
            order.status == FiatOrderStatus.USDSent ||
            order.status == FiatOrderStatus.COPSent,
            "Cannot timeout"
        );
        
        order.status = FiatOrderStatus.Disputed;
        
        // Crear disputa en el resolver
        fiatDisputeResolver.raiseDispute(orderId, "Timeout: 24h exceeded");
        
        userRatings[order.user].disputedFiatOrders++;
        userRatings[order.intermediary].disputedFiatOrders++;
        
        emit FiatOrderDisputed(orderId, "Timeout");
    }
    
    // ============================================
    // FUNCIONES DE RESOLUCIÓN DE DISPUTAS
    // ============================================
    
    /**
     * @notice Resolver disputa y liberar fondos (solo Dispute Resolver)
     * @param orderId ID de la orden
     * @param releaseTo 0 = usuario, 1 = intermediario, 2 = 50/50
     */
    function resolveDisputeAndReleaseFunds(uint256 orderId, uint8 releaseTo)
        external
        nonReentrant
    {
        require(msg.sender == address(fiatDisputeResolver), "Only dispute resolver");
        
        FiatToFiatOrder storage order = fiatOrders[orderId];
        require(order.status == FiatOrderStatus.Disputed, "Not disputed");
        
        if (releaseTo == 0) {
            // Usuario gana: devolver USDT al usuario
            fiatEscrowToken.safeTransfer(order.user, order.usdtAmount);
        } else if (releaseTo == 1) {
            // Intermediario gana: liberar USDT al intermediario
            fiatEscrowToken.safeTransfer(order.intermediary, order.usdtAmount);
        } else if (releaseTo == 2) {
            // 50/50: dividir fondos
            uint256 halfAmount = order.usdtAmount / 2;
            fiatEscrowToken.safeTransfer(order.user, halfAmount);
            fiatEscrowToken.safeTransfer(order.intermediary, order.usdtAmount - halfAmount);
        }
        
        order.status = FiatOrderStatus.Completed;
        order.completedAt = block.timestamp;
    }
    
    // ============================================
    // VISTAS
    // ============================================
    
    /**
     * @notice Obtener información de orden
     */
    function getFiatOrder(uint256 orderId) 
        external 
        view 
        returns (FiatToFiatOrder memory) 
    {
        return fiatOrders[orderId];
    }
    
    /**
     * @notice Obtener órdenes de un usuario
     */
    function getUserFiatOrders(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userFiatOrders[user];
    }
    
    /**
     * @notice Obtener órdenes de un intermediario
     */
    function getIntermediaryFiatOrders(address intermediary) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return intermediaryFiatOrders[intermediary];
    }
    
    /**
     * @notice Obtener órdenes activas (disponibles para aceptar)
     */
    function getActiveFiatOrders() 
        external 
        view 
        returns (uint256[] memory) 
    {
        return activeOrderIds;
    }
    
    /**
     * @notice Obtener rating de usuario
     */
    function getUserRating(address user) 
        external 
        view 
        returns (UserRating memory) 
    {
        return userRatings[user];
    }
    
    // ============================================
    // FUNCIONES INTERNAS
    // ============================================
    
    /**
     * @notice Remover orden de la lista de activas
     */
    function _removeActiveOrder(uint256 orderId) internal {
        for (uint256 i = 0; i < activeOrderIds.length; i++) {
            if (activeOrderIds[i] == orderId) {
                activeOrderIds[i] = activeOrderIds[activeOrderIds.length - 1];
                activeOrderIds.pop();
                break;
            }
        }
    }
    
    // ============================================
    // FUNCIONES ADMIN
    // ============================================
    
    function setFiatOrderTimeout(uint256 _timeout) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_timeout >= 1 hours && _timeout <= 72 hours, "Invalid timeout");
        fiatOrderTimeout = _timeout;
    }
    
    function setMinimumFiatOrderUSD(uint256 _minimum) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_minimum > 0, "Invalid minimum");
        minimumFiatOrderUSD = _minimum;
    }
    
    function setFiatEscrowToken(address _token) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_token != address(0), "Invalid token");
        fiatEscrowToken = IERC20(_token);
    }
    
    function setFiatFeeManager(address _manager) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_manager != address(0), "Invalid manager");
        fiatFeeManager = IFiatFeeManager(_manager);
    }
    
    function setFiatDisputeResolver(address _resolver) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_resolver != address(0), "Invalid resolver");
        fiatDisputeResolver = IFiatDisputeResolver(_resolver);
    }
    
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Emergency withdraw (solo para casos críticos)
     */
    function emergencyWithdraw(address token, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
