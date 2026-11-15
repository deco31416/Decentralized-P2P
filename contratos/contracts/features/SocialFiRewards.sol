// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SocialFiRewards
 * @notice Sistema de recompensas por actividad social en la plataforma
 * @dev Incentiva engagement social con rewards en CAMBIO tokens
 * 
 * CARACTERÍSTICAS:
 * - Rewards por múltiples tipos de actividad social:
 *   * Crear post/contenido
 *   * Likes/reacciones
 *   * Comentarios
 *   * Shares/compartir
 *   * Seguir usuarios
 *   * Interacciones de calidad
 * 
 * - Sistema de niveles y multiplicadores
 * - Daily/weekly limits para prevenir abuse
 * - Cooldowns entre acciones
 * - Verificación de calidad de contenido
 * - Penalización por spam/abuse
 * 
 * NIVELES DE USUARIO:
 * - Novice: 1x multiplier (0-100 engagement)
 * - Active: 1.2x multiplier (100-500 engagement)
 * - Veteran: 1.5x multiplier (500-2000 engagement)
 * - Expert: 2x multiplier (2000-5000 engagement)
 * - Legend: 3x multiplier (5000+ engagement)
 * 
 * REWARDS BASE:
 * - Post: 10 CAMBIO
 * - Like: 0.1 CAMBIO
 * - Comment: 2 CAMBIO
 * - Share: 5 CAMBIO
 * - Follow: 1 CAMBIO
 * - Quality interaction: 20 CAMBIO (curado)
 * 
 * EJEMPLO:
 * - Usuario Expert (2x) crea post: 10 * 2 = 20 CAMBIO
 * - Usuario Veteran (1.5x) comenta: 2 * 1.5 = 3 CAMBIO
 * - Usuario Active (1.2x) comparte: 5 * 1.2 = 6 CAMBIO
 */
