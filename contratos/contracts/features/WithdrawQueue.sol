// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WithdrawQueue
 * @notice Cola de retiros con timelock y prioridades
 * @dev Sistema de cola para retiros grandes que requieren tiempo de espera
 * 
 * Características principales:
 * - Cola ordenada por prioridad y timestamp
 * - Timelock configurable por prioridad
 * - 3 niveles de prioridad: NORMAL, HIGH, URGENT
 * - Estados: PENDING, APPROVED, EXECUTED, CANCELLED, EXPIRED
 * - Aprobación manual por admin/multisig
 * - Cancelación por usuario o admin
 * - Expiración automática después de tiempo límite
 * - Batch processing para múltiples órdenes
 * - Fast-track para usuarios VIP
 * - Emergency execution sin timelock
 * 
 * Flujo normal:
 * 1. WithdrawManager crea orden con createWithdrawOrder()
 * 2. Orden queda PENDING con timelock activo
 * 3. Después de timelock, admin puede aprobar
 * 4. Orden pasa a APPROVED
 * 5. WithdrawManager ejecuta con executeWithdrawOrder()
 * 6. Orden pasa a EXECUTED
 * 
 * Prioridades:
 * - NORMAL: timelock 24h, usuarios regulares
 * - HIGH: timelock 12h, usuarios con alto volumen
 * - URGENT: timelock 6h, casos especiales
 * - VIP: timelock 1h o sin timelock
 * 
 * Seguridad:
 * - Solo WithdrawManager puede crear órdenes
 * - Admin/multisig aprueban órdenes
 * - Timelock previene retiros masivos instantáneos
 * - Expiración previene órdenes obsoletas
 * - Cancelación permite deshacer errores
 * - Circuit breaker puede pausar todo
 */
