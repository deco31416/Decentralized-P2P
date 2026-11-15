// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title VestingManager
 * @notice Sistema de vesting (liberación gradual) de tokens con cliff period
 * @dev Gestiona schedules de vesting para beneficiarios con las siguientes características:
 * 
 * CARACTERÍSTICAS:
 * - Cliff period: Período inicial sin liberación de tokens
 * - Linear release: Liberación lineal después del cliff
 * - Multiple schedules: Múltiples schedules por beneficiario
 * - Revocable: Schedules pueden ser revocables por admin
 * - IDO Integration: Integración automática con IDOManager
 * 
 * TIPOS DE VESTING:
 * 1. Team Vesting: 12 meses cliff + 24 meses linear
 * 2. Advisor Vesting: 6 meses cliff + 18 meses linear
 * 3. IDO Vesting: 1-3 meses cliff + 6-12 meses linear
 * 4. Partnership Vesting: Custom según acuerdo
 * 
 * FLUJO DE VESTING:
 * 1. Admin/IDOManager crea vesting schedule
 * 2. Tokens quedan bloqueados en el contrato
 * 3. Beneficiario espera cliff period
 * 4. Después del cliff, tokens se liberan linealmente
 * 5. Beneficiario reclama tokens liberados cuando quiera
 * 
 * EJEMPLO:
 * - Total: 10,000 tokens
 * - Cliff: 6 meses
 * - Duration: 24 meses
 * - Initial release: 10% (1,000 tokens inmediatos)
 * 
 * Timeline:
 * - Mes 0: 1,000 tokens disponibles (initial release)
 * - Mes 1-6: 0 tokens liberados (cliff)
 * - Mes 7: ~500 tokens liberados (1/18 del remaining)
 * - Mes 24: 10,000 tokens totalmente liberados
 */
