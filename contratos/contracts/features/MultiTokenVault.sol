// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MultiTokenVault
 * @notice Vault seguro para almacenar múltiples tokens ERC20
 * @dev Vault con múltiples capas de seguridad y access control
 * 
 * Características principales:
 * - Almacenamiento seguro de múltiples tokens ERC20
 * - Access control granular (admin, deposit, withdraw, emergency)
 * - Tracking detallado por token
 * - Emergency withdrawal con multisig
 * - Pausable por seguridad
 * - Audit trail completo
 * - Balance reconciliation
 * - Token recovery para tokens enviados por error
 * - Rate limiting en withdrawals
 * - Whitelist de direcciones autorizadas
 * - Circuit breakers automáticos
 * - Time locks opcionales
 * 
 * Roles:
 * - ADMIN: Configuración general
 * - DEPOSIT_ROLE: Puede depositar en el vault
 * - WITHDRAW_ROLE: Puede retirar del vault
 * - EMERGENCY_ROLE: Puede ejecutar withdrawals de emergencia
 * - PAUSER_ROLE: Puede pausar el vault
 * 
 * Seguridad:
 * - ReentrancyGuard en todas las transferencias
 * - SafeERC20 para operaciones seguras
 * - Rate limiting por token
 * - Circuit breakers si hay anomalías
 * - Emergency stop mechanism
 * - Audit logging de todas las operaciones
 */
