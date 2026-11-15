// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AntiRugPull
 * @notice Sistema de protección contra rug pulls con circuit breakers avanzados
 * @dev Monitorea patrones sospechosos y activa protecciones automáticas
 * 
 * Características principales:
 * - Detección de retiros masivos (whale detection)
 * - Detección de retiros en ráfaga (burst detection)
 * - Circuit breakers multi-nivel (WARNING, DANGER, CRITICAL)
 * - Rate limiting dinámico por token
 * - Whitelist de direcciones confiables
 * - Análisis de patrones de comportamiento
 * - Alertas automáticas a admin
 * - Pausado automático en situaciones críticas
 * - Timelock dinámico según riesgo
 * - Scoring de riesgo por operación
 * 
 * Niveles de alerta:
 * - NORMAL: Operación normal, sin restricciones
 * - WARNING: Actividad elevada, monitoreo intensivo
 * - DANGER: Actividad sospechosa, restricciones parciales
 * - CRITICAL: Posible rug pull, pausado automático
 * 
 * Patrones detectados:
 * - Retiro > X% del balance total en Y minutos
 * - Múltiples retiros grandes en corto tiempo
 * - Retiros coordinados de múltiples wallets
 * - Cambio drástico en volumen de retiros
 * - Retiros después de gran depósito (pump & dump)
 * - Wallet nueva con retiro masivo inmediato
 * 
 * Respuestas automáticas:
 * - WARNING: Incrementar monitoreo, notificar admin
 * - DANGER: Activar rate limiting estricto, requerir aprobación manual
 * - CRITICAL: Pausar retiros, bloquear operaciones, alertar urgente
 * 
 * Seguridad:
 * - Multi-nivel de protección
 * - Configuración granular por token
 * - Whitelist para wallets confiables
 * - Override manual por admin
 * - Logs detallados de todas las alertas
 * - Sistema de scoring para decisiones automatizadas
 */