contract VestingManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========================================
    // ROLES
    // ========================================
    
    bytes32 public constant VESTING_ADMIN_ROLE = keccak256("VESTING_ADMIN_ROLE");
    bytes32 public constant IDO_ROLE = keccak256("IDO_ROLE");

    // ========================================
    // ESTRUCTURAS
    // ========================================

    /**
     * @dev Tipos de vesting predefinidos
     */
    enum VestingType {
        CUSTOM,         // Custom configuration
        TEAM,           // Team members (12m cliff + 24m linear)
        ADVISOR,        // Advisors (6m cliff + 18m linear)
        IDO_SHORT,      // IDO short (1m cliff + 6m linear)
        IDO_MEDIUM,     // IDO medium (2m cliff + 9m linear)
        IDO_LONG,       // IDO long (3m cliff + 12m linear)
        PARTNERSHIP     // Partnership (custom)
    }

    /**
     * @dev Estado del vesting schedule
     */
    enum VestingStatus {
        ACTIVE,     // Activo
        REVOKED,    // Revocado
        COMPLETED   // Completado (todo reclamado)
    }

    /**
     * @dev Información de vesting schedule
     */
    struct VestingSchedule {
        uint256 scheduleId;             // ID único del schedule
        address beneficiary;            // Beneficiario
        address token;                  // Token a vestear
        uint256 totalAmount;            // Cantidad total
        uint256 amountClaimed;          // Cantidad ya reclamada
        uint256 startTime;              // Tiempo de inicio
        uint256 cliffDuration;          // Duración del cliff (segundos)
        uint256 vestingDuration;        // Duración total del vesting (segundos)
        uint256 initialReleasePercent;  // % de release inicial (basis points)
        bool revocable;                 // ¿Puede ser revocado?
        VestingStatus status;           // Estado
        VestingType vestingType;        // Tipo de vesting
        uint256 createdAt;              // Timestamp de creación
        address creator;                // Quién lo creó
    }

    /**
     * @dev Configuración de tipo de vesting
     */
    struct VestingTypeConfig {
        uint256 cliffDuration;          // Duración del cliff
        uint256 vestingDuration;        // Duración del vesting
        uint256 initialReleasePercent;  // % inicial
        bool revocable;                 // ¿Revocable?
    }

    // ========================================
    // VARIABLES DE ESTADO
    // ========================================

    /// @notice Contador de schedules
    uint256 public scheduleCounter;

    /// @notice Schedules por ID
    mapping(uint256 => VestingSchedule) public schedules;

    /// @notice Schedules por beneficiario
    mapping(address => uint256[]) public beneficiarySchedules;

    /// @notice Schedules por token
    mapping(address => uint256[]) public tokenSchedules;

    /// @notice Total vestiendo por token
    mapping(address => uint256) public totalVestingByToken;

    /// @notice Configuraciones de tipos de vesting
    mapping(VestingType => VestingTypeConfig) public vestingTypeConfigs;

    /// @notice Total de schedules creados
    uint256 public totalSchedulesCreated;

    /// @notice Total de tokens reclamados
    mapping(address => uint256) public totalTokensClaimed;

    // ========================================
    // EVENTOS
    // ========================================

    event VestingScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        address indexed token,
        uint256 totalAmount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        VestingType vestingType
    );

    event TokensClaimed(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        address indexed token,
        uint256 amount
    );

    event VestingRevoked(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 amountVested,
        uint256 amountRevoked
    );

    event VestingCompleted(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 totalAmount
    );

    event VestingTypeConfigUpdated(
        VestingType indexed vestingType,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 initialReleasePercent
    );

    // ========================================
    // ERRORES
    // ========================================

    error InvalidAddress();
    error InvalidAmount();
    error InvalidDuration();
    error InvalidPercent();
    error ScheduleNotFound();
    error NotBeneficiary();
    error NoTokensAvailable();
    error ScheduleNotRevocable();
    error ScheduleAlreadyRevoked();
    error InsufficientBalance();
    error CliffNotEnded();

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
        _grantRole(VESTING_ADMIN_ROLE, admin);

        // Configurar tipos de vesting predefinidos
        _setupVestingTypes();
    }

    /**
     * @dev Configura tipos de vesting predefinidos
     */
    function _setupVestingTypes() internal {
        // TEAM: 12 meses cliff + 24 meses linear, 0% initial
        vestingTypeConfigs[VestingType.TEAM] = VestingTypeConfig({
            cliffDuration: 365 days,
            vestingDuration: 730 days,
            initialReleasePercent: 0,
            revocable: true
        });

        // ADVISOR: 6 meses cliff + 18 meses linear, 0% initial
        vestingTypeConfigs[VestingType.ADVISOR] = VestingTypeConfig({
            cliffDuration: 180 days,
            vestingDuration: 545 days,
            initialReleasePercent: 0,
            revocable: true
        });

        // IDO_SHORT: 1 mes cliff + 6 meses linear, 10% initial
        vestingTypeConfigs[VestingType.IDO_SHORT] = VestingTypeConfig({
            cliffDuration: 30 days,
            vestingDuration: 180 days,
            initialReleasePercent: 1000, // 10%
            revocable: false
        });

        // IDO_MEDIUM: 2 meses cliff + 9 meses linear, 10% initial
        vestingTypeConfigs[VestingType.IDO_MEDIUM] = VestingTypeConfig({
            cliffDuration: 60 days,
            vestingDuration: 270 days,
            initialReleasePercent: 1000, // 10%
            revocable: false
        });

        // IDO_LONG: 3 meses cliff + 12 meses linear, 5% initial
        vestingTypeConfigs[VestingType.IDO_LONG] = VestingTypeConfig({
            cliffDuration: 90 days,
            vestingDuration: 365 days,
            initialReleasePercent: 500, // 5%
            revocable: false
        });
    }

    // ========================================
    // FUNCIONES PRINCIPALES - CREAR VESTING
    // ========================================

    /**
     * @notice Crea un vesting schedule con tipo predefinido
     * @param beneficiary Beneficiario del vesting
     * @param token Token a vestear
     * @param totalAmount Cantidad total
     * @param vestingType Tipo de vesting predefinido
     * @return scheduleId ID del schedule creado
     */
    function createVestingSchedule(
        address beneficiary,
        address token,
        uint256 totalAmount,
        VestingType vestingType
    )
        external
        onlyRole(VESTING_ADMIN_ROLE)
        whenNotPaused
        returns (uint256 scheduleId)
    {
        if (beneficiary == address(0) || token == address(0)) revert InvalidAddress();
        if (totalAmount == 0) revert InvalidAmount();
        if (vestingType == VestingType.CUSTOM) revert InvalidDuration();

        VestingTypeConfig memory config = vestingTypeConfigs[vestingType];

        scheduleId = _createSchedule(
            beneficiary,
            token,
            totalAmount,
            config.cliffDuration,
            config.vestingDuration,
            config.initialReleasePercent,
            config.revocable,
            vestingType
        );

        // Transferir tokens al contrato
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    /**
     * @notice Crea un vesting schedule custom
     * @param beneficiary Beneficiario del vesting
     * @param token Token a vestear
     * @param totalAmount Cantidad total
     * @param cliffDuration Duración del cliff (segundos)
     * @param vestingDuration Duración total del vesting (segundos)
     * @param initialReleasePercent % de release inicial (basis points, max 5000 = 50%)
     * @param revocable ¿Puede ser revocado?
     * @return scheduleId ID del schedule creado
     */
    function createCustomVestingSchedule(
        address beneficiary,
        address token,
        uint256 totalAmount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 initialReleasePercent,
        bool revocable
    )
        external
        onlyRole(VESTING_ADMIN_ROLE)
        whenNotPaused
        returns (uint256 scheduleId)
    {
        if (beneficiary == address(0) || token == address(0)) revert InvalidAddress();
        if (totalAmount == 0) revert InvalidAmount();
        if (vestingDuration == 0) revert InvalidDuration();
        if (initialReleasePercent > 5000) revert InvalidPercent(); // Max 50% initial

        scheduleId = _createSchedule(
            beneficiary,
            token,
            totalAmount,
            cliffDuration,
            vestingDuration,
            initialReleasePercent,
            revocable,
            VestingType.CUSTOM
        );

        // Transferir tokens al contrato
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    /**
     * @notice Crea vesting desde IDOManager (solo IDO_ROLE)
     * @dev Usado por IDOManager para crear vesting automático
     */
    function createIDOVesting(
        address beneficiary,
        address token,
        uint256 totalAmount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 initialReleasePercent
    )
        external
        onlyRole(IDO_ROLE)
        whenNotPaused
        returns (uint256 scheduleId)
    {
        if (beneficiary == address(0) || token == address(0)) revert InvalidAddress();
        if (totalAmount == 0) revert InvalidAmount();

        scheduleId = _createSchedule(
            beneficiary,
            token,
            totalAmount,
            cliffDuration,
            vestingDuration,
            initialReleasePercent,
            false, // IDO vesting no es revocable
            VestingType.CUSTOM
        );

        // IDOManager ya transfirió los tokens, no necesitamos transferFrom
        // Solo verificamos que tengamos balance suficiente
        if (IERC20(token).balanceOf(address(this)) < totalVestingByToken[token]) {
            revert InsufficientBalance();
        }
    }

    /**
     * @dev Función interna para crear schedule
     */
    function _createSchedule(
        address beneficiary,
        address token,
        uint256 totalAmount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 initialReleasePercent,
        bool revocable,
        VestingType vestingType
    )
        internal
        returns (uint256 scheduleId)
    {
        scheduleId = ++scheduleCounter;

        schedules[scheduleId] = VestingSchedule({
            scheduleId: scheduleId,
            beneficiary: beneficiary,
            token: token,
            totalAmount: totalAmount,
            amountClaimed: 0,
            startTime: block.timestamp,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            initialReleasePercent: initialReleasePercent,
            revocable: revocable,
            status: VestingStatus.ACTIVE,
            vestingType: vestingType,
            createdAt: block.timestamp,
            creator: msg.sender
        });

        // Actualizar mappings
        beneficiarySchedules[beneficiary].push(scheduleId);
        tokenSchedules[token].push(scheduleId);
        totalVestingByToken[token] += totalAmount;
        totalSchedulesCreated++;

        emit VestingScheduleCreated(
            scheduleId,
            beneficiary,
            token,
            totalAmount,
            cliffDuration,
            vestingDuration,
            vestingType
        );
    }

    // ========================================
    // FUNCIONES PRINCIPALES - RECLAMAR
    // ========================================

    /**
     * @notice Reclama tokens vested disponibles
     * @param scheduleId ID del schedule
     * 
     * CÁLCULO DE TOKENS DISPONIBLES:
     * 1. Si aún no pasó cliff: Solo initial release (si aplica)
     * 2. Si pasó cliff: Initial release + tokens linealmente vested
     * 3. Tokens disponibles = Total calculado - Ya reclamado
     * 
     * EJEMPLO:
     * - Total: 10,000 tokens
     * - Initial: 10% = 1,000 tokens
     * - Cliff: 6 meses
     * - Duration: 24 meses
     * - Tiempo transcurrido: 12 meses (6 meses después del cliff)
     * - Vesting progress: 6 / 18 = 33.33%
     * - Tokens vested: 1,000 (initial) + (9,000 * 33.33%) = 4,000 tokens
     */
    function claimVestedTokens(uint256 scheduleId)
        external
        nonReentrant
        whenNotPaused
    {
        VestingSchedule storage schedule = schedules[scheduleId];

        if (schedule.scheduleId == 0) revert ScheduleNotFound();
        if (schedule.beneficiary != msg.sender) revert NotBeneficiary();
        if (schedule.status == VestingStatus.REVOKED) revert ScheduleAlreadyRevoked();

        uint256 claimableAmount = _calculateClaimableAmount(scheduleId);
        if (claimableAmount == 0) revert NoTokensAvailable();

        // Actualizar schedule
        schedule.amountClaimed += claimableAmount;

        // Si reclamó todo, marcar como completado
        if (schedule.amountClaimed >= schedule.totalAmount) {
            schedule.status = VestingStatus.COMPLETED;
            emit VestingCompleted(scheduleId, schedule.beneficiary, schedule.totalAmount);
        }

        // Actualizar totales
        totalTokensClaimed[schedule.token] += claimableAmount;

        // Transferir tokens
        IERC20(schedule.token).safeTransfer(schedule.beneficiary, claimableAmount);

        emit TokensClaimed(scheduleId, schedule.beneficiary, schedule.token, claimableAmount);
    }

    /**
     * @notice Reclama de múltiples schedules a la vez
     * @param scheduleIds Array de IDs de schedules
     */
    function claimMultipleSchedules(uint256[] calldata scheduleIds)
        external
        nonReentrant
        whenNotPaused
    {
        for (uint256 i = 0; i < scheduleIds.length; i++) {
            uint256 scheduleId = scheduleIds[i];
            VestingSchedule storage schedule = schedules[scheduleId];

            // Saltar si no cumple requisitos
            if (schedule.scheduleId == 0) continue;
            if (schedule.beneficiary != msg.sender) continue;
            if (schedule.status == VestingStatus.REVOKED) continue;

            uint256 claimableAmount = _calculateClaimableAmount(scheduleId);
            if (claimableAmount == 0) continue;

            // Actualizar schedule
            schedule.amountClaimed += claimableAmount;

            // Si reclamó todo, marcar como completado
            if (schedule.amountClaimed >= schedule.totalAmount) {
                schedule.status = VestingStatus.COMPLETED;
                emit VestingCompleted(scheduleId, schedule.beneficiary, schedule.totalAmount);
            }

            // Actualizar totales
            totalTokensClaimed[schedule.token] += claimableAmount;

            // Transferir tokens
            IERC20(schedule.token).safeTransfer(schedule.beneficiary, claimableAmount);

            emit TokensClaimed(scheduleId, schedule.beneficiary, schedule.token, claimableAmount);
        }
    }

    // ========================================
    // FUNCIONES DE ADMINISTRACIÓN
    // ========================================

    /**
     * @notice Revoca un vesting schedule
     * @dev Solo puede revocar si el schedule es revocable
     * @param scheduleId ID del schedule a revocar
     * 
     * Al revocar:
     * - Tokens ya vested van al beneficiario
     * - Tokens no vested regresan al creator
     */
    function revokeVesting(uint256 scheduleId)
        external
        onlyRole(VESTING_ADMIN_ROLE)
        nonReentrant
    {
        VestingSchedule storage schedule = schedules[scheduleId];

        if (schedule.scheduleId == 0) revert ScheduleNotFound();
        if (!schedule.revocable) revert ScheduleNotRevocable();
        if (schedule.status == VestingStatus.REVOKED) revert ScheduleAlreadyRevoked();

        // Calcular tokens vested y no vested
        uint256 vestedAmount = _calculateVestedAmount(scheduleId);
        uint256 claimableAmount = vestedAmount - schedule.amountClaimed;
        uint256 nonVestedAmount = schedule.totalAmount - vestedAmount;

        // Actualizar estado
        schedule.status = VestingStatus.REVOKED;
        schedule.amountClaimed = vestedAmount;

        // Transferir tokens vested al beneficiario
        if (claimableAmount > 0) {
            IERC20(schedule.token).safeTransfer(schedule.beneficiary, claimableAmount);
            totalTokensClaimed[schedule.token] += claimableAmount;
        }

        // Transferir tokens no vested al creator
        if (nonVestedAmount > 0) {
            IERC20(schedule.token).safeTransfer(schedule.creator, nonVestedAmount);
            totalVestingByToken[schedule.token] -= nonVestedAmount;
        }

        emit VestingRevoked(scheduleId, schedule.beneficiary, vestedAmount, nonVestedAmount);
    }

    // ========================================
    // FUNCIONES DE CÁLCULO
    // ========================================

    /**
     * @notice Calcula cantidad total vested (liberada) hasta el momento
     * @param scheduleId ID del schedule
     * @return Cantidad total vested
     */
    function _calculateVestedAmount(uint256 scheduleId) internal view returns (uint256) {
        VestingSchedule storage schedule = schedules[scheduleId];

        if (schedule.status == VestingStatus.REVOKED) {
            return schedule.amountClaimed;
        }

        uint256 timeElapsed = block.timestamp - schedule.startTime;

        // 1. Calcular initial release
        uint256 initialRelease = (schedule.totalAmount * schedule.initialReleasePercent) / 10000;

        // 2. Si no pasó cliff, solo initial release
        if (timeElapsed < schedule.cliffDuration) {
            return initialRelease;
        }

        // 3. Calcular tiempo post-cliff
        uint256 timeAfterCliff = timeElapsed - schedule.cliffDuration;
        uint256 vestingTimeRemaining = schedule.vestingDuration - schedule.cliffDuration;

        // 4. Si ya pasó toda la duración, retornar todo
        if (timeAfterCliff >= vestingTimeRemaining) {
            return schedule.totalAmount;
        }

        // 5. Calcular vesting lineal post-cliff
        uint256 amountToVest = schedule.totalAmount - initialRelease;
        uint256 vestedAmount = (amountToVest * timeAfterCliff) / vestingTimeRemaining;

        return initialRelease + vestedAmount;
    }

    /**
     * @notice Calcula cantidad disponible para reclamar
     * @param scheduleId ID del schedule
     * @return Cantidad disponible para reclamar
     */
    function _calculateClaimableAmount(uint256 scheduleId) internal view returns (uint256) {
        uint256 vestedAmount = _calculateVestedAmount(scheduleId);
        uint256 claimedAmount = schedules[scheduleId].amountClaimed;
        
        if (vestedAmount <= claimedAmount) {
            return 0;
        }

        return vestedAmount - claimedAmount;
    }

    // ========================================
    // FUNCIONES DE CONSULTA
    // ========================================

    /**
     * @notice Obtiene información completa de un schedule
     */
    function getSchedule(uint256 scheduleId)
        external
        view
        returns (
            address beneficiary,
            address token,
            uint256 totalAmount,
            uint256 amountClaimed,
            uint256 amountVested,
            uint256 amountClaimable,
            uint256 startTime,
            uint256 cliffEnd,
            uint256 vestingEnd,
            VestingStatus status,
            VestingType vestingType
        )
    {
        VestingSchedule storage schedule = schedules[scheduleId];
        
        return (
            schedule.beneficiary,
            schedule.token,
            schedule.totalAmount,
            schedule.amountClaimed,
            _calculateVestedAmount(scheduleId),
            _calculateClaimableAmount(scheduleId),
            schedule.startTime,
            schedule.startTime + schedule.cliffDuration,
            schedule.startTime + schedule.vestingDuration,
            schedule.status,
            schedule.vestingType
        );
    }

    /**
     * @notice Obtiene todos los schedules de un beneficiario
     */
    function getBeneficiarySchedules(address beneficiary)
        external
        view
        returns (uint256[] memory)
    {
        return beneficiarySchedules[beneficiary];
    }

    /**
     * @notice Obtiene total claimable de un beneficiario
     */
    function getTotalClaimable(address beneficiary)
        external
        view
        returns (uint256 total)
    {
        uint256[] memory scheduleIds = beneficiarySchedules[beneficiary];
        
        for (uint256 i = 0; i < scheduleIds.length; i++) {
            VestingSchedule storage schedule = schedules[scheduleIds[i]];
            if (schedule.status == VestingStatus.ACTIVE) {
                total += _calculateClaimableAmount(scheduleIds[i]);
            }
        }

        return total;
    }

    /**
     * @notice Obtiene estadísticas de un beneficiario
     */
    function getBeneficiaryStats(address beneficiary)
        external
        view
        returns (
            uint256 totalSchedules,
            uint256 activeSchedules,
            uint256 totalVesting,
            uint256 totalVested,
            uint256 totalClaimed,
            uint256 totalClaimable
        )
    {
        uint256[] memory scheduleIds = beneficiarySchedules[beneficiary];
        totalSchedules = scheduleIds.length;

        for (uint256 i = 0; i < scheduleIds.length; i++) {
            VestingSchedule storage schedule = schedules[scheduleIds[i]];
            
            if (schedule.status == VestingStatus.ACTIVE) {
                activeSchedules++;
                totalVesting += schedule.totalAmount;
                totalVested += _calculateVestedAmount(scheduleIds[i]);
                totalClaimed += schedule.amountClaimed;
                totalClaimable += _calculateClaimableAmount(scheduleIds[i]);
            }
        }
    }

    /**
     * @notice Verifica si el cliff ya terminó
     */
    function hasCliffEnded(uint256 scheduleId) external view returns (bool) {
        VestingSchedule storage schedule = schedules[scheduleId];
        return block.timestamp >= schedule.startTime + schedule.cliffDuration;
    }

    /**
     * @notice Verifica si el vesting ya terminó completamente
     */
    function hasVestingEnded(uint256 scheduleId) external view returns (bool) {
        VestingSchedule storage schedule = schedules[scheduleId];
        return block.timestamp >= schedule.startTime + schedule.vestingDuration;
    }

    /**
     * @notice Obtiene progreso del vesting (0-10000 = 0-100%)
     */
    function getVestingProgress(uint256 scheduleId) external view returns (uint256) {
        VestingSchedule storage schedule = schedules[scheduleId];
        
        if (schedule.status != VestingStatus.ACTIVE) {
            return 10000; // 100%
        }

        uint256 timeElapsed = block.timestamp - schedule.startTime;
        
        if (timeElapsed >= schedule.vestingDuration) {
            return 10000; // 100%
        }

        return (timeElapsed * 10000) / schedule.vestingDuration;
    }

    // ========================================
    // FUNCIONES ADMIN
    // ========================================

    /**
     * @notice Actualiza configuración de tipo de vesting
     */
    function updateVestingTypeConfig(
        VestingType vestingType,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 initialReleasePercent,
        bool revocable
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (vestingType == VestingType.CUSTOM) revert InvalidDuration();
        if (initialReleasePercent > 5000) revert InvalidPercent();

        vestingTypeConfigs[vestingType] = VestingTypeConfig({
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            initialReleasePercent: initialReleasePercent,
            revocable: revocable
        });

        emit VestingTypeConfigUpdated(
            vestingType,
            cliffDuration,
            vestingDuration,
            initialReleasePercent
        );
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

    /**
     * @notice Recupera tokens enviados por error
     * @dev Solo puede recuperar tokens que no estén en vesting
     */
    function recoverTokens(address token, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 vestingAmount = totalVestingByToken[token];
        uint256 claimedAmount = totalTokensClaimed[token];
        uint256 locked = vestingAmount - claimedAmount;

        if (balance < locked + amount) revert InsufficientBalance();

        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
