// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IAssetManager.sol";

/**
 * @title WithdrawManager
 * @notice Gestión centralizada de retiros con límites y verificaciones
 * @dev Maneja retiros de múltiples tokens con controles de seguridad
 * 
 * Características principales:
 * - Retiros multi-token con whitelist
 * - Límites diarios por usuario por token
 * - Límites mínimos y máximos por retiro
 * - Fees de retiro configurables por token
 * - Verificación KYC opcional por token
 * - Integración con WithdrawQueue para retiros grandes
 * - Timelock opcional para retiros grandes
 * - Anti-fraud: verificación de saldo, cooldown
 * - Emergency withdrawals con autorización especial
 * - Batch withdrawals para múltiples tokens
 * - Integración con vault para extraer fondos
 * - Integración con BalanceManager
 * - Historial completo de retiros
 * 
 * Flujo de retiro normal:
 * 1. Usuario llama withdraw() con token y cantidad
 * 2. Sistema verifica whitelist, límites, saldo
 * 3. Si retiro > threshold, se encola en WithdrawQueue
 * 4. Si retiro normal, se ejecuta inmediatamente
 * 5. Se descuenta fee, se actualiza balance
 * 6. Se transfiere desde vault al usuario
 * 7. Se emite evento WithdrawExecuted
 * 
 * Flujo de retiro grande:
 * 1. Usuario llama withdraw() con cantidad > queueThreshold
 * 2. Sistema crea orden en WithdrawQueue
 * 3. Orden espera timelock (ej: 24h)
 * 4. Después de timelock, se puede ejecutar
 * 5. Admin o sistema ejecuta retiro desde queue
 * 
 * Seguridad:
 * - ReentrancyGuard en todas las funciones de retiro
 * - SafeERC20 para transferencias seguras
 * - Verificación de saldo antes de retiro
 * - Cooldown entre retiros para prevenir draining
 * - Límites diarios que se resetean automáticamente
 * - Whitelist de tokens permitidos
 * - KYC verification para tokens regulados
 * - Emergency pause para detener retiros
 */
