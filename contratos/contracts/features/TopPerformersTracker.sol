// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title TopPerformersTracker
 * @notice Sistema de tracking de rendimiento de usuarios para rankings y rewards
 * @dev Rastrea métricas de performance en tiempo real para identificar top performers
 * 
 * CARACTERÍSTICAS:
 * - Tracking de 3 categorías principales:
 *   1. Referral Performance (volumen generado por referidos)
 *   2. Trading Performance (volumen personal de trading)
 *   3. Fee Generation (fees totales generados)
 * 
 * - Períodos de tracking:
 *   * All-time (histórico total)
 *   * Weekly (última semana)
 *   * Monthly (último mes)
 *   * Daily (último día)
 * 
 * - Rankings dinámicos con top 10 en cada categoría
 * - Snapshots semanales para distribución de rewards
 * - Integración con RewardDistributor para lotería semanal
 * 
 * FLUJO DE TRACKING:
 * 1. Contratos autorizados registran actividad (TRACKER_ROLE)
 * 2. Sistema actualiza métricas en tiempo real
 * 3. Rankings se recalculan automáticamente
 * 4. Al final de semana, snapshot para rewards
 * 5. RewardDistributor consulta top performers
 * 
 * EJEMPLO DE ACTIVIDADES:
 * - Usuario hace trade de $1,000 → +$1,000 trading volume
 * - Usuario genera fee de $3 → +$3 fee generation
 * - Referido del usuario tradea $500 → +$500 referral volume
 * - Usuario stakea tokens → +1 engagement activity
 */