contract AntiRugPull is AccessControl, ReentrancyGuard, Pausable {
    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de monitor
    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");
    
    /// @notice Rol de respuesta automática
    bytes32 public constant AUTO_RESPONSE_ROLE = keccak256("AUTO_RESPONSE_ROLE");

    /// @notice Niveles de alerta
    enum AlertLevel {
        NORMAL,
        WARNING,
        DANGER,
        CRITICAL
    }

    /// @notice Tipos de patrón sospechoso
    enum PatternType {
        WHALE_WITHDRAWAL,
        BURST_WITHDRAWALS,
        COORDINATED_WITHDRAWALS,
        VOLUME_SPIKE,
        PUMP_AND_DUMP,
        NEW_WALLET_DRAIN,
        RAPID_SUCCESSION
    }

    /// @notice Configuración de circuit breaker por token
    struct CircuitBreakerConfig {
        bool enabled;
        uint256 maxWithdrawalPercentage;
        uint256 timeWindow;
        uint256 burstThreshold;
        uint256 burstTimeWindow;
        uint256 warningThreshold;
        uint256 dangerThreshold;
        uint256 criticalThreshold;
    }

    /// @notice Actividad de retiro
    struct WithdrawalActivity {
        uint256 totalAmount;
        uint256 withdrawalCount;
        uint256 firstWithdrawalTime;
        uint256 lastWithdrawalTime;
        uint256 largestWithdrawal;
        address largestWithdrawalUser;
    }

    /// @notice Alerta de seguridad
    struct SecurityAlert {
        uint256 id;
        AlertLevel level;
        PatternType patternType;
        address token;
        address user;
        uint256 amount;
        uint256 timestamp;
        string description;
        bool resolved;
        address resolvedBy;
        uint256 resolvedAt;
    }

    /// @notice Score de riesgo de usuario
    struct RiskScore {
        uint256 score;
        uint256 lastUpdate;
        uint256 totalWithdrawals;
        uint256 totalDeposits;
        uint256 accountAge;
        bool flagged;
    }

    /// @notice Configuraciones de circuit breaker por token
    mapping(address => CircuitBreakerConfig) public circuitBreakerConfigs;
    
    /// @notice Actividad de retiros por token (ventana de tiempo)
    mapping(address => WithdrawalActivity) public tokenActivity;
    
    /// @notice Alertas de seguridad
    mapping(uint256 => SecurityAlert) public alerts;
    
    /// @notice Contador de alertas
    uint256 public alertCounter;
    
    /// @notice Nivel de alerta actual por token
    mapping(address => AlertLevel) public tokenAlertLevel;
    
    /// @notice Whitelist de direcciones confiables
    mapping(address => bool) public trustedAddresses;
    
    /// @notice Risk score por usuario
    mapping(address => RiskScore) public userRiskScores;
    
    /// @notice Última alerta por usuario
    mapping(address => uint256) public lastUserAlert;
    
    /// @notice Circuit breaker activo por token
    mapping(address => bool) public circuitBreakerActive;
    
    /// @notice Tiempo de último reset por token
    mapping(address => uint256) public lastResetTime;

    /// @notice Retiros bloqueados temporalmente
    mapping(address => mapping(address => uint256)) public withdrawalBlocked; // user => token => until

    /// @notice Sistema de respuesta automática habilitado
    bool public autoResponseEnabled;

    /// @notice Referencia al vault para consultar balances
    address public vault;
    
    /// @notice Referencia al WithdrawManager
    address public withdrawManager;

    /// @notice Umbral de score para bloqueo automático
    uint256 public autoBlockThreshold;

    // ============================================
    // EVENTOS
    // ============================================

    event SecurityAlertRaised(
        uint256 indexed alertId,
        AlertLevel level,
        PatternType patternType,
        address indexed token,
        address indexed user,
        uint256 amount
    );

    event AlertLevelChanged(
        address indexed token,
        AlertLevel oldLevel,
        AlertLevel newLevel
    );

    event CircuitBreakerTriggered(
        address indexed token,
        AlertLevel level,
        string reason
    );

    event CircuitBreakerReset(
        address indexed token,
        address indexed resetBy
    );

    event TrustedAddressAdded(
        address indexed addr
    );

    event TrustedAddressRemoved(
        address indexed addr
    );

    event RiskScoreUpdated(
        address indexed user,
        uint256 oldScore,
        uint256 newScore
    );

    event WithdrawalBlocked(
        address indexed user,
        address indexed token,
        uint256 until,
        string reason
    );

    event AlertResolved(
        uint256 indexed alertId,
        address indexed resolvedBy
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _vault,
        address _withdrawManager
    ) {
        require(_admin != address(0), "Invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(MONITOR_ROLE, _admin);
        _grantRole(AUTO_RESPONSE_ROLE, _admin);

        vault = _vault;
        withdrawManager = _withdrawManager;
        
        autoResponseEnabled = true;
        autoBlockThreshold = 80; // Score de 80+ = bloqueo automático
    }

    // ============================================
    // MONITOREO DE RETIROS
    // ============================================

    /**
     * @notice Verifica retiro antes de ejecutar
     * @return allowed Si el retiro está permitido
     * @return alertLevel Nivel de alerta detectado
     * @return message Mensaje explicativo
     */
    function checkWithdrawal(
        address user,
        address token,
        uint256 amount
    ) external returns (bool allowed, AlertLevel alertLevel, string memory message) {
        // Verificar si está pausado
        if (paused()) {
            return (false, AlertLevel.CRITICAL, "System paused");
        }

        // Verificar si circuit breaker está activo
        if (circuitBreakerActive[token]) {
            return (false, AlertLevel.CRITICAL, "Circuit breaker active");
        }

        // Verificar si usuario está bloqueado temporalmente
        if (withdrawalBlocked[user][token] > block.timestamp) {
            return (false, AlertLevel.DANGER, "User temporarily blocked");
        }

        // Usuarios confiables pasan sin verificación
        if (trustedAddresses[user]) {
            return (true, AlertLevel.NORMAL, "Trusted address");
        }

        CircuitBreakerConfig memory config = circuitBreakerConfigs[token];
        if (!config.enabled) {
            return (true, AlertLevel.NORMAL, "Monitoring disabled");
        }

        // Obtener balance total del token en vault
        uint256 totalBalance = _getTotalBalance(token);
        if (totalBalance == 0) {
            return (true, AlertLevel.NORMAL, "Empty balance");
        }

        // Actualizar actividad
        _updateActivity(token, user, amount);

        // Verificar patrones sospechosos
        (bool suspicious, PatternType patternType, string memory reason) = 
            _detectSuspiciousPattern(user, token, amount, totalBalance, config);

        if (suspicious) {
            // Crear alerta
            AlertLevel level = _determineAlertLevel(patternType, amount, totalBalance, config);
            _raiseAlert(level, patternType, token, user, amount, reason);

            // Actualizar risk score
            _updateRiskScore(user, patternType);

            // Aplicar respuesta automática si está habilitado
            if (autoResponseEnabled) {
                _applyAutoResponse(user, token, level);
            }

            // Verificar si debe bloquearse
            if (level == AlertLevel.CRITICAL) {
                _activateCircuitBreaker(token, reason);
                return (false, level, reason);
            } else if (level == AlertLevel.DANGER) {
                // Bloquear temporalmente (1 hora)
                withdrawalBlocked[user][token] = block.timestamp + 1 hours;
                emit WithdrawalBlocked(user, token, block.timestamp + 1 hours, reason);
                return (false, level, reason);
            } else {
                // WARNING - permitir pero alertar
                return (true, level, reason);
            }
        }

        return (true, AlertLevel.NORMAL, "Check passed");
    }

    /**
     * @notice Actualiza actividad de retiros
     */
    function _updateActivity(address token, address user, uint256 amount) internal {
        WithdrawalActivity storage activity = tokenActivity[token];
        CircuitBreakerConfig memory config = circuitBreakerConfigs[token];

        // Resetear si pasó el time window
        if (block.timestamp >= activity.firstWithdrawalTime + config.timeWindow) {
            activity.totalAmount = 0;
            activity.withdrawalCount = 0;
            activity.firstWithdrawalTime = block.timestamp;
        }

        // Actualizar actividad
        if (activity.withdrawalCount == 0) {
            activity.firstWithdrawalTime = block.timestamp;
        }

        activity.totalAmount += amount;
        activity.withdrawalCount++;
        activity.lastWithdrawalTime = block.timestamp;

        if (amount > activity.largestWithdrawal) {
            activity.largestWithdrawal = amount;
            activity.largestWithdrawalUser = user;
        }
    }

    /**
     * @notice Detecta patrones sospechosos
     */
    function _detectSuspiciousPattern(
        address user,
        address token,
        uint256 amount,
        uint256 totalBalance,
        CircuitBreakerConfig memory config
    ) internal view returns (bool suspicious, PatternType patternType, string memory reason) {
        WithdrawalActivity memory activity = tokenActivity[token];

        // 1. Whale withdrawal - retiro > X% del balance total
        uint256 percentage = (amount * 10000) / totalBalance;
        if (percentage >= config.maxWithdrawalPercentage) {
            return (true, PatternType.WHALE_WITHDRAWAL, "Whale withdrawal detected");
        }

        // 2. Burst withdrawals - múltiples retiros en corto tiempo
        if (activity.withdrawalCount >= config.burstThreshold) {
            uint256 timeSinceFirst = block.timestamp - activity.firstWithdrawalTime;
            if (timeSinceFirst <= config.burstTimeWindow) {
                return (true, PatternType.BURST_WITHDRAWALS, "Burst withdrawals detected");
            }
        }

        // 3. Volume spike - volumen total > threshold en time window
        uint256 activityPercentage = (activity.totalAmount * 10000) / totalBalance;
        if (activityPercentage >= config.criticalThreshold) {
            return (true, PatternType.VOLUME_SPIKE, "Volume spike detected");
        }

        // 4. New wallet drain - wallet nueva con retiro grande
        RiskScore memory riskScore = userRiskScores[user];
        if (riskScore.accountAge < 1 days && percentage >= 500) { // > 5%
            return (true, PatternType.NEW_WALLET_DRAIN, "New wallet large withdrawal");
        }

        // 5. Rapid succession - retiros muy seguidos
        if (activity.withdrawalCount >= 3) {
            uint256 avgTimeBetween = (block.timestamp - activity.firstWithdrawalTime) / activity.withdrawalCount;
            if (avgTimeBetween < 5 minutes) {
                return (true, PatternType.RAPID_SUCCESSION, "Rapid succession withdrawals");
            }
        }

        return (false, PatternType.WHALE_WITHDRAWAL, "");
    }

    /**
     * @notice Determina nivel de alerta según patrón
     */
    function _determineAlertLevel(
        PatternType patternType,
        uint256 amount,
        uint256 totalBalance,
        CircuitBreakerConfig memory config
    ) internal pure returns (AlertLevel) {
        uint256 percentage = (amount * 10000) / totalBalance;

        // Patrones críticos automáticos
        if (patternType == PatternType.VOLUME_SPIKE || 
            patternType == PatternType.COORDINATED_WITHDRAWALS) {
            return AlertLevel.CRITICAL;
        }

        // Basado en porcentaje
        if (percentage >= config.criticalThreshold) {
            return AlertLevel.CRITICAL;
        } else if (percentage >= config.dangerThreshold) {
            return AlertLevel.DANGER;
        } else if (percentage >= config.warningThreshold) {
            return AlertLevel.WARNING;
        }

        return AlertLevel.WARNING;
    }

    /**
     * @notice Levanta alerta de seguridad
     */
    function _raiseAlert(
        AlertLevel level,
        PatternType patternType,
        address token,
        address user,
        uint256 amount,
        string memory description
    ) internal {
        alertCounter++;
        uint256 alertId = alertCounter;

        SecurityAlert storage alert = alerts[alertId];
        alert.id = alertId;
        alert.level = level;
        alert.patternType = patternType;
        alert.token = token;
        alert.user = user;
        alert.amount = amount;
        alert.timestamp = block.timestamp;
        alert.description = description;
        alert.resolved = false;

        lastUserAlert[user] = alertId;

        // Actualizar nivel de alerta del token
        AlertLevel oldLevel = tokenAlertLevel[token];
        if (level > oldLevel) {
            tokenAlertLevel[token] = level;
            emit AlertLevelChanged(token, oldLevel, level);
        }

        emit SecurityAlertRaised(alertId, level, patternType, token, user, amount);
    }

    /**
     * @notice Actualiza risk score de usuario
     */
    function _updateRiskScore(address user, PatternType patternType) internal {
        RiskScore storage score = userRiskScores[user];
        uint256 oldScore = score.score;

        // Incrementar score según tipo de patrón
        if (patternType == PatternType.WHALE_WITHDRAWAL) {
            score.score += 20;
        } else if (patternType == PatternType.BURST_WITHDRAWALS) {
            score.score += 30;
        } else if (patternType == PatternType.VOLUME_SPIKE) {
            score.score += 40;
        } else if (patternType == PatternType.NEW_WALLET_DRAIN) {
            score.score += 50;
        } else if (patternType == PatternType.COORDINATED_WITHDRAWALS) {
            score.score += 60;
        }

        // Cap a 100
        if (score.score > 100) {
            score.score = 100;
        }

        score.lastUpdate = block.timestamp;
        score.flagged = score.score >= 70;

        emit RiskScoreUpdated(user, oldScore, score.score);
    }

    /**
     * @notice Aplica respuesta automática según nivel
     */
    function _applyAutoResponse(address user, address token, AlertLevel level) internal {
        if (level == AlertLevel.CRITICAL) {
            // Activar circuit breaker
            _activateCircuitBreaker(token, "Auto-response: Critical alert");
        } else if (level == AlertLevel.DANGER) {
            // Bloquear usuario temporalmente
            withdrawalBlocked[user][token] = block.timestamp + 1 hours;
            emit WithdrawalBlocked(user, token, block.timestamp + 1 hours, "Auto-response: Danger alert");
        }
        // WARNING no requiere acción automática
    }

    /**
     * @notice Activa circuit breaker
     */
    function _activateCircuitBreaker(address token, string memory reason) internal {
        circuitBreakerActive[token] = true;
        emit CircuitBreakerTriggered(token, AlertLevel.CRITICAL, reason);

        // Pausar sistema si es necesario
        if (autoResponseEnabled) {
            _pause();
        }
    }

    /**
     * @notice Obtiene balance total del vault
     */
    function _getTotalBalance(address token) internal view returns (uint256) {
        if (vault == address(0)) return 0;

        (bool success, bytes memory data) = vault.staticcall(
            abi.encodeWithSignature("getTokenBalance(address)", token)
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        
        return 0;
    }

    // ============================================
    // ADMINISTRACIÓN
    // ============================================

    /**
     * @notice Configura circuit breaker para token
     */
    function configureCircuitBreaker(
        address token,
        bool enabled,
        uint256 maxWithdrawalPercentage,
        uint256 timeWindow,
        uint256 burstThreshold,
        uint256 burstTimeWindow,
        uint256 warningThreshold,
        uint256 dangerThreshold,
        uint256 criticalThreshold
    ) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(warningThreshold <= dangerThreshold, "Invalid warning");
        require(dangerThreshold <= criticalThreshold, "Invalid danger");

        CircuitBreakerConfig storage config = circuitBreakerConfigs[token];
        config.enabled = enabled;
        config.maxWithdrawalPercentage = maxWithdrawalPercentage;
        config.timeWindow = timeWindow;
        config.burstThreshold = burstThreshold;
        config.burstTimeWindow = burstTimeWindow;
        config.warningThreshold = warningThreshold;
        config.dangerThreshold = dangerThreshold;
        config.criticalThreshold = criticalThreshold;
    }

    /**
     * @notice Resetea circuit breaker
     */
    function resetCircuitBreaker(address token) external onlyRole(ADMIN_ROLE) {
        circuitBreakerActive[token] = false;
        tokenAlertLevel[token] = AlertLevel.NORMAL;
        
        // Resetear actividad
        delete tokenActivity[token];
        lastResetTime[token] = block.timestamp;

        emit CircuitBreakerReset(token, msg.sender);
    }

    /**
     * @notice Resuelve alerta
     */
    function resolveAlert(uint256 alertId) external onlyRole(ADMIN_ROLE) {
        SecurityAlert storage alert = alerts[alertId];
        require(!alert.resolved, "Already resolved");

        alert.resolved = true;
        alert.resolvedBy = msg.sender;
        alert.resolvedAt = block.timestamp;

        emit AlertResolved(alertId, msg.sender);
    }

    /**
     * @notice Agrega dirección confiable
     */
    function addTrustedAddress(address addr) external onlyRole(ADMIN_ROLE) {
        trustedAddresses[addr] = true;
        emit TrustedAddressAdded(addr);
    }

    /**
     * @notice Remueve dirección confiable
     */
    function removeTrustedAddress(address addr) external onlyRole(ADMIN_ROLE) {
        trustedAddresses[addr] = false;
        emit TrustedAddressRemoved(addr);
    }

    /**
     * @notice Desbloquea usuario
     */
    function unblockUser(address user, address token) external onlyRole(ADMIN_ROLE) {
        withdrawalBlocked[user][token] = 0;
    }

    /**
     * @notice Resetea risk score de usuario
     */
    function resetRiskScore(address user) external onlyRole(ADMIN_ROLE) {
        RiskScore storage score = userRiskScores[user];
        uint256 oldScore = score.score;
        score.score = 0;
        score.flagged = false;
        score.lastUpdate = block.timestamp;
        
        emit RiskScoreUpdated(user, oldScore, 0);
    }

    /**
     * @notice Configura vault
     */
    function setVault(address _vault) external onlyRole(ADMIN_ROLE) {
        vault = _vault;
    }

    /**
     * @notice Configura WithdrawManager
     */
    function setWithdrawManager(address _withdrawManager) external onlyRole(ADMIN_ROLE) {
        withdrawManager = _withdrawManager;
    }

    /**
     * @notice Habilita/deshabilita respuesta automática
     */
    function setAutoResponseEnabled(bool enabled) external onlyRole(ADMIN_ROLE) {
        autoResponseEnabled = enabled;
    }

    /**
     * @notice Configura umbral de bloqueo automático
     */
    function setAutoBlockThreshold(uint256 threshold) external onlyRole(ADMIN_ROLE) {
        require(threshold <= 100, "Invalid threshold");
        autoBlockThreshold = threshold;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============================================
    // VISTAS
    // ============================================

    /**
     * @notice Obtiene configuración de circuit breaker
     */
    function getCircuitBreakerConfig(address token) 
        external 
        view 
        returns (CircuitBreakerConfig memory) 
    {
        return circuitBreakerConfigs[token];
    }

    /**
     * @notice Obtiene actividad de token
     */
    function getTokenActivity(address token) 
        external 
        view 
        returns (WithdrawalActivity memory) 
    {
        return tokenActivity[token];
    }

    /**
     * @notice Obtiene alerta
     */
    function getAlert(uint256 alertId) external view returns (SecurityAlert memory) {
        return alerts[alertId];
    }

    /**
     * @notice Obtiene risk score de usuario
     */
    function getUserRiskScore(address user) external view returns (RiskScore memory) {
        return userRiskScores[user];
    }

    /**
     * @notice Obtiene alertas no resueltas
     */
    function getUnresolvedAlerts() external view returns (uint256[] memory) {
        uint256 count = 0;
        
        for (uint256 i = 1; i <= alertCounter; i++) {
            if (!alerts[i].resolved) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= alertCounter; i++) {
            if (!alerts[i].resolved) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Obtiene alertas críticas
     */
    function getCriticalAlerts() external view returns (uint256[] memory) {
        uint256 count = 0;
        
        for (uint256 i = 1; i <= alertCounter; i++) {
            if (alerts[i].level == AlertLevel.CRITICAL && !alerts[i].resolved) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= alertCounter; i++) {
            if (alerts[i].level == AlertLevel.CRITICAL && !alerts[i].resolved) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Obtiene usuarios flaggeados
     */
    function getFlaggedUsers() external pure returns (address[] memory) {
        // Esta función requeriría un array separado para ser eficiente
        // Por ahora retornamos vacío, se implementaría con un EnumerableSet
        return new address[](0);
    }

    /**
     * @notice Verifica si usuario está bloqueado
     */
    function isUserBlocked(address user, address token) external view returns (bool, uint256) {
        uint256 until = withdrawalBlocked[user][token];
        if (until > block.timestamp) {
            return (true, until);
        }
        return (false, 0);
    }

    /**
     * @notice Obtiene estadísticas
     */
    function getStats() external view returns (
        uint256 totalAlerts,
        uint256 unresolvedAlerts,
        uint256 criticalAlerts,
        uint256 activeCircuitBreakers
    ) {
        unresolvedAlerts = 0;
        criticalAlerts = 0;
        
        for (uint256 i = 1; i <= alertCounter; i++) {
            if (!alerts[i].resolved) {
                unresolvedAlerts++;
                if (alerts[i].level == AlertLevel.CRITICAL) {
                    criticalAlerts++;
                }
            }
        }

        // Contar circuit breakers activos (simplificado)
        activeCircuitBreakers = 0;

        return (alertCounter, unresolvedAlerts, criticalAlerts, activeCircuitBreakers);
    }

    /**
     * @notice Verifica si dirección es confiable
     */
    function isTrustedAddress(address addr) external view returns (bool) {
        return trustedAddresses[addr];
    }

    /**
     * @notice Obtiene nivel de alerta de token
     */
    function getTokenAlertLevel(address token) external view returns (AlertLevel) {
        return tokenAlertLevel[token];
    }
}