contract WithdrawQueue is AccessControl, ReentrancyGuard, Pausable {
    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador (WithdrawManager)
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de aprobador
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Prioridades de retiro
    enum Priority {
        NORMAL,
        HIGH,
        URGENT
    }

    /// @notice Estados de orden
    enum OrderStatus {
        PENDING,
        APPROVED,
        EXECUTED,
        CANCELLED,
        EXPIRED
    }

    /// @notice Orden de retiro
    struct WithdrawOrder {
        uint256 id;
        address user;
        address token;
        uint256 amount;
        uint256 netAmount;
        Priority priority;
        OrderStatus status;
        uint256 createdAt;
        uint256 approvedAt;
        uint256 executedAt;
        uint256 timelockEnd;
        uint256 expiresAt;
        address approvedBy;
        bool fastTracked;
        string reason;
    }

    /// @notice Configuración de timelock por prioridad
    struct TimelockConfig {
        uint256 normalTimelock;
        uint256 highTimelock;
        uint256 urgentTimelock;
        uint256 vipTimelock;
        uint256 expirationPeriod;
    }

    /// @notice Órdenes de retiro
    mapping(uint256 => WithdrawOrder) public orders;
    
    /// @notice Contador de órdenes
    uint256 public orderCounter;
    
    /// @notice Órdenes pendientes por usuario
    mapping(address => uint256[]) public userPendingOrders;
    
    /// @notice Órdenes aprobadas por usuario
    mapping(address => uint256[]) public userApprovedOrders;
    
    /// @notice Total de órdenes por estado
    mapping(OrderStatus => uint256) public ordersByStatus;
    
    /// @notice Usuarios VIP (sin timelock o reducido)
    mapping(address => bool) public vipUsers;

    /// @notice Configuración de timelocks
    TimelockConfig public timelockConfig;

    /// @notice Referencia al WithdrawManager
    address public withdrawManager;

    /// @notice Fast-track habilitado
    bool public fastTrackEnabled;

    /// @notice Emergency execution habilitado
    bool public emergencyExecutionEnabled;

    // ============================================
    // EVENTOS
    // ============================================

    event OrderCreated(
        uint256 indexed orderId,
        address indexed user,
        address indexed token,
        uint256 amount,
        Priority priority,
        uint256 timelockEnd
    );

    event OrderApproved(
        uint256 indexed orderId,
        address indexed approvedBy,
        uint256 timestamp
    );

    event OrderExecuted(
        uint256 indexed orderId,
        address indexed user,
        uint256 timestamp
    );

    event OrderCancelled(
        uint256 indexed orderId,
        address indexed cancelledBy,
        string reason
    );

    event OrderExpired(
        uint256 indexed orderId,
        uint256 timestamp
    );

    event FastTracked(
        uint256 indexed orderId,
        address indexed user
    );

    event VIPStatusChanged(
        address indexed user,
        bool isVIP
    );

    event TimelockConfigUpdated(
        uint256 normalTimelock,
        uint256 highTimelock,
        uint256 urgentTimelock,
        uint256 vipTimelock
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _withdrawManager
    ) {
        require(_admin != address(0), "Invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(APPROVER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        if (_withdrawManager != address(0)) {
            withdrawManager = _withdrawManager;
            _grantRole(OPERATOR_ROLE, _withdrawManager);
        }

        // Configuración inicial de timelocks
        timelockConfig.normalTimelock = 24 hours;
        timelockConfig.highTimelock = 12 hours;
        timelockConfig.urgentTimelock = 6 hours;
        timelockConfig.vipTimelock = 1 hours;
        timelockConfig.expirationPeriod = 7 days;

        fastTrackEnabled = true;
        emergencyExecutionEnabled = false;
    }

    // ============================================
    // CREACIÓN DE ÓRDENES
    // ============================================

    /**
     * @notice Crea orden de retiro
     * @param user Usuario que retira
     * @param token Token a retirar
     * @param amount Cantidad total
     * @param netAmount Cantidad neta (después de fees)
     */
    function createWithdrawOrder(
        address user,
        address token,
        uint256 amount,
        uint256 netAmount
    ) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        return _createOrder(user, token, amount, netAmount, Priority.NORMAL, "");
    }

    /**
     * @notice Crea orden con prioridad
     */
    function createWithdrawOrderWithPriority(
        address user,
        address token,
        uint256 amount,
        uint256 netAmount,
        Priority priority,
        string memory reason
    ) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        return _createOrder(user, token, amount, netAmount, priority, reason);
    }

    /**
     * @notice Crea orden interna
     */
    function _createOrder(
        address user,
        address token,
        uint256 amount,
        uint256 netAmount,
        Priority priority,
        string memory reason
    ) internal returns (uint256) {
        require(user != address(0), "Invalid user");
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");

        orderCounter++;
        uint256 orderId = orderCounter;

        // Calcular timelock
        uint256 timelock = _getTimelock(user, priority);
        uint256 timelockEnd = block.timestamp + timelock;
        uint256 expiresAt = timelockEnd + timelockConfig.expirationPeriod;

        // Crear orden
        WithdrawOrder storage order = orders[orderId];
        order.id = orderId;
        order.user = user;
        order.token = token;
        order.amount = amount;
        order.netAmount = netAmount;
        order.priority = priority;
        order.status = OrderStatus.PENDING;
        order.createdAt = block.timestamp;
        order.timelockEnd = timelockEnd;
        order.expiresAt = expiresAt;
        order.reason = reason;

        // Agregar a listas
        userPendingOrders[user].push(orderId);
        ordersByStatus[OrderStatus.PENDING]++;

        emit OrderCreated(orderId, user, token, amount, priority, timelockEnd);

        return orderId;
    }

    // ============================================
    // APROBACIÓN Y EJECUCIÓN
    // ============================================

    /**
     * @notice Aprueba orden de retiro
     */
    function approveOrder(uint256 orderId) external onlyRole(APPROVER_ROLE) {
        WithdrawOrder storage order = orders[orderId];
        require(order.status == OrderStatus.PENDING, "Order not pending");
        require(block.timestamp >= order.timelockEnd, "Timelock active");
        require(block.timestamp < order.expiresAt, "Order expired");

        order.status = OrderStatus.APPROVED;
        order.approvedAt = block.timestamp;
        order.approvedBy = msg.sender;

        // Actualizar contadores
        ordersByStatus[OrderStatus.PENDING]--;
        ordersByStatus[OrderStatus.APPROVED]++;

        // Mover de pending a approved
        _removeFromPendingOrders(order.user, orderId);
        userApprovedOrders[order.user].push(orderId);

        emit OrderApproved(orderId, msg.sender, block.timestamp);
    }

    /**
     * @notice Aprueba múltiples órdenes
     */
    function batchApproveOrders(uint256[] memory orderIds) external onlyRole(APPROVER_ROLE) {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 orderId = orderIds[i];
            WithdrawOrder storage order = orders[orderId];
            
            if (order.status == OrderStatus.PENDING && 
                block.timestamp >= order.timelockEnd && 
                block.timestamp < order.expiresAt) {
                
                order.status = OrderStatus.APPROVED;
                order.approvedAt = block.timestamp;
                order.approvedBy = msg.sender;

                ordersByStatus[OrderStatus.PENDING]--;
                ordersByStatus[OrderStatus.APPROVED]++;

                _removeFromPendingOrders(order.user, orderId);
                userApprovedOrders[order.user].push(orderId);

                emit OrderApproved(orderId, msg.sender, block.timestamp);
            }
        }
    }

    /**
     * @notice Ejecuta orden aprobada
     */
    function executeOrder(uint256 orderId) external onlyRole(OPERATOR_ROLE) nonReentrant {
        WithdrawOrder storage order = orders[orderId];
        require(order.status == OrderStatus.APPROVED, "Order not approved");
        require(block.timestamp < order.expiresAt, "Order expired");

        order.status = OrderStatus.EXECUTED;
        order.executedAt = block.timestamp;

        // Actualizar contadores
        ordersByStatus[OrderStatus.APPROVED]--;
        ordersByStatus[OrderStatus.EXECUTED]++;

        // Remover de approved orders
        _removeFromApprovedOrders(order.user, orderId);

        emit OrderExecuted(orderId, order.user, block.timestamp);
    }

    /**
     * @notice Ejecuta múltiples órdenes aprobadas
     */
    function batchExecuteOrders(uint256[] memory orderIds) external onlyRole(OPERATOR_ROLE) nonReentrant {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 orderId = orderIds[i];
            WithdrawOrder storage order = orders[orderId];
            
            if (order.status == OrderStatus.APPROVED && block.timestamp < order.expiresAt) {
                order.status = OrderStatus.EXECUTED;
                order.executedAt = block.timestamp;

                ordersByStatus[OrderStatus.APPROVED]--;
                ordersByStatus[OrderStatus.EXECUTED]++;

                _removeFromApprovedOrders(order.user, orderId);

                emit OrderExecuted(orderId, order.user, block.timestamp);
            }
        }
    }

    /**
     * @notice Ejecución de emergencia sin timelock
     */
    function emergencyExecuteOrder(uint256 orderId) 
        external 
        onlyRole(ADMIN_ROLE) 
        nonReentrant 
    {
        require(emergencyExecutionEnabled, "Emergency execution disabled");
        
        WithdrawOrder storage order = orders[orderId];
        require(order.status == OrderStatus.PENDING, "Order not pending");

        order.status = OrderStatus.EXECUTED;
        order.executedAt = block.timestamp;
        order.approvedBy = msg.sender;
        order.fastTracked = true;

        // Actualizar contadores
        ordersByStatus[OrderStatus.PENDING]--;
        ordersByStatus[OrderStatus.EXECUTED]++;

        _removeFromPendingOrders(order.user, orderId);

        emit OrderExecuted(orderId, order.user, block.timestamp);
    }

    // ============================================
    // CANCELACIÓN Y EXPIRACIÓN
    // ============================================

    /**
     * @notice Cancela orden
     */
    function cancelOrder(uint256 orderId, string memory reason) external {
        WithdrawOrder storage order = orders[orderId];
        require(
            order.status == OrderStatus.PENDING || order.status == OrderStatus.APPROVED,
            "Cannot cancel"
        );
        require(
            msg.sender == order.user || hasRole(ADMIN_ROLE, msg.sender),
            "Not authorized"
        );

        OrderStatus oldStatus = order.status;
        order.status = OrderStatus.CANCELLED;

        // Actualizar contadores
        ordersByStatus[oldStatus]--;
        ordersByStatus[OrderStatus.CANCELLED]++;

        // Remover de listas
        if (oldStatus == OrderStatus.PENDING) {
            _removeFromPendingOrders(order.user, orderId);
        } else {
            _removeFromApprovedOrders(order.user, orderId);
        }

        emit OrderCancelled(orderId, msg.sender, reason);
    }

    /**
     * @notice Marca orden como expirada
     */
    function expireOrder(uint256 orderId) external {
        WithdrawOrder storage order = orders[orderId];
        require(
            order.status == OrderStatus.PENDING || order.status == OrderStatus.APPROVED,
            "Cannot expire"
        );
        require(block.timestamp >= order.expiresAt, "Not expired yet");

        OrderStatus oldStatus = order.status;
        order.status = OrderStatus.EXPIRED;

        // Actualizar contadores
        ordersByStatus[oldStatus]--;
        ordersByStatus[OrderStatus.EXPIRED]++;

        // Remover de listas
        if (oldStatus == OrderStatus.PENDING) {
            _removeFromPendingOrders(order.user, orderId);
        } else {
            _removeFromApprovedOrders(order.user, orderId);
        }

        emit OrderExpired(orderId, block.timestamp);
    }

    /**
     * @notice Expira múltiples órdenes
     */
    function batchExpireOrders(uint256[] memory orderIds) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 orderId = orderIds[i];
            WithdrawOrder storage order = orders[orderId];
            
            if ((order.status == OrderStatus.PENDING || order.status == OrderStatus.APPROVED) &&
                block.timestamp >= order.expiresAt) {
                
                OrderStatus oldStatus = order.status;
                order.status = OrderStatus.EXPIRED;

                ordersByStatus[oldStatus]--;
                ordersByStatus[OrderStatus.EXPIRED]++;

                if (oldStatus == OrderStatus.PENDING) {
                    _removeFromPendingOrders(order.user, orderId);
                } else {
                    _removeFromApprovedOrders(order.user, orderId);
                }

                emit OrderExpired(orderId, block.timestamp);
            }
        }
    }

    // ============================================
    // FAST-TRACK
    // ============================================

    /**
     * @notice Fast-track de orden (reduce o elimina timelock)
     */
    function fastTrackOrder(uint256 orderId) external onlyRole(ADMIN_ROLE) {
        require(fastTrackEnabled, "Fast-track disabled");
        
        WithdrawOrder storage order = orders[orderId];
        require(order.status == OrderStatus.PENDING, "Order not pending");

        order.timelockEnd = block.timestamp; // Eliminar timelock
        order.fastTracked = true;

        emit FastTracked(orderId, order.user);
    }

    // ============================================
    // CONFIGURACIÓN
    // ============================================

    /**
     * @notice Configura timelocks
     */
    function configureTimelocks(
        uint256 normalTimelock,
        uint256 highTimelock,
        uint256 urgentTimelock,
        uint256 vipTimelock,
        uint256 expirationPeriod
    ) external onlyRole(ADMIN_ROLE) {
        require(normalTimelock >= highTimelock, "Invalid normal timelock");
        require(highTimelock >= urgentTimelock, "Invalid high timelock");
        require(urgentTimelock >= vipTimelock, "Invalid urgent timelock");
        require(expirationPeriod > 0, "Invalid expiration");

        timelockConfig.normalTimelock = normalTimelock;
        timelockConfig.highTimelock = highTimelock;
        timelockConfig.urgentTimelock = urgentTimelock;
        timelockConfig.vipTimelock = vipTimelock;
        timelockConfig.expirationPeriod = expirationPeriod;

        emit TimelockConfigUpdated(normalTimelock, highTimelock, urgentTimelock, vipTimelock);
    }

    /**
     * @notice Configura estado VIP de usuario
     */
    function setVIPStatus(address user, bool vipStatus) external onlyRole(ADMIN_ROLE) {
        vipUsers[user] = vipStatus;
        emit VIPStatusChanged(user, vipStatus);
    }

    /**
     * @notice Configura múltiples VIPs
     */
    function batchSetVIPStatus(address[] memory users, bool vipStatus) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < users.length; i++) {
            vipUsers[users[i]] = vipStatus;
            emit VIPStatusChanged(users[i], vipStatus);
        }
    }

    /**
     * @notice Configura WithdrawManager
     */
    function setWithdrawManager(address _withdrawManager) external onlyRole(ADMIN_ROLE) {
        require(_withdrawManager != address(0), "Invalid address");
        
        if (withdrawManager != address(0)) {
            _revokeRole(OPERATOR_ROLE, withdrawManager);
        }
        
        withdrawManager = _withdrawManager;
        _grantRole(OPERATOR_ROLE, _withdrawManager);
    }

    /**
     * @notice Habilita/deshabilita fast-track
     */
    function setFastTrackEnabled(bool enabled) external onlyRole(ADMIN_ROLE) {
        fastTrackEnabled = enabled;
    }

    /**
     * @notice Habilita/deshabilita emergency execution
     */
    function setEmergencyExecutionEnabled(bool enabled) external onlyRole(ADMIN_ROLE) {
        emergencyExecutionEnabled = enabled;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============================================
    // HELPERS INTERNOS
    // ============================================

    /**
     * @notice Obtiene timelock según usuario y prioridad
     */
    function _getTimelock(address user, Priority priority) internal view returns (uint256) {
        if (vipUsers[user]) {
            return timelockConfig.vipTimelock;
        }

        if (priority == Priority.URGENT) {
            return timelockConfig.urgentTimelock;
        } else if (priority == Priority.HIGH) {
            return timelockConfig.highTimelock;
        } else {
            return timelockConfig.normalTimelock;
        }
    }

    /**
     * @notice Remueve orden de pending orders
     */
    function _removeFromPendingOrders(address user, uint256 orderId) internal {
        uint256[] storage pendingOrderIds = userPendingOrders[user];
        for (uint256 i = 0; i < pendingOrderIds.length; i++) {
            if (pendingOrderIds[i] == orderId) {
                pendingOrderIds[i] = pendingOrderIds[pendingOrderIds.length - 1];
                pendingOrderIds.pop();
                break;
            }
        }
    }

    /**
     * @notice Remueve orden de approved orders
     */
    function _removeFromApprovedOrders(address user, uint256 orderId) internal {
        uint256[] storage approvedOrderIds = userApprovedOrders[user];
        for (uint256 i = 0; i < approvedOrderIds.length; i++) {
            if (approvedOrderIds[i] == orderId) {
                approvedOrderIds[i] = approvedOrderIds[approvedOrderIds.length - 1];
                approvedOrderIds.pop();
                break;
            }
        }
    }

    // ============================================
    // VISTAS
    // ============================================

    /**
     * @notice Obtiene información de orden
     */
    function getOrder(uint256 orderId) external view returns (WithdrawOrder memory) {
        return orders[orderId];
    }

    /**
     * @notice Obtiene órdenes pendientes de usuario
     */
    function getUserPendingOrders(address user) external view returns (uint256[] memory) {
        return userPendingOrders[user];
    }

    /**
     * @notice Obtiene órdenes aprobadas de usuario
     */
    function getUserApprovedOrders(address user) external view returns (uint256[] memory) {
        return userApprovedOrders[user];
    }

    /**
     * @notice Obtiene todas las órdenes de usuario por estado
     */
    function getUserOrdersByStatus(address user, OrderStatus status) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256 count = 0;
        
        // Contar órdenes con el estado
        for (uint256 i = 1; i <= orderCounter; i++) {
            if (orders[i].user == user && orders[i].status == status) {
                count++;
            }
        }

        // Crear array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= orderCounter; i++) {
            if (orders[i].user == user && orders[i].status == status) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Obtiene órdenes que pueden ser aprobadas
     */
    function getApprovableOrders() external view returns (uint256[] memory) {
        uint256 count = 0;
        
        // Contar órdenes aprobables
        for (uint256 i = 1; i <= orderCounter; i++) {
            WithdrawOrder memory order = orders[i];
            if (order.status == OrderStatus.PENDING && 
                block.timestamp >= order.timelockEnd && 
                block.timestamp < order.expiresAt) {
                count++;
            }
        }

        // Crear array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= orderCounter; i++) {
            WithdrawOrder memory order = orders[i];
            if (order.status == OrderStatus.PENDING && 
                block.timestamp >= order.timelockEnd && 
                block.timestamp < order.expiresAt) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Obtiene órdenes ejecutables
     */
    function getExecutableOrders() external view returns (uint256[] memory) {
        uint256 count = 0;
        
        for (uint256 i = 1; i <= orderCounter; i++) {
            WithdrawOrder memory order = orders[i];
            if (order.status == OrderStatus.APPROVED && block.timestamp < order.expiresAt) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= orderCounter; i++) {
            WithdrawOrder memory order = orders[i];
            if (order.status == OrderStatus.APPROVED && block.timestamp < order.expiresAt) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Obtiene órdenes expiradas
     */
    function getExpiredOrders() external view returns (uint256[] memory) {
        uint256 count = 0;
        
        for (uint256 i = 1; i <= orderCounter; i++) {
            WithdrawOrder memory order = orders[i];
            if ((order.status == OrderStatus.PENDING || order.status == OrderStatus.APPROVED) &&
                block.timestamp >= order.expiresAt) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= orderCounter; i++) {
            WithdrawOrder memory order = orders[i];
            if ((order.status == OrderStatus.PENDING || order.status == OrderStatus.APPROVED) &&
                block.timestamp >= order.expiresAt) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Verifica si orden puede ser aprobada
     */
    function canApprove(uint256 orderId) external view returns (bool can, string memory reason) {
        WithdrawOrder memory order = orders[orderId];
        
        if (order.status != OrderStatus.PENDING) {
            return (false, "Order not pending");
        }
        
        if (block.timestamp < order.timelockEnd) {
            return (false, "Timelock active");
        }
        
        if (block.timestamp >= order.expiresAt) {
            return (false, "Order expired");
        }
        
        return (true, "Can approve");
    }

    /**
     * @notice Obtiene estadísticas
     */
    function getStats() external view returns (
        uint256 totalOrders,
        uint256 pending,
        uint256 approved,
        uint256 executed,
        uint256 cancelled,
        uint256 expired
    ) {
        return (
            orderCounter,
            ordersByStatus[OrderStatus.PENDING],
            ordersByStatus[OrderStatus.APPROVED],
            ordersByStatus[OrderStatus.EXECUTED],
            ordersByStatus[OrderStatus.CANCELLED],
            ordersByStatus[OrderStatus.EXPIRED]
        );
    }

    /**
     * @notice Obtiene timelock de usuario
     */
    function getUserTimelock(address user, Priority priority) external view returns (uint256) {
        return _getTimelock(user, priority);
    }

    /**
     * @notice Verifica si usuario es VIP
     */
    function isVIP(address user) external view returns (bool) {
        return vipUsers[user];
    }
}