contract SocialFiRewards is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========================================
    // ROLES
    // ========================================
    
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    // ========================================
    // ESTRUCTURAS
    // ========================================

    /**
     * @dev Tipos de actividad social
     */
    enum ActivityType {
        POST_CREATED,           // Crear post
        LIKE_GIVEN,             // Dar like
        COMMENT_MADE,           // Hacer comentario
        CONTENT_SHARED,         // Compartir contenido
        USER_FOLLOWED,          // Seguir usuario
        QUALITY_INTERACTION,    // Interacción de calidad (curada)
        POLL_VOTED,             // Votar en encuesta
        CONTENT_CURATED         // Contenido curado
    }

    /**
     * @dev Nivel de usuario
     */
    enum UserLevel {
        NOVICE,     // Novato (0-100)
        ACTIVE,     // Activo (100-500)
        VETERAN,    // Veterano (500-2000)
        EXPERT,     // Experto (2000-5000)
        LEGEND      // Leyenda (5000+)
    }

    /**
     * @dev Perfil social de usuario
     */
    struct SocialProfile {
        address user;                       // Usuario
        uint256 totalEngagement;            // Engagement total
        uint256 postsCreated;               // Posts creados
        uint256 likesGiven;                 // Likes dados
        uint256 commentsMade;               // Comentarios hechos
        uint256 contentShared;              // Contenido compartido
        uint256 usersFollowed;              // Usuarios seguidos
        uint256 qualityInteractions;        // Interacciones de calidad
        uint256 totalRewardsEarned;         // Total rewards ganados
        uint256 dailyRewardsEarned;         // Rewards del día
        uint256 weeklyRewardsEarned;        // Rewards de la semana
        uint256 lastActivityTime;           // Última actividad
        uint256 lastDailyReset;             // Último reset diario
        uint256 lastWeeklyReset;            // Último reset semanal
        UserLevel level;                    // Nivel del usuario
        bool isBanned;                      // Baneado por spam
        uint256 bannedUntil;                // Ban hasta timestamp
    }

    /**
     * @dev Configuración de rewards por actividad
     */
    struct RewardConfig {
        uint256 baseReward;                 // Reward base
        uint256 dailyLimit;                 // Límite diario
        uint256 cooldown;                   // Cooldown entre acciones (segundos)
        bool requiresModeration;            // Requiere moderación
        bool enabled;                       // Actividad habilitada
    }

    /**
     * @dev Multiplicadores por nivel
     */
    struct LevelConfig {
        uint256 multiplier;                 // Multiplicador (basis points)
        uint256 minEngagement;              // Engagement mínimo
    }

    /**
     * @dev Actividad registrada
     */
    struct Activity {
        uint256 activityId;                 // ID único
        address user;                       // Usuario
        ActivityType activityType;          // Tipo de actividad
        uint256 rewardEarned;               // Reward ganado
        uint256 timestamp;                  // Timestamp
        string contentHash;                 // Hash de contenido (IPFS)
        bool moderated;                     // Moderado
        bool approved;                      // Aprobado
    }

    // ========================================
    // VARIABLES DE ESTADO
    // ========================================

    /// @notice Token de rewards (CAMBIO)
    IERC20 public immutable rewardToken;

    /// @notice Treasury que provee rewards
    address public treasury;

    /// @notice Perfiles sociales de usuarios
    mapping(address => SocialProfile) public socialProfiles;

    /// @notice Configuración de rewards por tipo
    mapping(ActivityType => RewardConfig) public rewardConfigs;

    /// @notice Configuración de niveles
    mapping(UserLevel => LevelConfig) public levelConfigs;

    /// @notice Último tiempo de actividad por tipo
    mapping(address => mapping(ActivityType => uint256)) public lastActivityTime;

    /// @notice Contador de actividades diarias por tipo
    mapping(address => mapping(ActivityType => uint256)) public dailyActivityCount;

    /// @notice Actividades registradas
    mapping(uint256 => Activity) public activities;
    uint256 public activityCounter;

    /// @notice Actividades por usuario
    mapping(address => uint256[]) public userActivities;

    /// @notice Actividades pendientes de moderación
    uint256[] public pendingModerationQueue;

    /// @notice Total de rewards distribuidos
    uint256 public totalRewardsDistributed;

    /// @notice Límite diario global por usuario
    uint256 public globalDailyLimit = 1000e18; // 1000 CAMBIO

    /// @notice Límite semanal global por usuario
    uint256 public globalWeeklyLimit = 5000e18; // 5000 CAMBIO

    // ========================================
    // EVENTOS
    // ========================================

    event ActivityRecorded(
        uint256 indexed activityId,
        address indexed user,
        ActivityType indexed activityType,
        uint256 rewardEarned,
        uint256 timestamp
    );

    event RewardClaimed(
        address indexed user,
        uint256 amount
    );

    event UserLevelUp(
        address indexed user,
        UserLevel indexed newLevel,
        uint256 timestamp
    );

    event UserBanned(
        address indexed user,
        uint256 bannedUntil,
        string reason
    );

    event UserUnbanned(
        address indexed user,
        uint256 timestamp
    );

    event ActivityModerated(
        uint256 indexed activityId,
        bool approved,
        address indexed moderator
    );

    event RewardConfigUpdated(
        ActivityType indexed activityType,
        uint256 baseReward,
        uint256 dailyLimit
    );

    // ========================================
    // ERRORES
    // ========================================

    error InvalidAddress();
    error InvalidAmount();
    error UserIsBanned();
    error ActivityDisabled();
    error DailyLimitReached();
    error WeeklyLimitReached();
    error CooldownActive();
    error ActivityNotFound();
    error AlreadyModerated();

    // ========================================
    // CONSTRUCTOR
    // ========================================

    /**
     * @notice Constructor del contrato
     * @param _rewardToken Token CAMBIO
     * @param _treasury Treasury que provee rewards
     * @param admin Admin principal
     */
    constructor(
        address _rewardToken,
        address _treasury,
        address admin
    ) {
        if (_rewardToken == address(0) || _treasury == address(0) || admin == address(0)) {
            revert InvalidAddress();
        }

        rewardToken = IERC20(_rewardToken);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MODERATOR_ROLE, admin);
        _grantRole(CURATOR_ROLE, admin);

        _setupRewardConfigs();
        _setupLevelConfigs();
    }

    /**
     * @dev Configura rewards por defecto
     */
    function _setupRewardConfigs() internal {
        // POST_CREATED: 10 CAMBIO, 10 daily, 1 hour cooldown
        rewardConfigs[ActivityType.POST_CREATED] = RewardConfig({
            baseReward: 10e18,
            dailyLimit: 10,
            cooldown: 1 hours,
            requiresModeration: false,
            enabled: true
        });

        // LIKE_GIVEN: 0.1 CAMBIO, 100 daily, 1 min cooldown
        rewardConfigs[ActivityType.LIKE_GIVEN] = RewardConfig({
            baseReward: 0.1e18,
            dailyLimit: 100,
            cooldown: 1 minutes,
            requiresModeration: false,
            enabled: true
        });

        // COMMENT_MADE: 2 CAMBIO, 50 daily, 5 min cooldown
        rewardConfigs[ActivityType.COMMENT_MADE] = RewardConfig({
            baseReward: 2e18,
            dailyLimit: 50,
            cooldown: 5 minutes,
            requiresModeration: false,
            enabled: true
        });

        // CONTENT_SHARED: 5 CAMBIO, 20 daily, 10 min cooldown
        rewardConfigs[ActivityType.CONTENT_SHARED] = RewardConfig({
            baseReward: 5e18,
            dailyLimit: 20,
            cooldown: 10 minutes,
            requiresModeration: false,
            enabled: true
        });

        // USER_FOLLOWED: 1 CAMBIO, 50 daily, 2 min cooldown
        rewardConfigs[ActivityType.USER_FOLLOWED] = RewardConfig({
            baseReward: 1e18,
            dailyLimit: 50,
            cooldown: 2 minutes,
            requiresModeration: false,
            enabled: true
        });

        // QUALITY_INTERACTION: 20 CAMBIO, 10 daily, moderado
        rewardConfigs[ActivityType.QUALITY_INTERACTION] = RewardConfig({
            baseReward: 20e18,
            dailyLimit: 10,
            cooldown: 30 minutes,
            requiresModeration: true,
            enabled: true
        });
    }

    /**
     * @dev Configura niveles y multiplicadores
     */
    function _setupLevelConfigs() internal {
        levelConfigs[UserLevel.NOVICE] = LevelConfig({
            multiplier: 10000,      // 1.0x
            minEngagement: 0
        });

        levelConfigs[UserLevel.ACTIVE] = LevelConfig({
            multiplier: 12000,      // 1.2x
            minEngagement: 100
        });

        levelConfigs[UserLevel.VETERAN] = LevelConfig({
            multiplier: 15000,      // 1.5x
            minEngagement: 500
        });

        levelConfigs[UserLevel.EXPERT] = LevelConfig({
            multiplier: 20000,      // 2.0x
            minEngagement: 2000
        });

        levelConfigs[UserLevel.LEGEND] = LevelConfig({
            multiplier: 30000,      // 3.0x
            minEngagement: 5000
        });
    }

    // ========================================
    // FUNCIONES PRINCIPALES
    // ========================================

    /**
     * @notice Registra actividad social y otorga reward
     * @param activityType Tipo de actividad
     * @param contentHash Hash del contenido (IPFS)
     */
    function recordActivity(ActivityType activityType, string calldata contentHash)
        external
        nonReentrant
        whenNotPaused
    {
        _ensureProfileExists(msg.sender);
        _checkAndResetPeriods(msg.sender);

        SocialProfile storage profile = socialProfiles[msg.sender];

        // Validaciones
        if (profile.isBanned && block.timestamp < profile.bannedUntil) {
            revert UserIsBanned();
        }

        RewardConfig storage config = rewardConfigs[activityType];
        if (!config.enabled) revert ActivityDisabled();

        // Verificar cooldown
        if (block.timestamp < lastActivityTime[msg.sender][activityType] + config.cooldown) {
            revert CooldownActive();
        }

        // Verificar límite diario de actividad
        if (dailyActivityCount[msg.sender][activityType] >= config.dailyLimit) {
            revert DailyLimitReached();
        }

        // Calcular reward con multiplicador de nivel
        uint256 multiplier = levelConfigs[profile.level].multiplier;
        uint256 reward = (config.baseReward * multiplier) / 10000;

        // Verificar límites globales
        if (profile.dailyRewardsEarned + reward > globalDailyLimit) {
            revert DailyLimitReached();
        }
        if (profile.weeklyRewardsEarned + reward > globalWeeklyLimit) {
            revert WeeklyLimitReached();
        }

        // Registrar actividad
        uint256 activityId = ++activityCounter;
        activities[activityId] = Activity({
            activityId: activityId,
            user: msg.sender,
            activityType: activityType,
            rewardEarned: reward,
            timestamp: block.timestamp,
            contentHash: contentHash,
            moderated: false,
            approved: !config.requiresModeration
        });

        userActivities[msg.sender].push(activityId);

        if (config.requiresModeration) {
            pendingModerationQueue.push(activityId);
        }

        // Actualizar perfil
        profile.totalEngagement += 1;
        profile.totalRewardsEarned += reward;
        profile.dailyRewardsEarned += reward;
        profile.weeklyRewardsEarned += reward;
        profile.lastActivityTime = block.timestamp;

        // Actualizar contador específico
        _updateActivityCounter(activityType, profile);

        // Actualizar tracking
        lastActivityTime[msg.sender][activityType] = block.timestamp;
        dailyActivityCount[msg.sender][activityType]++;

        // Verificar level up
        _checkLevelUp(msg.sender);

        // Transferir reward si no requiere moderación
        if (!config.requiresModeration) {
            totalRewardsDistributed += reward;
            rewardToken.safeTransferFrom(treasury, msg.sender, reward);
        }

        emit ActivityRecorded(activityId, msg.sender, activityType, reward, block.timestamp);
    }

    /**
     * @dev Actualiza contador de actividad específica
     */
    function _updateActivityCounter(ActivityType activityType, SocialProfile storage profile) internal {
        if (activityType == ActivityType.POST_CREATED) {
            profile.postsCreated++;
        } else if (activityType == ActivityType.LIKE_GIVEN) {
            profile.likesGiven++;
        } else if (activityType == ActivityType.COMMENT_MADE) {
            profile.commentsMade++;
        } else if (activityType == ActivityType.CONTENT_SHARED) {
            profile.contentShared++;
        } else if (activityType == ActivityType.USER_FOLLOWED) {
            profile.usersFollowed++;
        } else if (activityType == ActivityType.QUALITY_INTERACTION) {
            profile.qualityInteractions++;
        }
    }

    /**
     * @dev Asegura que el perfil del usuario existe
     */
    function _ensureProfileExists(address user) internal {
        if (socialProfiles[user].user == address(0)) {
            socialProfiles[user].user = user;
            socialProfiles[user].level = UserLevel.NOVICE;
            socialProfiles[user].lastDailyReset = block.timestamp;
            socialProfiles[user].lastWeeklyReset = block.timestamp;
        }
    }

    /**
     * @dev Verifica y resetea períodos si es necesario
     */
    function _checkAndResetPeriods(address user) internal {
        SocialProfile storage profile = socialProfiles[user];

        // Reset diario
        if (block.timestamp >= profile.lastDailyReset + 1 days) {
            profile.dailyRewardsEarned = 0;
            profile.lastDailyReset = block.timestamp;
            
            // Resetear contadores diarios
            for (uint256 i = 0; i < 8; i++) {
                dailyActivityCount[user][ActivityType(i)] = 0;
            }
        }

        // Reset semanal
        if (block.timestamp >= profile.lastWeeklyReset + 7 days) {
            profile.weeklyRewardsEarned = 0;
            profile.lastWeeklyReset = block.timestamp;
        }
    }

    /**
     * @dev Verifica si usuario subió de nivel
     */
    function _checkLevelUp(address user) internal {
        SocialProfile storage profile = socialProfiles[user];
        UserLevel currentLevel = profile.level;
        UserLevel newLevel = _calculateLevel(profile.totalEngagement);

        if (newLevel != currentLevel) {
            profile.level = newLevel;
            emit UserLevelUp(user, newLevel, block.timestamp);
        }
    }

    /**
     * @dev Calcula nivel según engagement
     */
    function _calculateLevel(uint256 engagement) internal pure returns (UserLevel) {
        if (engagement >= 5000) return UserLevel.LEGEND;
        if (engagement >= 2000) return UserLevel.EXPERT;
        if (engagement >= 500) return UserLevel.VETERAN;
        if (engagement >= 100) return UserLevel.ACTIVE;
        return UserLevel.NOVICE;
    }

    // ========================================
    // FUNCIONES DE MODERACIÓN
    // ========================================

    /**
     * @notice Modera una actividad pendiente
     * @param activityId ID de la actividad
     * @param approved Si se aprueba o no
     */
    function moderateActivity(uint256 activityId, bool approved)
        external
        onlyRole(MODERATOR_ROLE)
        nonReentrant
    {
        Activity storage activity = activities[activityId];
        
        if (activity.activityId == 0) revert ActivityNotFound();
        if (activity.moderated) revert AlreadyModerated();

        activity.moderated = true;
        activity.approved = approved;

        // Si se aprueba, transferir reward
        if (approved) {
            totalRewardsDistributed += activity.rewardEarned;
            rewardToken.safeTransferFrom(treasury, activity.user, activity.rewardEarned);
        } else {
            // Si se rechaza, restar de perfil
            SocialProfile storage profile = socialProfiles[activity.user];
            profile.totalRewardsEarned -= activity.rewardEarned;
            profile.dailyRewardsEarned -= activity.rewardEarned;
            profile.weeklyRewardsEarned -= activity.rewardEarned;
        }

        emit ActivityModerated(activityId, approved, msg.sender);
    }

    /**
     * @notice Banea un usuario por spam
     * @param user Usuario a banear
     * @param duration Duración del ban en segundos
     * @param reason Razón del ban
     */
    function banUser(address user, uint256 duration, string calldata reason)
        external
        onlyRole(MODERATOR_ROLE)
    {
        SocialProfile storage profile = socialProfiles[user];
        profile.isBanned = true;
        profile.bannedUntil = block.timestamp + duration;

        emit UserBanned(user, profile.bannedUntil, reason);
    }

    /**
     * @notice Desbanea un usuario
     * @param user Usuario a desbanear
     */
    function unbanUser(address user)
        external
        onlyRole(MODERATOR_ROLE)
    {
        SocialProfile storage profile = socialProfiles[user];
        profile.isBanned = false;
        profile.bannedUntil = 0;

        emit UserUnbanned(user, block.timestamp);
    }

    // ========================================
    // FUNCIONES DE CONSULTA
    // ========================================

    /**
     * @notice Obtiene perfil social de usuario
     */
    function getUserProfile(address user)
        external
        view
        returns (
            uint256 totalEngagement,
            UserLevel level,
            uint256 totalRewardsEarned,
            uint256 dailyRewardsEarned,
            uint256 weeklyRewardsEarned,
            bool isBanned
        )
    {
        SocialProfile storage profile = socialProfiles[user];
        return (
            profile.totalEngagement,
            profile.level,
            profile.totalRewardsEarned,
            profile.dailyRewardsEarned,
            profile.weeklyRewardsEarned,
            profile.isBanned && block.timestamp < profile.bannedUntil
        );
    }

    /**
     * @notice Obtiene estadísticas detalladas de usuario
     */
    function getUserStats(address user)
        external
        view
        returns (
            uint256 postsCreated,
            uint256 likesGiven,
            uint256 commentsMade,
            uint256 contentShared,
            uint256 usersFollowed,
            uint256 qualityInteractions
        )
    {
        SocialProfile storage profile = socialProfiles[user];
        return (
            profile.postsCreated,
            profile.likesGiven,
            profile.commentsMade,
            profile.contentShared,
            profile.usersFollowed,
            profile.qualityInteractions
        );
    }

    /**
     * @notice Obtiene actividades pendientes de moderación
     */
    function getPendingModerationQueue(uint256 limit)
        external
        view
        returns (Activity[] memory)
    {
        uint256 count = limit < pendingModerationQueue.length ? limit : pendingModerationQueue.length;
        Activity[] memory pending = new Activity[](count);

        for (uint256 i = 0; i < count; i++) {
            pending[i] = activities[pendingModerationQueue[i]];
        }

        return pending;
    }

    /**
     * @notice Obtiene multiplicador actual de usuario
     */
    function getUserMultiplier(address user)
        external
        view
        returns (uint256)
    {
        return levelConfigs[socialProfiles[user].level].multiplier;
    }

    // ========================================
    // FUNCIONES ADMIN
    // ========================================

    /**
     * @notice Actualiza configuración de reward
     */
    function updateRewardConfig(
        ActivityType activityType,
        uint256 baseReward,
        uint256 dailyLimit,
        uint256 cooldown,
        bool requiresModeration,
        bool enabled
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rewardConfigs[activityType] = RewardConfig({
            baseReward: baseReward,
            dailyLimit: dailyLimit,
            cooldown: cooldown,
            requiresModeration: requiresModeration,
            enabled: enabled
        });

        emit RewardConfigUpdated(activityType, baseReward, dailyLimit);
    }

    /**
     * @notice Actualiza límites globales
     */
    function updateGlobalLimits(uint256 dailyLimit, uint256 weeklyLimit)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        globalDailyLimit = dailyLimit;
        globalWeeklyLimit = weeklyLimit;
    }

    /**
     * @notice Actualiza treasury
     */
    function setTreasury(address newTreasury)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newTreasury == address(0)) revert InvalidAddress();
        treasury = newTreasury;
    }

    /**
     * @notice Pausa el contrato
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Despausa el contrato
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
