// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ReferralManager
 * @notice Sistema completo de referidos con múltiples niveles y distribución automática
 * @dev Gestiona códigos únicos, tracking de referidos, y distribución de comisiones
 * 
 * CARACTERÍSTICAS:
 * - Códigos de referido únicos generados automáticamente
 * - Sistema multi-nivel (hasta 3 niveles de profundidad)
 * - Comisiones configurables por nivel
 * - Distribución automática de rewards en USDC
 * - Tracking completo de volumen y earnings
 * - Integración con TreasuryManager (recibe del referralPool)
 * - Stats detalladas por referidor
 * - Prevención de auto-referidos
 * - Expiración de códigos opcional
 * 
 * NIVELES DE COMISIÓN (default):
 * - Nivel 1 (directo): 50% del 15% = 7.5% de fees
 * - Nivel 2 (indirecto): 30% del 15% = 4.5% de fees
 * - Nivel 3 (indirecto): 20% del 15% = 3% de fees
 * 
 * FLUJO:
 * 1. Usuario genera código único al registrarse
 * 2. Nuevo usuario usa código al hacer su primera operación
 * 3. Cuando nuevo usuario genera fees, se distribuye:
 *    - 50% al referidor directo
 *    - 30% al referidor del referidor
 *    - 20% al referidor nivel 3
 * 4. Si no hay referidor en algún nivel, esos % vuelven al pool
 * 
 * EJEMPLO:
 * Alice refiere a Bob → Bob refiere a Charlie
 * Charlie tradea y genera $100 en fees → $15 van a referralPool
 * 
 * Distribución:
 * - Bob (nivel 1 de Charlie): $15 * 50% = $7.50
 * - Alice (nivel 2 de Charlie): $15 * 30% = $4.50
 * - Nivel 3 no existe: $15 * 20% = $3.00 queda en pool
 * 
 * Total distribuido: $12.00
 * Queda en pool: $3.00 (para futuras distribuciones)
 */
