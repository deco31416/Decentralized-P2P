// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IAssetManager.sol";

/**
 * @title BalanceManager
 * @author deoc31416
 * @notice Gestión centralizada de balances multi-token para el ecosistema
 * @dev Maneja depósitos, retiros, bloqueos y liberaciones de fondos
 * 
 * Características:
 * - Soporte para múltiples tokens ERC20
 * - Sistema de escrow para trades
 * - Límites de retiro diarios
 * - Protección contra rug pulls
 * - Tracking completo de transacciones
 */
contract BalanceManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========== ROLES ==========
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ========== STRUCTS ==========
    
    /// @notice Información de balance de usuario por token
    struct Balance {
        uint256 available;      // Balance disponible
        uint256 locked;         // Balance bloqueado en trades/escrow
        uint256 totalDeposited; // Total histórico depositado
        uint256 totalWithdrawn; // Total histórico retirado
    }

    /// @notice Registro de transacción
    struct Transaction {
        address user;
        address token;
        uint256 amount;
        TransactionType txType;
        uint256 timestamp;
        bytes32 referenceId;
    }

    /// @notice Tipos de transacción
    enum TransactionType {
        Deposit,
        Withdraw,
        Lock,
        Unlock,
        Transfer
    }

    // ========== STATE VARIABLES ==========
    
    /// @notice Balance por usuario por token: user => token => Balance
    mapping(address => mapping(address => Balance)) public balances;

    /// @notice Tokens soportados
    mapping(address => bool) public supportedTokens;
    
    /// @notice Lista de tokens soportados
    address[] public tokenList;

    /// @notice Límite de retiro diario por usuario por token
    mapping(address => mapping(address => uint256)) public dailyWithdrawLimit;

    /// @notice Retiros realizados hoy: user => token => day => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public dailyWithdrawn;

    /// @notice Historial de transacciones
    Transaction[] public transactions;

    /// @notice Mapping de transacciones por usuario
    mapping(address => uint256[]) public userTransactions;

    /// @notice Total depositado por token
    mapping(address => uint256) public totalDeposits;

    /// @notice Total retirado por token
    mapping(address => uint256) public totalWithdrawals;

    /// @notice Límite de retiro diario por defecto (0 = sin límite)
    uint256 public defaultDailyLimit = 0;

    /// @notice Fee de retiro (en basis points, 100 = 1%)
    uint256 public withdrawFee = 0; // Sin fee por defecto

    /// @notice Dirección del treasury para fees
    address public treasury;

    /// @notice Referencia al AssetManager
    address public assetManager;

    // ========== EVENTS ==========
    
    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 newBalance
    );
    
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 fee,
        uint256 newBalance
    );
    
    event FundsLocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        bytes32 indexed referenceId
    );
    
    event FundsUnlocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        bytes32 indexed referenceId
    );
    
    event InternalTransfer(
        address indexed from,
        address indexed to,
        address indexed token,
        uint256 amount
    );
    
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event DailyLimitUpdated(address indexed user, address indexed token, uint256 newLimit);
    event WithdrawFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    // ========== MODIFIERS ==========
    
    modifier onlySupported(address token) {
        require(supportedTokens[token], "Token not supported");
        _;
    }

    modifier validAddress(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    // ========== CONSTRUCTOR ==========
    
    constructor(address admin, address _treasury) validAddress(admin) validAddress(_treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        treasury = _treasury;
    }

    // ========== DEPOSIT FUNCTIONS ==========
    
    /**
     * @notice Deposita tokens al balance del usuario
     * @param token Dirección del token a depositar
     * @param amount Cantidad a depositar
     */
    function deposit(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlySupported(token) 
    {
        require(amount > 0, "Amount must be > 0");

        // Transfer tokens al contrato
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Actualizar balance
        balances[msg.sender][token].available += amount;
        balances[msg.sender][token].totalDeposited += amount;
        totalDeposits[token] += amount;

        // Registrar transacción
        _recordTransaction(msg.sender, token, amount, TransactionType.Deposit, bytes32(0));

        emit Deposited(msg.sender, token, amount, balances[msg.sender][token].available);
    }

    /**
     * @notice Deposita en nombre de otro usuario (para contratos)
     * @param user Usuario destino
     * @param token Token a depositar
     * @param amount Cantidad
     */
    function depositFor(address user, address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlySupported(token)
        onlyRole(OPERATOR_ROLE)
    {
        require(amount > 0, "Amount must be > 0");
        require(user != address(0), "Invalid user");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        balances[user][token].available += amount;
        balances[user][token].totalDeposited += amount;
        totalDeposits[token] += amount;

        _recordTransaction(user, token, amount, TransactionType.Deposit, bytes32(0));

        emit Deposited(user, token, amount, balances[user][token].available);
    }

    // ========== WITHDRAW FUNCTIONS ==========
    
    /**
     * @notice Retira tokens del balance del usuario
     * @param token Token a retirar
     * @param amount Cantidad a retirar
     */
    function withdraw(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlySupported(token) 
    {
        require(amount > 0, "Amount must be > 0");
        require(balances[msg.sender][token].available >= amount, "Insufficient balance");

        // Verificar límite diario
        _checkDailyLimit(msg.sender, token, amount);

        // Calcular fee
        uint256 fee = (amount * withdrawFee) / 10000;
        uint256 amountAfterFee = amount - fee;

        // Actualizar balance
        balances[msg.sender][token].available -= amount;
        balances[msg.sender][token].totalWithdrawn += amount;
        totalWithdrawals[token] += amount;

        // Registrar retiro del día
        uint256 today = block.timestamp / 1 days;
        dailyWithdrawn[msg.sender][token][today] += amount;

        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amountAfterFee);
        
        // Transfer fee al treasury
        if (fee > 0) {
            IERC20(token).safeTransfer(treasury, fee);
        }

        // Registrar transacción
        _recordTransaction(msg.sender, token, amount, TransactionType.Withdraw, bytes32(0));

        emit Withdrawn(msg.sender, token, amount, fee, balances[msg.sender][token].available);
    }

    /**
     * @notice Verifica y actualiza límite de retiro diario
     */
    function _checkDailyLimit(address user, address token, uint256 amount) internal view {
        uint256 limit = dailyWithdrawLimit[user][token];
        
        // Si no hay límite personalizado, usar default (0 = sin límite)
        if (limit == 0) {
            limit = defaultDailyLimit;
        }

        // Si limit es 0, no hay restricción
        if (limit == 0) return;

        uint256 today = block.timestamp / 1 days;
        uint256 withdrawn = dailyWithdrawn[user][token][today];

        require(withdrawn + amount <= limit, "Daily limit exceeded");
    }

    // ========== LOCK/UNLOCK FUNCTIONS (Para Escrow) ==========
    
    /**
     * @notice Bloquea fondos en escrow (para trades)
     * @param user Usuario dueño de los fondos
     * @param token Token a bloquear
     * @param amount Cantidad a bloquear
     * @param referenceId ID de referencia (orden, trade, etc)
     */
    function lockFunds(
        address user, 
        address token, 
        uint256 amount, 
        bytes32 referenceId
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
        onlySupported(token) 
    {
        require(amount > 0, "Amount must be > 0");
        require(balances[user][token].available >= amount, "Insufficient balance");

        balances[user][token].available -= amount;
        balances[user][token].locked += amount;

        _recordTransaction(user, token, amount, TransactionType.Lock, referenceId);

        emit FundsLocked(user, token, amount, referenceId);
    }

    /**
     * @notice Libera fondos bloqueados
     * @param user Usuario dueño de los fondos
     * @param token Token a liberar
     * @param amount Cantidad a liberar
     * @param referenceId ID de referencia
     */
    function unlockFunds(
        address user, 
        address token, 
        uint256 amount, 
        bytes32 referenceId
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
        onlySupported(token) 
    {
        require(amount > 0, "Amount must be > 0");
        require(balances[user][token].locked >= amount, "Insufficient locked balance");

        balances[user][token].locked -= amount;
        balances[user][token].available += amount;

        _recordTransaction(user, token, amount, TransactionType.Unlock, referenceId);

        emit FundsUnlocked(user, token, amount, referenceId);
    }

    /**
     * @notice Transfiere fondos bloqueados entre usuarios (para completar trades)
     * @param from Usuario origen
     * @param to Usuario destino
     * @param token Token a transferir
     * @param amount Cantidad
     * @param referenceId ID de referencia
     */
    function transferLocked(
        address from,
        address to,
        address token,
        uint256 amount,
        bytes32 referenceId
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
        onlySupported(token) 
    {
        require(amount > 0, "Amount must be > 0");
        require(to != address(0), "Invalid recipient");
        require(balances[from][token].locked >= amount, "Insufficient locked balance");

        // Remover de locked del origen
        balances[from][token].locked -= amount;

        // Agregar a available del destino
        balances[to][token].available += amount;

        _recordTransaction(from, token, amount, TransactionType.Transfer, referenceId);

        emit InternalTransfer(from, to, token, amount);
    }

    // ========== INTERNAL FUNCTIONS ==========
    
    /**
     * @notice Registra una transacción
     */
    function _recordTransaction(
        address user,
        address token,
        uint256 amount,
        TransactionType txType,
        bytes32 referenceId
    ) internal {
        uint256 txId = transactions.length;
        
        transactions.push(Transaction({
            user: user,
            token: token,
            amount: amount,
            txType: txType,
            timestamp: block.timestamp,
            referenceId: referenceId
        }));

        userTransactions[user].push(txId);
    }

    // ========== VIEW FUNCTIONS ==========
    
    /**
     * @notice Obtiene el balance disponible de un usuario
     * @param user Usuario
     * @param token Token
     * @return Balance disponible
     */
    function getAvailableBalance(address user, address token) 
        external 
        view 
        returns (uint256) 
    {
        return balances[user][token].available;
    }

    /**
     * @notice Obtiene el balance bloqueado de un usuario
     * @param user Usuario
     * @param token Token
     * @return Balance bloqueado
     */
    function getLockedBalance(address user, address token) 
        external 
        view 
        returns (uint256) 
    {
        return balances[user][token].locked;
    }

    /**
     * @notice Obtiene el balance total (disponible + bloqueado)
     * @param user Usuario
     * @param token Token
     * @return Balance total
     */
    function getTotalBalance(address user, address token) 
        external 
        view 
        returns (uint256) 
    {
        return balances[user][token].available + balances[user][token].locked;
    }

    /**
     * @notice Obtiene información completa de balance
     * @param user Usuario
     * @param token Token
     * @return Balance completo
     */
    function getBalance(address user, address token) 
        external 
        view 
        returns (Balance memory) 
    {
        return balances[user][token];
    }

    /**
     * @notice Obtiene transacciones de un usuario
     * @param user Usuario
     * @return Array de IDs de transacciones
     */
    function getUserTransactions(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userTransactions[user];
    }

    /**
     * @notice Obtiene detalles de una transacción
     * @param txId ID de la transacción
     * @return Transacción completa
     */
    function getTransaction(uint256 txId) 
        external 
        view 
        returns (Transaction memory) 
    {
        require(txId < transactions.length, "Invalid transaction ID");
        return transactions[txId];
    }

    /**
     * @notice Obtiene lista de tokens soportados
     * @return Array de direcciones de tokens
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    // ========== ADMIN FUNCTIONS ==========
    
    /**
     * @notice Agrega un nuevo token soportado
     * @param token Dirección del token
     */
    function addSupportedToken(address token) 
        external 
        onlyRole(ADMIN_ROLE) 
        validAddress(token) 
    {
        require(!supportedTokens[token], "Token already supported");
        
        supportedTokens[token] = true;
        tokenList.push(token);
        
        emit TokenAdded(token);
    }

    /**
     * @notice Remueve un token soportado
     * @param token Dirección del token
     */
    function removeSupportedToken(address token) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(supportedTokens[token], "Token not supported");
        require(totalDeposits[token] == totalWithdrawals[token], "Token has deposits");
        
        supportedTokens[token] = false;
        
        // Remover de array
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }
        
        emit TokenRemoved(token);
    }

    /**
     * @notice Actualiza límite de retiro diario para un usuario
     * @param user Usuario
     * @param token Token
     * @param limit Nuevo límite (0 = sin límite)
     */
    function setDailyLimit(address user, address token, uint256 limit) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        dailyWithdrawLimit[user][token] = limit;
        emit DailyLimitUpdated(user, token, limit);
    }

    /**
     * @notice Actualiza límite de retiro diario por defecto
     * @param limit Nuevo límite (0 = sin límite)
     */
    function setDefaultDailyLimit(uint256 limit) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        defaultDailyLimit = limit;
    }

    /**
     * @notice Actualiza fee de retiro
     * @param newFee Nuevo fee en basis points (100 = 1%)
     */
    function setWithdrawFee(uint256 newFee) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(newFee <= 1000, "Fee too high (max 10%)");
        uint256 oldFee = withdrawFee;
        withdrawFee = newFee;
        emit WithdrawFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Actualiza dirección del treasury
     * @param newTreasury Nueva dirección
     */
    function setTreasury(address newTreasury) 
        external 
        onlyRole(ADMIN_ROLE) 
        validAddress(newTreasury) 
    {
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Pausa el contrato
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Despausa el contrato
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Retiro de emergencia (solo admin)
     * @param token Token a retirar
     * @param amount Cantidad
     * @param to Dirección destino
     */
    function emergencyWithdraw(address token, uint256 amount, address to) 
        external 
        onlyRole(ADMIN_ROLE) 
        validAddress(to) 
    {
        IERC20(token).safeTransfer(to, amount);
    }
}