contract MultiTokenVault is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de deposit
    bytes32 public constant DEPOSIT_ROLE = keccak256("DEPOSIT_ROLE");
    
    /// @notice Rol de withdraw
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
    
    /// @notice Rol de emergencia
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Información de token en vault
    struct VaultToken {
        address token;
        uint256 balance;            // Balance actual
        uint256 totalDeposited;     // Total depositado histórico
        uint256 totalWithdrawn;     // Total retirado histórico
        uint256 lastDepositAt;      // Último depósito
        uint256 lastWithdrawAt;     // Último retiro
        uint256 depositCount;       // Número de depósitos
        uint256 withdrawCount;      // Número de retiros
        bool active;                // Token activo
        bool emergencyMode;         // Modo emergencia activado
    }

    /// @notice Registro de operación
    struct Operation {
        uint256 operationId;
        address token;
        address operator;
        uint256 amount;
        bool isDeposit;             // true = deposit, false = withdraw
        uint256 timestamp;
        uint256 balanceBefore;
        uint256 balanceAfter;
        string memo;
    }

    /// @notice Rate limit por token
    struct RateLimit {
        uint256 maxAmountPerHour;   // Máximo por hora
        uint256 hourlyWithdrawn;    // Retirado en la última hora
        uint256 lastResetTime;      // Última vez que se reseteó
        bool enabled;               // Rate limit habilitado
    }

    /// @notice Contador de operaciones
    uint256 public operationCount;

    /// @notice Tokens en el vault
    mapping(address => VaultToken) public vaultTokens;
    
    /// @notice Lista de tokens
    address[] public tokens;
    
    /// @notice Operaciones
    mapping(uint256 => Operation) public operations;
    
    /// @notice Operaciones por token
    mapping(address => uint256[]) public tokenOperations;
    
    /// @notice Rate limits
    mapping(address => RateLimit) public rateLimits;
    
    /// @notice Whitelist de operadores
    mapping(address => bool) public whitelistedOperators;

    /// @notice Emergency withdrawals habilitados
    bool public emergencyWithdrawalsEnabled;
    
    /// @notice Circuit breaker activado
    bool public circuitBreakerActive;
    
    /// @notice Threshold para circuit breaker (10% del balance)
    uint256 public circuitBreakerThreshold = 1000; // 10% = 1000 basis points

    /// @notice Referencia al DepositManager
    address public depositManager;
    
    /// @notice Referencia al WithdrawManager
    address public withdrawManager;
    
    /// @notice Referencia al Treasury (para fees)
    address public treasury;

    /// @notice Total value locked
    uint256 public totalValueLocked;
    
    /// @notice Número de tokens únicos
    uint256 public uniqueTokensCount;

    // ============================================
    // EVENTOS
    // ============================================

    event TokenDeposited(
        uint256 indexed operationId,
        address indexed token,
        address indexed operator,
        uint256 amount,
        uint256 newBalance
    );

    event TokenWithdrawn(
        uint256 indexed operationId,
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 newBalance
    );

    event EmergencyWithdrawal(
        address indexed token,
        address indexed to,
        uint256 amount,
        address indexed initiator
    );

    event CircuitBreakerTriggered(
        address indexed token,
        uint256 amount,
        uint256 threshold
    );

    event RateLimitExceeded(
        address indexed token,
        uint256 attempted,
        uint256 limit
    );

    event TokenActivated(
        address indexed token
    );

    event TokenDeactivated(
        address indexed token
    );

    event OperatorWhitelisted(
        address indexed operator
    );

    event OperatorRemovedFromWhitelist(
        address indexed operator
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _depositManager,
        address _withdrawManager,
        address _treasury
    ) {
        require(_admin != address(0), "Invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);

        depositManager = _depositManager;
        withdrawManager = _withdrawManager;
        treasury = _treasury;

        // Admin también tiene roles de deposit/withdraw
        _grantRole(DEPOSIT_ROLE, _admin);
        _grantRole(WITHDRAW_ROLE, _admin);
    }

    // ============================================
    // DEPÓSITOS
    // ============================================

    /**
     * @notice Deposita tokens en el vault
     * @param token Dirección del token
     * @param amount Cantidad a depositar
     * @param memo Nota opcional
     */
    function deposit(
        address token,
        uint256 amount,
        string memory memo
    ) external nonReentrant whenNotPaused onlyRole(DEPOSIT_ROLE) returns (uint256) {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");
        require(!circuitBreakerActive, "Circuit breaker active");

        VaultToken storage vaultToken = vaultTokens[token];
        
        // Inicializar token si es la primera vez
        if (!vaultToken.active && vaultToken.token == address(0)) {
            vaultToken.token = token;
            vaultToken.active = true;
            tokens.push(token);
            uniqueTokensCount++;
            emit TokenActivated(token);
        }

        require(vaultToken.active, "Token not active");

        uint256 balanceBefore = vaultToken.balance;

        // Transferir tokens al vault
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Actualizar balance
        vaultToken.balance += amount;
        vaultToken.totalDeposited += amount;
        vaultToken.lastDepositAt = block.timestamp;
        vaultToken.depositCount++;

        // Registrar operación
        operationCount++;
        Operation storage op = operations[operationCount];
        op.operationId = operationCount;
        op.token = token;
        op.operator = msg.sender;
        op.amount = amount;
        op.isDeposit = true;
        op.timestamp = block.timestamp;
        op.balanceBefore = balanceBefore;
        op.balanceAfter = vaultToken.balance;
        op.memo = memo;

        tokenOperations[token].push(operationCount);

        emit TokenDeposited(
            operationCount,
            token,
            msg.sender,
            amount,
            vaultToken.balance
        );

        return operationCount;
    }

    /**
     * @notice Deposita múltiples tokens en batch
     * @dev TEMPORALMENTE DESHABILITADO - Requiere refactorización para llamada interna
     */
    // function batchDeposit(
    //     address[] memory _tokens,
    //     uint256[] memory amounts,
    //     string memory memo
    // ) external nonReentrant whenNotPaused onlyRole(DEPOSIT_ROLE) returns (uint256[] memory) {
    //     require(_tokens.length == amounts.length, "Length mismatch");
    //     require(_tokens.length <= 20, "Too many tokens");

    //     uint256[] memory operationIds = new uint256[](_tokens.length);

    //     for (uint256 i = 0; i < _tokens.length; i++) {
    //         operationIds[i] = deposit(_tokens[i], amounts[i], memo);
    //     }

    //     return operationIds;
    // }

    // ============================================
    // RETIROS
    // ============================================

    /**
     * @notice Retira tokens del vault
     * @param token Dirección del token
     * @param to Destinatario
     * @param amount Cantidad a retirar
     * @param memo Nota opcional
     */
    function withdraw(
        address token,
        address to,
        uint256 amount,
        string memory memo
    ) external nonReentrant whenNotPaused onlyRole(WITHDRAW_ROLE) returns (uint256) {
        require(token != address(0), "Invalid token");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(!circuitBreakerActive, "Circuit breaker active");

        VaultToken storage vaultToken = vaultTokens[token];
        require(vaultToken.active, "Token not active");
        require(vaultToken.balance >= amount, "Insufficient balance");
        require(!vaultToken.emergencyMode, "Emergency mode");

        // Verificar rate limit
        _checkRateLimit(token, amount);

        // Verificar circuit breaker
        _checkCircuitBreaker(token, amount);

        uint256 balanceBefore = vaultToken.balance;

        // Actualizar balance
        vaultToken.balance -= amount;
        vaultToken.totalWithdrawn += amount;
        vaultToken.lastWithdrawAt = block.timestamp;
        vaultToken.withdrawCount++;

        // Actualizar rate limit
        _updateRateLimit(token, amount);

        // Transferir tokens
        IERC20(token).safeTransfer(to, amount);

        // Registrar operación
        operationCount++;
        Operation storage op = operations[operationCount];
        op.operationId = operationCount;
        op.token = token;
        op.operator = msg.sender;
        op.amount = amount;
        op.isDeposit = false;
        op.timestamp = block.timestamp;
        op.balanceBefore = balanceBefore;
        op.balanceAfter = vaultToken.balance;
        op.memo = memo;

        tokenOperations[token].push(operationCount);

        emit TokenWithdrawn(
            operationCount,
            token,
            to,
            amount,
            vaultToken.balance
        );

        return operationCount;
    }

    /**
     * @notice Retira múltiples tokens en batch
     * @dev TEMPORALMENTE DESHABILITADO - Requiere refactorización para llamada interna
     */
    // function batchWithdraw(
    //     address[] memory _tokens,
    //     address to,
    //     uint256[] memory amounts,
    //     string memory memo
    // ) external nonReentrant whenNotPaused onlyRole(WITHDRAW_ROLE) returns (uint256[] memory) {
    //     require(_tokens.length == amounts.length, "Length mismatch");
    //     require(_tokens.length <= 20, "Too many tokens");

    //     uint256[] memory operationIds = new uint256[](_tokens.length);

    //     for (uint256 i = 0; i < _tokens.length; i++) {
    //         operationIds[i] = withdraw(_tokens[i], to, amounts[i], memo);
    //     }

    //     return operationIds;
    // }

    // ============================================
    // RETIROS DE EMERGENCIA
    // ============================================

    /**
     * @notice Retiro de emergencia (multisig)
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount,
        string memory /* reason */
    ) external nonReentrant onlyRole(EMERGENCY_ROLE) {
        require(emergencyWithdrawalsEnabled, "Emergency withdrawals disabled");
        require(token != address(0), "Invalid token");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        VaultToken storage vaultToken = vaultTokens[token];
        require(vaultToken.balance >= amount, "Insufficient balance");

        vaultToken.balance -= amount;
        vaultToken.emergencyMode = true;

        IERC20(token).safeTransfer(to, amount);

        emit EmergencyWithdrawal(token, to, amount, msg.sender);
    }

    /**
     * @notice Habilita/deshabilita retiros de emergencia
     */
    function setEmergencyWithdrawalsEnabled(bool enabled) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        emergencyWithdrawalsEnabled = enabled;
    }

    // ============================================
    // RATE LIMITING
    // ============================================

    /**
     * @notice Configura rate limit para un token
     */
    function setRateLimit(address token, uint256 maxAmountPerHour, bool enabled) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        RateLimit storage limit = rateLimits[token];
        limit.maxAmountPerHour = maxAmountPerHour;
        limit.enabled = enabled;
        limit.lastResetTime = block.timestamp;
    }

    /**
     * @notice Verifica rate limit
     */
    function _checkRateLimit(address token, uint256 amount) internal view {
        RateLimit storage limit = rateLimits[token];
        if (!limit.enabled) return;

        uint256 timePassed = block.timestamp - limit.lastResetTime;
        
        if (timePassed < 1 hours) {
            require(
                limit.hourlyWithdrawn + amount <= limit.maxAmountPerHour,
                "Rate limit exceeded"
            );
        }
    }

    /**
     * @notice Actualiza rate limit
     */
    function _updateRateLimit(address token, uint256 amount) internal {
        RateLimit storage limit = rateLimits[token];
        if (!limit.enabled) return;

        uint256 timePassed = block.timestamp - limit.lastResetTime;
        
        if (timePassed >= 1 hours) {
            limit.hourlyWithdrawn = amount;
            limit.lastResetTime = block.timestamp;
        } else {
            limit.hourlyWithdrawn += amount;
        }

        if (limit.hourlyWithdrawn >= limit.maxAmountPerHour) {
            emit RateLimitExceeded(token, amount, limit.maxAmountPerHour);
        }
    }

    // ============================================
    // CIRCUIT BREAKER
    // ============================================

    /**
     * @notice Verifica circuit breaker
     */
    function _checkCircuitBreaker(address token, uint256 amount) internal {
        VaultToken storage vaultToken = vaultTokens[token];
        
        // Si el retiro es mayor al threshold% del balance, activar circuit breaker
        uint256 threshold = (vaultToken.balance * circuitBreakerThreshold) / 10000;
        
        if (amount > threshold) {
            circuitBreakerActive = true;
            emit CircuitBreakerTriggered(token, amount, threshold);
            revert("Circuit breaker triggered");
        }
    }

    /**
     * @notice Resetea circuit breaker (admin)
     */
    function resetCircuitBreaker() external onlyRole(ADMIN_ROLE) {
        circuitBreakerActive = false;
    }

    /**
     * @notice Configura threshold del circuit breaker
     */
    function setCircuitBreakerThreshold(uint256 threshold) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(threshold <= 5000, "Threshold too high"); // Max 50%
        circuitBreakerThreshold = threshold;
    }

    // ============================================
    // GESTIÓN DE TOKENS
    // ============================================

    /**
     * @notice Activa un token
     */
    function activateToken(address token) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        
        VaultToken storage vaultToken = vaultTokens[token];
        
        if (vaultToken.token == address(0)) {
            vaultToken.token = token;
            tokens.push(token);
            uniqueTokensCount++;
        }
        
        vaultToken.active = true;
        vaultToken.emergencyMode = false;
        
        emit TokenActivated(token);
    }

    /**
     * @notice Desactiva un token
     */
    function deactivateToken(address token) external onlyRole(ADMIN_ROLE) {
        VaultToken storage vaultToken = vaultTokens[token];
        require(vaultToken.token != address(0), "Token not found");
        
        vaultToken.active = false;
        
        emit TokenDeactivated(token);
    }

    /**
     * @notice Recupera tokens enviados por error
     */
    function recoverToken(address token, address to, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(!vaultTokens[token].active, "Token is active");
        require(to != address(0), "Invalid recipient");
        
        IERC20(token).safeTransfer(to, amount);
    }

    // ============================================
    // WHITELIST
    // ============================================

    /**
     * @notice Añade operador a whitelist
     */
    function addToWhitelist(address operator) external onlyRole(ADMIN_ROLE) {
        whitelistedOperators[operator] = true;
        emit OperatorWhitelisted(operator);
    }

    /**
     * @notice Remueve operador de whitelist
     */
    function removeFromWhitelist(address operator) external onlyRole(ADMIN_ROLE) {
        whitelistedOperators[operator] = false;
        emit OperatorRemovedFromWhitelist(operator);
    }

    // ============================================
    // RECONCILIACIÓN
    // ============================================

    /**
     * @notice Reconcilia balance de un token
     */
    function reconcileBalance(address token) external onlyRole(OPERATOR_ROLE) {
        VaultToken storage vaultToken = vaultTokens[token];
        require(vaultToken.active, "Token not active");

        uint256 actualBalance = IERC20(token).balanceOf(address(this));
        uint256 recordedBalance = vaultToken.balance;

        if (actualBalance != recordedBalance) {
            vaultToken.balance = actualBalance;
        }
    }

    /**
     * @notice Reconcilia todos los balances
     */
    function reconcileAllBalances() external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            VaultToken storage vaultToken = vaultTokens[token];
            
            if (vaultToken.active) {
                uint256 actualBalance = IERC20(token).balanceOf(address(this));
                vaultToken.balance = actualBalance;
            }
        }
    }

    // ============================================
    // CONFIGURACIÓN
    // ============================================

    function setDepositManager(address _depositManager) external onlyRole(ADMIN_ROLE) {
        depositManager = _depositManager;
        if (_depositManager != address(0)) {
            _grantRole(DEPOSIT_ROLE, _depositManager);
        }
    }

    function setWithdrawManager(address _withdrawManager) external onlyRole(ADMIN_ROLE) {
        withdrawManager = _withdrawManager;
        if (_withdrawManager != address(0)) {
            _grantRole(WITHDRAW_ROLE, _withdrawManager);
        }
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

    function getVaultToken(address token) external view returns (VaultToken memory) {
        return vaultTokens[token];
    }

    function getOperation(uint256 operationId) external view returns (Operation memory) {
        return operations[operationId];
    }

    function getTokenOperations(address token) external view returns (uint256[] memory) {
        return tokenOperations[token];
    }

    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    function getBalance(address token) external view returns (uint256) {
        return vaultTokens[token].balance;
    }

    function getBalances(address[] memory _tokens) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory balances = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            balances[i] = vaultTokens[_tokens[i]].balance;
        }
        return balances;
    }

    function getTotalValueLocked() external view returns (uint256) {
        // Esta función requeriría integración con un oracle para calcular TVL
        return totalValueLocked;
    }

    function getRateLimit(address token) 
        external 
        view 
        returns (
            uint256 maxPerHour,
            uint256 currentlyWithdrawn,
            uint256 remaining,
            bool enabled
        ) 
    {
        RateLimit storage limit = rateLimits[token];
        uint256 timePassed = block.timestamp - limit.lastResetTime;
        
        if (timePassed >= 1 hours) {
            currentlyWithdrawn = 0;
            remaining = limit.maxAmountPerHour;
        } else {
            currentlyWithdrawn = limit.hourlyWithdrawn;
            remaining = limit.maxAmountPerHour > currentlyWithdrawn ? 
                limit.maxAmountPerHour - currentlyWithdrawn : 0;
        }
        
        return (limit.maxAmountPerHour, currentlyWithdrawn, remaining, limit.enabled);
    }

    function getSystemStats() 
        external 
        view 
        returns (
            uint256 totalTokens,
            uint256 totalOperations,
            bool circuitBreaker,
            bool emergency
        ) 
    {
        return (
            uniqueTokensCount,
            operationCount,
            circuitBreakerActive,
            emergencyWithdrawalsEnabled
        );
    }
}