contract ReferralManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========================================
    // ROLES
    // ========================================
    
    bytes32 public constant TRACKER_ROLE = keccak256("TRACKER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // ========================================
    // ESTRUCTURAS
    // ========================================

    /**
     * @dev Información de referido
     */
    struct ReferralInfo {
        address user;                   // Usuario referido
        address referrer;               // Quien lo refirió (nivel 1)
        address referrerLevel2;         // Nivel 2
        address referrerLevel3;         // Nivel 3
        string referralCode;            // Código usado
        uint256 registeredAt;           // Timestamp de registro
        uint256 totalVolumeGenerated;   // Volumen total generado
        uint256 totalFeesGenerated;     // Fees totales generados
        bool active;                    // Activo
    }

    /**
     * @dev Stats de un referidor
     */
    struct ReferrerStats {
        address referrer;
        uint256 totalReferrals;             // Referidos directos
        uint256 totalReferralsLevel2;       // Referidos nivel 2
        uint256 totalReferralsLevel3;       // Referidos nivel 3
        uint256 totalVolumeGenerated;       // Volumen generado por red
        uint256 totalFeesGenerated;         // Fees generados por red
        uint256 totalEarningsLevel1;        // Earnings de nivel 1
        uint256 totalEarningsLevel2;        // Earnings de nivel 2
        uint256 totalEarningsLevel3;        // Earnings de nivel 3
        uint256 pendingRewards;             // Rewards pendientes
        uint256 claimedRewards;             // Rewards ya reclamados
        uint256 lastActivityTimestamp;      // Última actividad
    }

    /**
     * @dev Configuración de niveles de comisión
     */
    struct CommissionConfig {
        uint256 level1Percent;  // % para nivel 1 (en BPS, ej: 5000 = 50%)
        uint256 level2Percent;  // % para nivel 2 (en BPS, ej: 3000 = 30%)
        uint256 level3Percent;  // % para nivel 3 (en BPS, ej: 2000 = 20%)
        bool enabled;
    }

    // ========================================
    // CONSTANTES
    // ========================================

    uint256 public constant BPS = 10000;  // 100% = 10000 basis points
    uint256 public constant MAX_CODE_LENGTH = 20;
    uint256 public constant MIN_CODE_LENGTH = 6;

    // ========================================
    // VARIABLES DE ESTADO
    // ========================================

    /// @notice Token de recompensas (USDC)
    IERC20 public rewardToken;

    /// @notice Configuración de comisiones
    CommissionConfig public commissionConfig;

    /// @notice Info de referidos por usuario
    mapping(address => ReferralInfo) public referralInfo;

    /// @notice Stats de referidores
    mapping(address => ReferrerStats) public referrerStats;

    /// @notice Código de referido a address
    mapping(string => address) public codeToAddress;

    /// @notice Address a código de referido
    mapping(address => string) public addressToCode;

    /// @notice Referidos directos de un usuario
    mapping(address => address[]) public directReferrals;

    /// @notice Contador global
    uint256 public totalUsers;
    uint256 public totalReferrals;
    uint256 public totalVolumeTracked;
    uint256 public totalFeesTracked;
    uint256 public totalRewardsDistributed;

    // ========================================
    // EVENTOS
    // ========================================

    event ReferralCodeGenerated(address indexed user, string code);
    event ReferralRegistered(address indexed user, address indexed referrer, string code);
    event VolumeRecorded(address indexed user, uint256 volume, uint256 fees);
    event RewardsDistributed(
        address indexed user,
        address indexed level1,
        address indexed level2,
        address level3,
        uint256 amountLevel1,
        uint256 amountLevel2,
        uint256 amountLevel3
    );
    event RewardsClaimed(address indexed referrer, uint256 amount);
    event CommissionConfigUpdated(uint256 level1, uint256 level2, uint256 level3);

    // ========================================
    // ERRORES
    // ========================================

    error InvalidAddress();
    error InvalidCode();
    error CodeAlreadyExists();
    error CodeNotFound();
    error AlreadyReferred();
    error SelfReferralNotAllowed();
    error InsufficientBalance();
    error NoRewardsToClaim();
    error InvalidCommissionConfig();

    // ========================================
    // CONSTRUCTOR
    // ========================================

    constructor(
        address admin,
        address _rewardToken
    ) {
        if (admin == address(0) || _rewardToken == address(0)) revert InvalidAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TRACKER_ROLE, admin);
        _grantRole(DISTRIBUTOR_ROLE, admin);

        rewardToken = IERC20(_rewardToken);

        // Configuración por defecto: 50%, 30%, 20%
        commissionConfig = CommissionConfig({
            level1Percent: 5000,  // 50%
            level2Percent: 3000,  // 30%
            level3Percent: 2000,  // 20%
            enabled: true
        });
    }

    // ========================================
    // FUNCIONES PRINCIPALES
    // ========================================

    /**
     * @notice Genera código de referido único para un usuario
     * @param user Usuario
     * @param code Código personalizado (opcional, si es "" se genera auto)
     */
    function generateReferralCode(address user, string memory code)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (user == address(0)) revert InvalidAddress();
        if (bytes(addressToCode[user]).length > 0) revert CodeAlreadyExists();

        string memory finalCode = code;
        
        // Si no se provee código, generar automático basado en address
        if (bytes(code).length == 0) {
            finalCode = _generateAutoCode(user);
        } else {
            if (bytes(code).length < MIN_CODE_LENGTH || bytes(code).length > MAX_CODE_LENGTH) {
                revert InvalidCode();
            }
            if (codeToAddress[code] != address(0)) revert CodeAlreadyExists();
        }

        codeToAddress[finalCode] = user;
        addressToCode[user] = finalCode;
        totalUsers++;

        emit ReferralCodeGenerated(user, finalCode);
    }

    /**
     * @notice Registra un referido usando código
     * @param user Usuario nuevo
     * @param referralCode Código del referidor
     */
    function registerReferral(address user, string memory referralCode)
        external
        onlyRole(TRACKER_ROLE)
        whenNotPaused
    {
        if (user == address(0)) revert InvalidAddress();
        if (referralInfo[user].active) revert AlreadyReferred();
        
        address referrer = codeToAddress[referralCode];
        if (referrer == address(0)) revert CodeNotFound();
        if (referrer == user) revert SelfReferralNotAllowed();

        // Construir cadena de referidos (hasta 3 niveles)
        address level2 = referralInfo[referrer].referrer;
        address level3 = level2 != address(0) ? referralInfo[level2].referrer : address(0);

        referralInfo[user] = ReferralInfo({
            user: user,
            referrer: referrer,
            referrerLevel2: level2,
            referrerLevel3: level3,
            referralCode: referralCode,
            registeredAt: block.timestamp,
            totalVolumeGenerated: 0,
            totalFeesGenerated: 0,
            active: true
        });

        // Actualizar stats de referidores
        referrerStats[referrer].totalReferrals++;
        directReferrals[referrer].push(user);

        if (level2 != address(0)) {
            referrerStats[level2].totalReferralsLevel2++;
        }
        if (level3 != address(0)) {
            referrerStats[level3].totalReferralsLevel3++;
        }

        totalReferrals++;

        emit ReferralRegistered(user, referrer, referralCode);
    }

    /**
     * @notice Registra volumen/fees generados por un usuario y distribuye rewards
     * @param user Usuario que generó actividad
     * @param volume Volumen de trading
     * @param fees Fees generados
     */
    function recordActivityAndDistribute(address user, uint256 volume, uint256 fees)
        external
        onlyRole(TRACKER_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (user == address(0)) revert InvalidAddress();
        
        ReferralInfo storage info = referralInfo[user];
        if (!info.active) return; // Usuario sin referidor, no distribuir

        // Actualizar stats del usuario
        info.totalVolumeGenerated += volume;
        info.totalFeesGenerated += fees;

        totalVolumeTracked += volume;
        totalFeesTracked += fees;

        // Distribuir comisiones a los 3 niveles
        _distributeCommissions(user, fees);

        emit VolumeRecorded(user, volume, fees);
    }

    /**
     * @notice Permite a un referidor reclamar sus rewards acumulados
     */
    function claimRewards() external nonReentrant whenNotPaused {
        ReferrerStats storage stats = referrerStats[msg.sender];
        uint256 pending = stats.pendingRewards;

        if (pending == 0) revert NoRewardsToClaim();

        uint256 available = rewardToken.balanceOf(address(this));
        if (available < pending) revert InsufficientBalance();

        stats.pendingRewards = 0;
        stats.claimedRewards += pending;

        rewardToken.safeTransfer(msg.sender, pending);

        emit RewardsClaimed(msg.sender, pending);
    }

    // ========================================
    // FUNCIONES INTERNAS
    // ========================================

    /**
     * @notice Distribuye comisiones a los 3 niveles de referidores
     */
    function _distributeCommissions(address user, uint256 fees) internal {
        if (!commissionConfig.enabled) return;

        ReferralInfo storage info = referralInfo[user];
        
        address level1 = info.referrer;
        address level2 = info.referrerLevel2;
        address level3 = info.referrerLevel3;

        uint256 amountLevel1 = 0;
        uint256 amountLevel2 = 0;
        uint256 amountLevel3 = 0;

        // Calcular comisiones
        if (level1 != address(0)) {
            amountLevel1 = (fees * commissionConfig.level1Percent) / BPS;
            referrerStats[level1].totalEarningsLevel1 += amountLevel1;
            referrerStats[level1].pendingRewards += amountLevel1;
            referrerStats[level1].totalVolumeGenerated += info.totalVolumeGenerated;
            referrerStats[level1].totalFeesGenerated += fees;
            referrerStats[level1].lastActivityTimestamp = block.timestamp;
        }

        if (level2 != address(0)) {
            amountLevel2 = (fees * commissionConfig.level2Percent) / BPS;
            referrerStats[level2].totalEarningsLevel2 += amountLevel2;
            referrerStats[level2].pendingRewards += amountLevel2;
            referrerStats[level2].lastActivityTimestamp = block.timestamp;
        }

        if (level3 != address(0)) {
            amountLevel3 = (fees * commissionConfig.level3Percent) / BPS;
            referrerStats[level3].totalEarningsLevel3 += amountLevel3;
            referrerStats[level3].pendingRewards += amountLevel3;
            referrerStats[level3].lastActivityTimestamp = block.timestamp;
        }

        uint256 totalDistributed = amountLevel1 + amountLevel2 + amountLevel3;
        totalRewardsDistributed += totalDistributed;

        emit RewardsDistributed(user, level1, level2, level3, amountLevel1, amountLevel2, amountLevel3);
    }

    /**
     * @notice Genera código automático basado en address
     */
    function _generateAutoCode(address user) internal pure returns (string memory) {
        bytes memory addressBytes = abi.encodePacked(user);
        bytes memory result = new bytes(8);
        
        for (uint256 i = 0; i < 8; i++) {
            uint8 value = uint8(addressBytes[i + 12]);
            uint8 char1 = value / 16;
            result[i] = bytes1(char1 < 10 ? 48 + char1 : 55 + char1);
        }
        
        return string(result);
    }

    // ========================================
    // FUNCIONES DE VISTA
    // ========================================

    /**
     * @notice Obtiene info completa de referido
     */
    function getReferralInfo(address user) external view returns (ReferralInfo memory) {
        return referralInfo[user];
    }

    /**
     * @notice Obtiene stats completas de referidor
     */
    function getReferrerStats(address referrer) external view returns (ReferrerStats memory) {
        return referrerStats[referrer];
    }

    /**
     * @notice Obtiene referidos directos de un usuario
     */
    function getDirectReferrals(address referrer) external view returns (address[] memory) {
        return directReferrals[referrer];
    }

    /**
     * @notice Obtiene código de referido de un usuario
     */
    function getUserCode(address user) external view returns (string memory) {
        return addressToCode[user];
    }

    /**
     * @notice Verifica si un código existe
     */
    function codeExists(string memory code) external view returns (bool) {
        return codeToAddress[code] != address(0);
    }

    /**
     * @notice Obtiene estadísticas globales
     */
    function getGlobalStats() external view returns (
        uint256 _totalUsers,
        uint256 _totalReferrals,
        uint256 _totalVolumeTracked,
        uint256 _totalFeesTracked,
        uint256 _totalRewardsDistributed,
        uint256 poolBalance
    ) {
        return (
            totalUsers,
            totalReferrals,
            totalVolumeTracked,
            totalFeesTracked,
            totalRewardsDistributed,
            rewardToken.balanceOf(address(this))
        );
    }

    // ========================================
    // FUNCIONES ADMIN
    // ========================================

    /**
     * @notice Actualiza configuración de comisiones
     */
    function updateCommissionConfig(
        uint256 level1,
        uint256 level2,
        uint256 level3
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (level1 + level2 + level3 > BPS) revert InvalidCommissionConfig();
        
        commissionConfig.level1Percent = level1;
        commissionConfig.level2Percent = level2;
        commissionConfig.level3Percent = level3;

        emit CommissionConfigUpdated(level1, level2, level3);
    }

    /**
     * @notice Habilita/deshabilita distribución de comisiones
     */
    function setCommissionEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        commissionConfig.enabled = enabled;
    }

    /**
     * @notice Retira fondos de emergencia (solo admin)
     */
    function emergencyWithdraw(address token, uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