contract TopPerformersTracker is AccessControl, ReentrancyGuard, Pausable {
    
    // ========================================
    // ROLES
    // ========================================
    
    bytes32 public constant TRACKER_ROLE = keccak256("TRACKER_ROLE");
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

    // ========================================
    // ESTRUCTURAS
    // ========================================

    /**
     * @dev Categorías de performance
     */
    enum PerformanceCategory {
        REFERRAL_VOLUME,    // Volumen de referidos
        TRADING_VOLUME,     // Volumen de trading personal
        FEE_GENERATION,     // Fees generados
        ENGAGEMENT          // Actividad general
    }

    /**
     * @dev Período de tracking
     */
    enum TrackingPeriod {
        ALL_TIME,   // Todo el tiempo
        WEEKLY,     // Última semana
        MONTHLY,    // Último mes
        DAILY       // Último día
    }

    /**
     * @dev Métricas de performance de un usuario
     */
    struct UserPerformance {
        address user;                       // Usuario
        uint256 referralVolumeAllTime;      // Volumen referidos (histórico)
        uint256 referralVolumeWeekly;       // Volumen referidos (semana)
        uint256 referralVolumeMonthly;      // Volumen referidos (mes)
        uint256 referralVolumeDaily;        // Volumen referidos (día)
        uint256 tradingVolumeAllTime;       // Volumen trading (histórico)
        uint256 tradingVolumeWeekly;        // Volumen trading (semana)
        uint256 tradingVolumeMonthly;       // Volumen trading (mes)
        uint256 tradingVolumeDaily;         // Volumen trading (día)
        uint256 feesGeneratedAllTime;       // Fees generados (histórico)
        uint256 feesGeneratedWeekly;        // Fees generados (semana)
        uint256 feesGeneratedMonthly;       // Fees generados (mes)
        uint256 feesGeneratedDaily;         // Fees generados (día)
        uint256 engagementScore;            // Score de engagement
        uint256 lastActivityTimestamp;      // Última actividad
        uint256 totalActivities;            // Total de actividades
        bool isActive;                      // Usuario activo
    }

    /**
     * @dev Snapshot semanal de top performers
     */
    struct WeeklySnapshot {
        uint256 weekNumber;                             // Número de semana
        uint256 timestamp;                              // Timestamp del snapshot
        mapping(PerformanceCategory => address[10]) topPerformers;  // Top 10 por categoría
        mapping(PerformanceCategory => uint256[10]) topValues;      // Valores top 10
        uint256 totalActiveUsers;                       // Total usuarios activos
        uint256 totalReferralVolume;                    // Volumen total de referidos
        uint256 totalTradingVolume;                     // Volumen total de trading
        uint256 totalFeesGenerated;                     // Fees totales generados
    }

    /**
     * @dev Actividad registrada
     */
    struct Activity {
        uint256 activityId;                 // ID único
        address user;                       // Usuario
        PerformanceCategory category;       // Categoría
        uint256 value;                      // Valor de la actividad
        uint256 timestamp;                  // Timestamp
        string description;                 // Descripción opcional
    }

    // ========================================
    // VARIABLES DE ESTADO
    // ========================================

    /// @notice Performance por usuario
    mapping(address => UserPerformance) public userPerformance;

    /// @notice Lista de usuarios activos
    address[] public activeUsers;
    mapping(address => bool) public isActiveUser;

    /// @notice Snapshots semanales
    mapping(uint256 => WeeklySnapshot) private weeklySnapshots;

    /// @notice Semana actual
    uint256 public currentWeek;

    /// @notice Rankings actuales por categoría
    mapping(PerformanceCategory => address[]) public rankings;

    /// @notice Actividades registradas
    mapping(uint256 => Activity) public activities;
    uint256 public activityCounter;

    /// @notice Actividades por usuario
    mapping(address => uint256[]) public userActivities;

    /// @notice Total de métricas globales
    uint256 public totalReferralVolumeAllTime;
    uint256 public totalTradingVolumeAllTime;
    uint256 public totalFeesGeneratedAllTime;
    uint256 public totalUsersTracked;

    /// @notice Timestamps de períodos
    uint256 public lastWeeklyReset;
    uint256 public lastMonthlyReset;
    uint256 public lastDailyReset;

    /// @notice Threshold para considerarse activo
    uint256 public activityThreshold = 10e18; // 10 CAMBIO en fees

    // ========================================
    // EVENTOS
    // ========================================

    event ActivityRecorded(
        uint256 indexed activityId,
        address indexed user,
        PerformanceCategory indexed category,
        uint256 value,
        uint256 timestamp
    );

    event PerformanceUpdated(
        address indexed user,
        PerformanceCategory indexed category,
        uint256 newValue,
        TrackingPeriod period
    );

    event WeeklySnapshotCreated(
        uint256 indexed weekNumber,
        uint256 timestamp,
        uint256 totalActiveUsers
    );

    event RankingsUpdated(
        PerformanceCategory indexed category,
        uint256 timestamp
    );

    event UserActivated(
        address indexed user,
        uint256 timestamp
    );

    event UserDeactivated(
        address indexed user,
        uint256 timestamp
    );

    event PeriodReset(
        TrackingPeriod indexed period,
        uint256 timestamp
    );

    // ========================================
    // ERRORES
    // ========================================

    error InvalidAddress();
    error InvalidValue();
    error InvalidCategory();
    error UserNotActive();
    error SnapshotNotFound();

    // ========================================
    // CONSTRUCTOR
    // ========================================

    /**
     * @notice Constructor del contrato
     * @param admin Admin principal
     */
    constructor(address admin) {
        if (admin == address(0)) revert InvalidAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TRACKER_ROLE, admin);
        _grantRole(SNAPSHOT_ROLE, admin);

        currentWeek = _getCurrentWeekNumber();
        lastWeeklyReset = block.timestamp;
        lastMonthlyReset = block.timestamp;
        lastDailyReset = block.timestamp;
    }

    // ========================================
    // FUNCIONES PRINCIPALES - TRACKING
    // ========================================

    /**
     * @notice Registra actividad de referidos
     * @param user Usuario que generó la actividad
     * @param volume Volumen generado por referidos
     */
    function recordReferralActivity(address user, uint256 volume)
        external
        onlyRole(TRACKER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert InvalidAddress();
        if (volume == 0) revert InvalidValue();

        _checkAndResetPeriods();
        _ensureUserExists(user);

        UserPerformance storage perf = userPerformance[user];
        
        // Actualizar métricas
        perf.referralVolumeAllTime += volume;
        perf.referralVolumeWeekly += volume;
        perf.referralVolumeMonthly += volume;
        perf.referralVolumeDaily += volume;
        perf.lastActivityTimestamp = block.timestamp;
        perf.totalActivities++;

        // Actualizar globales
        totalReferralVolumeAllTime += volume;

        // Registrar actividad
        uint256 activityId = _recordActivity(user, PerformanceCategory.REFERRAL_VOLUME, volume, "");

        // Actualizar rankings
        _updateRankings(PerformanceCategory.REFERRAL_VOLUME);

        emit PerformanceUpdated(user, PerformanceCategory.REFERRAL_VOLUME, perf.referralVolumeWeekly, TrackingPeriod.WEEKLY);
        emit ActivityRecorded(activityId, user, PerformanceCategory.REFERRAL_VOLUME, volume, block.timestamp);
    }

    /**
     * @notice Registra actividad de trading
     * @param user Usuario que hizo el trade
     * @param volume Volumen del trade
     */
    function recordTradingActivity(address user, uint256 volume)
        external
        onlyRole(TRACKER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert InvalidAddress();
        if (volume == 0) revert InvalidValue();

        _checkAndResetPeriods();
        _ensureUserExists(user);

        UserPerformance storage perf = userPerformance[user];
        
        // Actualizar métricas
        perf.tradingVolumeAllTime += volume;
        perf.tradingVolumeWeekly += volume;
        perf.tradingVolumeMonthly += volume;
        perf.tradingVolumeDaily += volume;
        perf.lastActivityTimestamp = block.timestamp;
        perf.totalActivities++;

        // Actualizar globales
        totalTradingVolumeAllTime += volume;

        // Registrar actividad
        uint256 activityId = _recordActivity(user, PerformanceCategory.TRADING_VOLUME, volume, "");

        // Actualizar rankings
        _updateRankings(PerformanceCategory.TRADING_VOLUME);

        emit PerformanceUpdated(user, PerformanceCategory.TRADING_VOLUME, perf.tradingVolumeWeekly, TrackingPeriod.WEEKLY);
        emit ActivityRecorded(activityId, user, PerformanceCategory.TRADING_VOLUME, volume, block.timestamp);
    }

    /**
     * @notice Registra fees generados por usuario
     * @param user Usuario que generó los fees
     * @param fees Cantidad de fees generados
     */
    function recordFeeGeneration(address user, uint256 fees)
        external
        onlyRole(TRACKER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert InvalidAddress();
        if (fees == 0) revert InvalidValue();

        _checkAndResetPeriods();
        _ensureUserExists(user);

        UserPerformance storage perf = userPerformance[user];
        
        // Actualizar métricas
        perf.feesGeneratedAllTime += fees;
        perf.feesGeneratedWeekly += fees;
        perf.feesGeneratedMonthly += fees;
        perf.feesGeneratedDaily += fees;
        perf.lastActivityTimestamp = block.timestamp;
        perf.totalActivities++;

        // Verificar si usuario alcanzó threshold de actividad
        if (!perf.isActive && perf.feesGeneratedAllTime >= activityThreshold) {
            perf.isActive = true;
            emit UserActivated(user, block.timestamp);
        }

        // Actualizar globales
        totalFeesGeneratedAllTime += fees;

        // Registrar actividad
        uint256 activityId = _recordActivity(user, PerformanceCategory.FEE_GENERATION, fees, "");

        // Actualizar rankings
        _updateRankings(PerformanceCategory.FEE_GENERATION);

        emit PerformanceUpdated(user, PerformanceCategory.FEE_GENERATION, perf.feesGeneratedWeekly, TrackingPeriod.WEEKLY);
        emit ActivityRecorded(activityId, user, PerformanceCategory.FEE_GENERATION, fees, block.timestamp);
    }

    /**
     * @notice Registra actividad de engagement general
     * @param user Usuario con actividad
     * @param points Puntos de engagement
     * @param description Descripción de la actividad
     */
    function recordEngagement(address user, uint256 points, string calldata description)
        external
        onlyRole(TRACKER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert InvalidAddress();
        if (points == 0) revert InvalidValue();

        _ensureUserExists(user);

        UserPerformance storage perf = userPerformance[user];
        perf.engagementScore += points;
        perf.lastActivityTimestamp = block.timestamp;
        perf.totalActivities++;

        // Registrar actividad
        uint256 activityId = _recordActivity(user, PerformanceCategory.ENGAGEMENT, points, description);

        emit PerformanceUpdated(user, PerformanceCategory.ENGAGEMENT, perf.engagementScore, TrackingPeriod.ALL_TIME);
        emit ActivityRecorded(activityId, user, PerformanceCategory.ENGAGEMENT, points, block.timestamp);
    }

    // ========================================
    // FUNCIONES INTERNAS
    // ========================================

    /**
     * @dev Asegura que el usuario existe en el sistema
     */
    function _ensureUserExists(address user) internal {
        if (userPerformance[user].user == address(0)) {
            userPerformance[user].user = user;
            userPerformance[user].isActive = false;
            
            if (!isActiveUser[user]) {
                activeUsers.push(user);
                isActiveUser[user] = true;
                totalUsersTracked++;
            }
        }
    }

    /**
     * @dev Registra una actividad
     */
    function _recordActivity(
        address user,
        PerformanceCategory category,
        uint256 value,
        string memory description
    )
        internal
        returns (uint256)
    {
        uint256 activityId = ++activityCounter;
        
        activities[activityId] = Activity({
            activityId: activityId,
            user: user,
            category: category,
            value: value,
            timestamp: block.timestamp,
            description: description
        });

        userActivities[user].push(activityId);

        return activityId;
    }

    /**
     * @dev Verifica y resetea períodos si es necesario
     */
    function _checkAndResetPeriods() internal {
        // Reset diario (cada 24 horas)
        if (block.timestamp >= lastDailyReset + 1 days) {
            _resetDailyMetrics();
            lastDailyReset = block.timestamp;
            emit PeriodReset(TrackingPeriod.DAILY, block.timestamp);
        }

        // Reset semanal (cada 7 días)
        if (block.timestamp >= lastWeeklyReset + 7 days) {
            _createWeeklySnapshot();
            _resetWeeklyMetrics();
            lastWeeklyReset = block.timestamp;
            currentWeek = _getCurrentWeekNumber();
            emit PeriodReset(TrackingPeriod.WEEKLY, block.timestamp);
        }

        // Reset mensual (cada 30 días)
        if (block.timestamp >= lastMonthlyReset + 30 days) {
            _resetMonthlyMetrics();
            lastMonthlyReset = block.timestamp;
            emit PeriodReset(TrackingPeriod.MONTHLY, block.timestamp);
        }
    }

    /**
     * @dev Resetea métricas diarias
     */
    function _resetDailyMetrics() internal {
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            if (isActiveUser[user]) {
                UserPerformance storage perf = userPerformance[user];
                perf.referralVolumeDaily = 0;
                perf.tradingVolumeDaily = 0;
                perf.feesGeneratedDaily = 0;
            }
        }
    }

    /**
     * @dev Resetea métricas semanales
     */
    function _resetWeeklyMetrics() internal {
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            if (isActiveUser[user]) {
                UserPerformance storage perf = userPerformance[user];
                perf.referralVolumeWeekly = 0;
                perf.tradingVolumeWeekly = 0;
                perf.feesGeneratedWeekly = 0;
            }
        }
    }

    /**
     * @dev Resetea métricas mensuales
     */
    function _resetMonthlyMetrics() internal {
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            if (isActiveUser[user]) {
                UserPerformance storage perf = userPerformance[user];
                perf.referralVolumeMonthly = 0;
                perf.tradingVolumeMonthly = 0;
                perf.feesGeneratedMonthly = 0;
            }
        }
    }

    /**
     * @dev Actualiza rankings de una categoría
     */
    function _updateRankings(PerformanceCategory category) internal {
        // Por simplicidad, solo mantenemos top 50 para eficiencia
        // En producción, esto podría optimizarse con estructuras más complejas
        
        address[] memory topUsers = new address[](50);
        uint256[] memory topValues = new uint256[](50);
        uint256 count = 0;

        // Recopilar usuarios con actividad
        for (uint256 i = 0; i < activeUsers.length && count < 50; i++) {
            address user = activeUsers[i];
            if (!isActiveUser[user]) continue;

            uint256 value = _getUserValueByCategory(user, category, TrackingPeriod.WEEKLY);
            if (value == 0) continue;

            // Insertar en orden descendente
            uint256 insertIndex = count;
            for (uint256 j = 0; j < count; j++) {
                if (value > topValues[j]) {
                    insertIndex = j;
                    break;
                }
            }

            // Desplazar elementos
            for (uint256 k = count; k > insertIndex; k--) {
                if (k < 50) {
                    topUsers[k] = topUsers[k - 1];
                    topValues[k] = topValues[k - 1];
                }
            }

            // Insertar nuevo elemento
            topUsers[insertIndex] = user;
            topValues[insertIndex] = value;
            
            if (count < 50) count++;
        }

        // Actualizar ranking
        delete rankings[category];
        for (uint256 i = 0; i < count; i++) {
            rankings[category].push(topUsers[i]);
        }

        emit RankingsUpdated(category, block.timestamp);
    }

    /**
     * @dev Obtiene valor de usuario por categoría y período
     */
    function _getUserValueByCategory(
        address user,
        PerformanceCategory category,
        TrackingPeriod period
    )
        internal
        view
        returns (uint256)
    {
        UserPerformance storage perf = userPerformance[user];

        if (category == PerformanceCategory.REFERRAL_VOLUME) {
            if (period == TrackingPeriod.DAILY) return perf.referralVolumeDaily;
            if (period == TrackingPeriod.WEEKLY) return perf.referralVolumeWeekly;
            if (period == TrackingPeriod.MONTHLY) return perf.referralVolumeMonthly;
            return perf.referralVolumeAllTime;
        } else if (category == PerformanceCategory.TRADING_VOLUME) {
            if (period == TrackingPeriod.DAILY) return perf.tradingVolumeDaily;
            if (period == TrackingPeriod.WEEKLY) return perf.tradingVolumeWeekly;
            if (period == TrackingPeriod.MONTHLY) return perf.tradingVolumeMonthly;
            return perf.tradingVolumeAllTime;
        } else if (category == PerformanceCategory.FEE_GENERATION) {
            if (period == TrackingPeriod.DAILY) return perf.feesGeneratedDaily;
            if (period == TrackingPeriod.WEEKLY) return perf.feesGeneratedWeekly;
            if (period == TrackingPeriod.MONTHLY) return perf.feesGeneratedMonthly;
            return perf.feesGeneratedAllTime;
        } else {
            return perf.engagementScore;
        }
    }

    /**
     * @dev Crea snapshot semanal
     */
    function _createWeeklySnapshot() internal {
        uint256 weekNumber = currentWeek;
        WeeklySnapshot storage snapshot = weeklySnapshots[weekNumber];
        
        snapshot.weekNumber = weekNumber;
        snapshot.timestamp = block.timestamp;
        snapshot.totalActiveUsers = _countActiveUsers();
        snapshot.totalReferralVolume = _sumWeeklyReferralVolume();
        snapshot.totalTradingVolume = _sumWeeklyTradingVolume();
        snapshot.totalFeesGenerated = _sumWeeklyFeesGenerated();

        // Guardar top 10 de cada categoría
        for (uint256 cat = 0; cat < 3; cat++) {
            PerformanceCategory category = PerformanceCategory(cat);
            address[] memory ranking = rankings[category];
            
            for (uint256 i = 0; i < 10 && i < ranking.length; i++) {
                snapshot.topPerformers[category][i] = ranking[i];
                snapshot.topValues[category][i] = _getUserValueByCategory(
                    ranking[i],
                    category,
                    TrackingPeriod.WEEKLY
                );
            }
        }

        emit WeeklySnapshotCreated(weekNumber, block.timestamp, snapshot.totalActiveUsers);
    }

    /**
     * @dev Cuenta usuarios activos
     */
    function _countActiveUsers() internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (isActiveUser[activeUsers[i]] && userPerformance[activeUsers[i]].isActive) {
                count++;
            }
        }
        return count;
    }

    /**
     * @dev Suma volumen semanal de referidos
     */
    function _sumWeeklyReferralVolume() internal view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (isActiveUser[activeUsers[i]]) {
                sum += userPerformance[activeUsers[i]].referralVolumeWeekly;
            }
        }
        return sum;
    }

    /**
     * @dev Suma volumen semanal de trading
     */
    function _sumWeeklyTradingVolume() internal view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (isActiveUser[activeUsers[i]]) {
                sum += userPerformance[activeUsers[i]].tradingVolumeWeekly;
            }
        }
        return sum;
    }

    /**
     * @dev Suma fees semanales generados
     */
    function _sumWeeklyFeesGenerated() internal view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (isActiveUser[activeUsers[i]]) {
                sum += userPerformance[activeUsers[i]].feesGeneratedWeekly;
            }
        }
        return sum;
    }

    /**
     * @dev Calcula número de semana actual
     */
    function _getCurrentWeekNumber() internal view returns (uint256) {
        return block.timestamp / 1 weeks;
    }

    // ========================================
    // FUNCIONES DE CONSULTA
    // ========================================

    /**
     * @notice Obtiene performance completa de un usuario
     */
    function getUserPerformance(address user)
        external
        view
        returns (
            uint256 referralVolumeWeekly,
            uint256 tradingVolumeWeekly,
            uint256 feesGeneratedWeekly,
            uint256 engagementScore,
            bool isActive,
            uint256 totalActivities
        )
    {
        UserPerformance storage perf = userPerformance[user];
        return (
            perf.referralVolumeWeekly,
            perf.tradingVolumeWeekly,
            perf.feesGeneratedWeekly,
            perf.engagementScore,
            perf.isActive,
            perf.totalActivities
        );
    }

    /**
     * @notice Obtiene top performers de una categoría
     */
    function getTopPerformers(PerformanceCategory category, uint256 limit)
        external
        view
        returns (address[] memory users, uint256[] memory values)
    {
        address[] memory ranking = rankings[category];
        uint256 count = limit < ranking.length ? limit : ranking.length;
        
        users = new address[](count);
        values = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            users[i] = ranking[i];
            values[i] = _getUserValueByCategory(ranking[i], category, TrackingPeriod.WEEKLY);
        }

        return (users, values);
    }

    /**
     * @notice Obtiene snapshot de una semana
     */
    function getWeeklySnapshot(uint256 weekNumber)
        external
        view
        returns (
            uint256 timestamp,
            uint256 totalActiveUsers,
            uint256 totalReferralVolume,
            uint256 totalTradingVolume,
            uint256 totalFeesGenerated
        )
    {
        WeeklySnapshot storage snapshot = weeklySnapshots[weekNumber];
        return (
            snapshot.timestamp,
            snapshot.totalActiveUsers,
            snapshot.totalReferralVolume,
            snapshot.totalTradingVolume,
            snapshot.totalFeesGenerated
        );
    }

    /**
     * @notice Obtiene top 10 de una categoría en una semana específica
     */
    function getWeeklyTopPerformers(uint256 weekNumber, PerformanceCategory category)
        external
        view
        returns (address[10] memory users, uint256[10] memory values)
    {
        WeeklySnapshot storage snapshot = weeklySnapshots[weekNumber];
        return (snapshot.topPerformers[category], snapshot.topValues[category]);
    }

    /**
     * @notice Obtiene actividades de un usuario
     */
    function getUserActivities(address user, uint256 limit)
        external
        view
        returns (Activity[] memory)
    {
        uint256[] memory activityIds = userActivities[user];
        uint256 count = limit < activityIds.length ? limit : activityIds.length;
        
        Activity[] memory result = new Activity[](count);
        
        // Obtener las últimas actividades (orden inverso)
        uint256 startIndex = activityIds.length > count ? activityIds.length - count : 0;
        for (uint256 i = 0; i < count; i++) {
            result[i] = activities[activityIds[startIndex + i]];
        }

        return result;
    }

    /**
     * @notice Obtiene ranking de un usuario en una categoría
     */
    function getUserRank(address user, PerformanceCategory category)
        external
        view
        returns (uint256 rank)
    {
        address[] memory ranking = rankings[category];
        
        for (uint256 i = 0; i < ranking.length; i++) {
            if (ranking[i] == user) {
                return i + 1; // Rank empieza en 1
            }
        }

        return 0; // No está en ranking
    }

    /**
     * @notice Obtiene estadísticas globales
     */
    function getGlobalStats()
        external
        view
        returns (
            uint256 totalUsers,
            uint256 activeUsersCount,
            uint256 totalReferralVolume,
            uint256 totalTradingVolume,
            uint256 totalFeesGenerated,
            uint256 totalActivitiesRecorded
        )
    {
        return (
            totalUsersTracked,
            _countActiveUsers(),
            totalReferralVolumeAllTime,
            totalTradingVolumeAllTime,
            totalFeesGeneratedAllTime,
            activityCounter
        );
    }

    // ========================================
    // FUNCIONES ADMIN
    // ========================================

    /**
     * @notice Crea snapshot manualmente (para testing o emergencias)
     */
    function createManualSnapshot()
        external
        onlyRole(SNAPSHOT_ROLE)
    {
        _createWeeklySnapshot();
        currentWeek++;
    }

    /**
     * @notice Actualiza threshold de actividad
     */
    function setActivityThreshold(uint256 newThreshold)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        activityThreshold = newThreshold;
    }

    /**
     * @notice Fuerza actualización de rankings
     */
    function forceUpdateRankings()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < 4; i++) {
            _updateRankings(PerformanceCategory(i));
        }
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