contract WithdrawManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Configuración de token para retiros
    struct TokenConfig {
        bool whitelisted;
        uint256 minWithdraw;
        uint256 maxWithdraw;
        uint256 dailyLimit;
        uint256 withdrawFee;
        uint256 queueThreshold;
        bool requiresKYC;
        bool enabled;
        uint256 cooldownPeriod;
    }

    /// @notice Límite diario de usuario
    struct UserDailyLimit {
        uint256 withdrawn;
        uint256 lastResetTime;
    }

    /// @notice Información de retiro
    struct WithdrawInfo {
        uint256 id;
        address user;
        address token;
        uint256 amount;
        uint256 fee;
        uint256 netAmount;
        uint256 timestamp;
        bool executed;
        bool queued;
    }

    /// @notice Configuraciones de tokens
    mapping(address => TokenConfig) public tokenConfigs;
    
    /// @notice Límites diarios por usuario por token
    mapping(address => mapping(address => UserDailyLimit)) public userDailyLimits;
    
    /// @notice Último retiro de usuario
    mapping(address => uint256) public lastWithdrawTime;
    
    /// @notice Historial de retiros
    mapping(uint256 => WithdrawInfo) public withdrawals;
    
    /// @notice Contador de retiros
    uint256 public withdrawCounter;
    
    /// @notice Retiros pendientes en queue
    mapping(address => uint256[]) public userQueuedWithdrawals;

    /// @notice Total retirado por token
    mapping(address => uint256) public totalWithdrawnByToken;
    
    /// @notice Total de usuarios que han retirado
    uint256 public totalWithdrawers;
    
    /// @notice Usuarios que han retirado
    mapping(address => bool) public hasWithdrawn;

    /// @notice Cooldown global entre retiros
    uint256 public globalCooldown;

    /// @notice Referencia al vault
    address public vault;
    
    /// @notice Referencia al BalanceManager
    address public balanceManager;
    
    /// @notice Referencia al WithdrawQueue
    address public withdrawQueue;
    
    /// @notice Referencia al KYC Manager
    address public kycManager;
    
    /// @notice Referencia al Price Oracle
    address public priceOracle;

    /// @notice Referencia al AssetManager
    address public assetManager;

    /// @notice Emergency withdrawals habilitados
    bool public emergencyWithdrawalsEnabled;

    // ============================================
    // EVENTOS
    // ============================================

    event WithdrawExecuted(
        uint256 indexed withdrawId,
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 fee,
        uint256 netAmount
    );

    event WithdrawQueued(
        uint256 indexed withdrawId,
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 queueId
    );

    event TokenConfigured(
        address indexed token,
        uint256 minWithdraw,
        uint256 maxWithdraw,
        uint256 dailyLimit
    );

    event DailyLimitReset(
        address indexed user,
        address indexed token,
        uint256 newResetTime
    );

    event EmergencyWithdraw(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _vault,
        address _balanceManager
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_vault != address(0), "Invalid vault");
        require(_balanceManager != address(0), "Invalid balance manager");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        vault = _vault;
        balanceManager = _balanceManager;
        globalCooldown = 60; // 1 minuto por defecto
    }

    // ============================================
    // RETIRO PRINCIPAL
    // ============================================

    /**
     * @notice Retira tokens
     * @param token Token a retirar
     * @param amount Cantidad a retirar
     */
    function withdraw(
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(amount > 0, "Invalid amount");
        
        address user = msg.sender;

        // Validar con AssetManager si está configurado
        if (assetManager != address(0)) {
            require(
                IAssetManager(assetManager).canTokenBeWithdrawn(token),
                "Withdrawals disabled for this token in AssetManager"
            );
            
            // Verificar límites del AssetManager
            IAssetManager.TokenInfo memory tokenInfo = IAssetManager(assetManager).getTokenInfo(token);
            require(amount >= tokenInfo.minWithdrawAmount, "Below AssetManager minimum");
            require(amount <= tokenInfo.maxWithdrawAmount, "Exceeds AssetManager maximum");
        }

        // Verificaciones básicas
        _verifyWithdraw(user, token, amount);

        // Verificar cooldown
        _checkCooldown(user, token);

        // Verificar y actualizar límite diario
        _checkAndUpdateDailyLimit(user, token, amount);

        // Calcular fee
        uint256 fee = _calculateFee(token, amount);
        uint256 netAmount = amount - fee;

        withdrawCounter++;
        uint256 withdrawId = withdrawCounter;

        // Si el retiro es grande, encolar
        TokenConfig memory config = tokenConfigs[token];
        if (amount >= config.queueThreshold && withdrawQueue != address(0)) {
            return _queueWithdraw(withdrawId, user, token, amount, fee, netAmount);
        }

        // Ejecutar retiro inmediato
        _executeWithdraw(withdrawId, user, token, amount, fee, netAmount, false);

        return withdrawId;
    }

    /**
     * @notice Retiro por lotes
     */
    function batchWithdraw(
        address[] memory tokens,
        uint256[] memory amounts
    ) external nonReentrant whenNotPaused returns (uint256[] memory) {
        require(tokens.length == amounts.length, "Length mismatch");
        require(tokens.length <= 10, "Too many tokens");

        uint256[] memory withdrawIds = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            require(amounts[i] > 0, "Invalid amount");
            
            address user = msg.sender;
            address token = tokens[i];
            uint256 amount = amounts[i];

            _verifyWithdraw(user, token, amount);
            _checkCooldown(user, token);
            _checkAndUpdateDailyLimit(user, token, amount);

            uint256 fee = _calculateFee(token, amount);
            uint256 netAmount = amount - fee;

            withdrawCounter++;
            uint256 withdrawId = withdrawCounter;
            withdrawIds[i] = withdrawId;

            TokenConfig memory config = tokenConfigs[token];
            if (amount >= config.queueThreshold && withdrawQueue != address(0)) {
                _queueWithdraw(withdrawId, user, token, amount, fee, netAmount);
            } else {
                _executeWithdraw(withdrawId, user, token, amount, fee, netAmount, false);
            }
        }

        return withdrawIds;
    }

    /**
     * @notice Ejecuta retiro desde queue
     */
    function executeQueuedWithdraw(
        uint256 withdrawId
    ) external nonReentrant onlyRole(OPERATOR_ROLE) {
        WithdrawInfo storage info = withdrawals[withdrawId];
        require(info.queued, "Not queued");
        require(!info.executed, "Already executed");

        _executeWithdraw(
            withdrawId,
            info.user,
            info.token,
            info.amount,
            info.fee,
            info.netAmount,
            true
        );
    }

    /**
     * @notice Retiro de emergencia (sin límites)
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external nonReentrant {
        require(emergencyWithdrawalsEnabled, "Emergency withdrawals disabled");
        require(amount > 0, "Invalid amount");

        address user = msg.sender;

        // Solo verificar whitelist y saldo
        require(tokenConfigs[token].whitelisted, "Token not whitelisted");
        
        // Verificar saldo en BalanceManager
        (bool success, bytes memory data) = balanceManager.staticcall(
            abi.encodeWithSignature("getAvailableBalance(address,address)", user, token)
        );
        require(success, "Balance check failed");
        uint256 available = abi.decode(data, (uint256));
        require(available >= amount, "Insufficient balance");

        // Descontar de BalanceManager (sin fee en emergencia)
        (success, ) = balanceManager.call(
            abi.encodeWithSignature("unlockBalance(address,address,uint256)", user, token, amount)
        );
        require(success, "Balance unlock failed");

        // Transferir desde vault
        (success, ) = vault.call(
            abi.encodeWithSignature("withdraw(address,address,uint256)", token, user, amount)
        );
        require(success, "Vault withdrawal failed");

        emit EmergencyWithdraw(user, token, amount);
    }

    // ============================================
    // FUNCIONES INTERNAS
    // ============================================

    /**
     * @notice Verifica condiciones de retiro
     */
    function _verifyWithdraw(
        address user,
        address token,
        uint256 amount
    ) internal view {
        TokenConfig memory config = tokenConfigs[token];
        
        require(config.whitelisted, "Token not whitelisted");
        require(config.enabled, "Token disabled");
        require(amount >= config.minWithdraw, "Below minimum");
        require(amount <= config.maxWithdraw, "Above maximum");

        // Verificar KYC si es requerido
        if (config.requiresKYC && kycManager != address(0)) {
            (bool kycSuccess, bytes memory kycData) = kycManager.staticcall(
                abi.encodeWithSignature("isKYCVerified(address)", user)
            );
            require(kycSuccess && abi.decode(kycData, (bool)), "KYC required");
        }

        // Verificar saldo disponible
        (bool balanceSuccess, bytes memory balanceData) = balanceManager.staticcall(
            abi.encodeWithSignature("getAvailableBalance(address,address)", user, token)
        );
        require(balanceSuccess, "Balance check failed");
        uint256 available = abi.decode(balanceData, (uint256));
        require(available >= amount, "Insufficient balance");
    }

    /**
     * @notice Verifica cooldown
     */
    function _checkCooldown(address user, address token) internal view {
        TokenConfig memory config = tokenConfigs[token];
        uint256 cooldown = config.cooldownPeriod > 0 ? config.cooldownPeriod : globalCooldown;
        
        if (cooldown > 0) {
            uint256 timeSinceLastWithdraw = block.timestamp - lastWithdrawTime[user];
            require(timeSinceLastWithdraw >= cooldown, "Cooldown active");
        }
    }

    /**
     * @notice Verifica y actualiza límite diario
     */
    function _checkAndUpdateDailyLimit(
        address user,
        address token,
        uint256 amount
    ) internal {
        TokenConfig memory config = tokenConfigs[token];
        if (config.dailyLimit == 0) return; // Sin límite

        UserDailyLimit storage limit = userDailyLimits[user][token];

        // Resetear si pasó un día
        if (block.timestamp >= limit.lastResetTime + 1 days) {
            limit.withdrawn = 0;
            limit.lastResetTime = block.timestamp;
            emit DailyLimitReset(user, token, block.timestamp);
        }

        // Verificar límite
        require(limit.withdrawn + amount <= config.dailyLimit, "Daily limit exceeded");

        // Actualizar
        limit.withdrawn += amount;
    }

    /**
     * @notice Calcula fee de retiro
     */
    function _calculateFee(address token, uint256 amount) internal view returns (uint256) {
        TokenConfig memory config = tokenConfigs[token];
        if (config.withdrawFee == 0) return 0;
        
        return (amount * config.withdrawFee) / 10000; // Basis points
    }

    /**
     * @notice Encola retiro
     */
    function _queueWithdraw(
        uint256 withdrawId,
        address user,
        address token,
        uint256 amount,
        uint256 fee,
        uint256 netAmount
    ) internal returns (uint256) {
        // Guardar información
        WithdrawInfo storage info = withdrawals[withdrawId];
        info.id = withdrawId;
        info.user = user;
        info.token = token;
        info.amount = amount;
        info.fee = fee;
        info.netAmount = netAmount;
        info.timestamp = block.timestamp;
        info.executed = false;
        info.queued = true;

        // Agregar a queue del usuario
        userQueuedWithdrawals[user].push(withdrawId);

        // Llamar a WithdrawQueue para crear orden
        (bool success, bytes memory data) = withdrawQueue.call(
            abi.encodeWithSignature(
                "createWithdrawOrder(address,address,uint256,uint256)",
                user,
                token,
                amount,
                netAmount
            )
        );
        require(success, "Queue creation failed");
        uint256 queueId = abi.decode(data, (uint256));

        // Bloquear fondos en BalanceManager
        (success, ) = balanceManager.call(
            abi.encodeWithSignature("lockBalance(address,address,uint256,uint8)", user, token, amount, 4) // WITHDRAW lock
        );
        require(success, "Balance lock failed");

        emit WithdrawQueued(withdrawId, user, token, amount, queueId);

        return withdrawId;
    }

    /**
     * @notice Ejecuta retiro
     */
    function _executeWithdraw(
        uint256 withdrawId,
        address user,
        address token,
        uint256 amount,
        uint256 fee,
        uint256 netAmount,
        bool fromQueue
    ) internal {
        // Guardar o actualizar información
        WithdrawInfo storage info = withdrawals[withdrawId];
        if (!fromQueue) {
            info.id = withdrawId;
            info.user = user;
            info.token = token;
            info.amount = amount;
            info.fee = fee;
            info.netAmount = netAmount;
            info.timestamp = block.timestamp;
            info.queued = false;
        }
        info.executed = true;

        // Si no viene de queue, bloquear balance
        if (!fromQueue) {
            (bool unlockSuccess, ) = balanceManager.call(
                abi.encodeWithSignature("unlockBalance(address,address,uint256)", user, token, amount)
            );
            require(unlockSuccess, "Balance unlock failed");
        } else {
            // Si viene de queue, desbloquear
            (bool unlockSuccess2, ) = balanceManager.call(
                abi.encodeWithSignature("unlockBalance(address,address,uint256)", user, token, amount)
            );
            require(unlockSuccess2, "Balance unlock failed");
        }

        // Transferir desde vault al usuario
        (bool vaultSuccess, ) = vault.call(
            abi.encodeWithSignature("withdraw(address,address,uint256)", token, user, netAmount)
        );
        require(vaultSuccess, "Vault withdrawal failed");

        // Si hay fee, transferir a treasury
        if (fee > 0) {
            // Fee se queda en vault, no se transfiere
            // Treasury puede reclamar después
        }

        // Actualizar estadísticas
        totalWithdrawnByToken[token] += netAmount;
        
        if (!hasWithdrawn[user]) {
            hasWithdrawn[user] = true;
            totalWithdrawers++;
        }

        // Actualizar último retiro
        lastWithdrawTime[user] = block.timestamp;

        emit WithdrawExecuted(withdrawId, user, token, amount, fee, netAmount);
    }

    // ============================================
    // CONFIGURACIÓN
    // ============================================

    /**
     * @notice Configura token para retiros
     */
    function configureToken(
        address token,
        uint256 minWithdraw,
        uint256 maxWithdraw,
        uint256 dailyLimit,
        uint256 withdrawFee,
        uint256 queueThreshold,
        bool requiresKYC,
        uint256 cooldownPeriod
    ) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(maxWithdraw >= minWithdraw, "Invalid limits");
        require(withdrawFee <= 1000, "Fee too high"); // Max 10%

        TokenConfig storage config = tokenConfigs[token];
        config.whitelisted = true;
        config.minWithdraw = minWithdraw;
        config.maxWithdraw = maxWithdraw;
        config.dailyLimit = dailyLimit;
        config.withdrawFee = withdrawFee;
        config.queueThreshold = queueThreshold;
        config.requiresKYC = requiresKYC;
        config.enabled = true;
        config.cooldownPeriod = cooldownPeriod;

        emit TokenConfigured(token, minWithdraw, maxWithdraw, dailyLimit);
    }

    /**
     * @notice Habilita/deshabilita token
     */
    function setTokenEnabled(address token, bool enabled) external onlyRole(ADMIN_ROLE) {
        tokenConfigs[token].enabled = enabled;
    }

    /**
     * @notice Configura cooldown global
     */
    function setGlobalCooldown(uint256 cooldown) external onlyRole(ADMIN_ROLE) {
        globalCooldown = cooldown;
    }

    /**
     * @notice Configura WithdrawQueue
     */
    function setWithdrawQueue(address _withdrawQueue) external onlyRole(ADMIN_ROLE) {
        require(_withdrawQueue != address(0), "Invalid address");
        withdrawQueue = _withdrawQueue;
    }

    /**
     * @notice Configura KYC Manager
     */
    function setKYCManager(address _kycManager) external onlyRole(ADMIN_ROLE) {
        kycManager = _kycManager;
    }

    /**
     * @notice Configura Price Oracle
     */
    function setPriceOracle(address _priceOracle) external onlyRole(ADMIN_ROLE) {
        priceOracle = _priceOracle;
    }

    /**
     * @notice Habilita/deshabilita emergency withdrawals
     */
    function setEmergencyWithdrawalsEnabled(bool enabled) external onlyRole(ADMIN_ROLE) {
        emergencyWithdrawalsEnabled = enabled;
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

    /**
     * @notice Obtiene configuración de token
     */
    function getTokenConfig(address token) external view returns (TokenConfig memory) {
        return tokenConfigs[token];
    }

    /**
     * @notice Obtiene límite diario de usuario
     */
    function getUserDailyLimit(address user, address token) external view returns (uint256 withdrawn, uint256 limit, uint256 remaining) {
        UserDailyLimit memory userLimit = userDailyLimits[user][token];
        TokenConfig memory config = tokenConfigs[token];
        
        withdrawn = userLimit.withdrawn;
        limit = config.dailyLimit;
        
        // Si pasó un día, el withdrawn es 0
        if (block.timestamp >= userLimit.lastResetTime + 1 days) {
            withdrawn = 0;
        }
        
        if (limit == 0) {
            remaining = type(uint256).max;
        } else {
            remaining = limit > withdrawn ? limit - withdrawn : 0;
        }
    }

    /**
     * @notice Obtiene información de retiro
     */
    function getWithdrawInfo(uint256 withdrawId) external view returns (WithdrawInfo memory) {
        return withdrawals[withdrawId];
    }

    /**
     * @notice Obtiene retiros en queue de usuario
     */
    function getUserQueuedWithdrawals(address user) external view returns (uint256[] memory) {
        return userQueuedWithdrawals[user];
    }

    /**
     * @notice Verifica si usuario puede retirar
     */
    function canWithdraw(
        address user,
        address token,
        uint256 amount
    ) external view returns (bool can, string memory reason) {
        TokenConfig memory config = tokenConfigs[token];
        
        if (!config.whitelisted) return (false, "Token not whitelisted");
        if (!config.enabled) return (false, "Token disabled");
        if (amount < config.minWithdraw) return (false, "Below minimum");
        if (amount > config.maxWithdraw) return (false, "Above maximum");

        // Verificar KYC
        if (config.requiresKYC && kycManager != address(0)) {
            (bool kycSuccess2, bytes memory kycData2) = kycManager.staticcall(
                abi.encodeWithSignature("isKYCVerified(address)", user)
            );
            if (!kycSuccess2 || !abi.decode(kycData2, (bool))) {
                return (false, "KYC required");
            }
        }

        // Verificar saldo
        (bool balanceSuccess2, bytes memory balanceData2) = balanceManager.staticcall(
            abi.encodeWithSignature("getAvailableBalance(address,address)", user, token)
        );
        if (!balanceSuccess2) return (false, "Balance check failed");
        uint256 available = abi.decode(balanceData2, (uint256));
        if (available < amount) return (false, "Insufficient balance");

        // Verificar cooldown
        uint256 cooldown = config.cooldownPeriod > 0 ? config.cooldownPeriod : globalCooldown;
        if (cooldown > 0) {
            uint256 timeSinceLastWithdraw = block.timestamp - lastWithdrawTime[user];
            if (timeSinceLastWithdraw < cooldown) {
                return (false, "Cooldown active");
            }
        }

        // Verificar límite diario
        if (config.dailyLimit > 0) {
            UserDailyLimit memory userLimit = userDailyLimits[user][token];
            uint256 withdrawn = userLimit.withdrawn;
            
            // Si pasó un día, resetear
            if (block.timestamp >= userLimit.lastResetTime + 1 days) {
                withdrawn = 0;
            }
            
            if (withdrawn + amount > config.dailyLimit) {
                return (false, "Daily limit exceeded");
            }
        }

        return (true, "Can withdraw");
    }

    /**
     * @notice Calcula fee de retiro
     */
    function calculateWithdrawFee(address token, uint256 amount) external view returns (uint256) {
        return _calculateFee(token, amount);
    }

    /**
     * @notice Obtiene estadísticas
     */
    function getStats() external view returns (
        uint256 totalWithdraws,
        uint256 uniqueWithdrawers
    ) {
        return (withdrawCounter, totalWithdrawers);
    }

    /**
     * @notice Obtiene total retirado de token
     */
    function getTotalWithdrawnByToken(address token) external view returns (uint256) {
        return totalWithdrawnByToken[token];
    }
}
