// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title KYCManager
 * @notice Gestiona verificación KYC con tiers y límites por nivel
 * @dev Sistema de 3 tiers: Tier0 (sin KYC), Tier1 (básico), Tier2 (completo)
 */
contract KYCManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // ============================================
    // Roles
    // ============================================
    bytes32 public constant KYC_VERIFIER_ROLE = keccak256("KYC_VERIFIER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============================================
    // Enums
    // ============================================
    enum KYCStatus {
        NOT_SUBMITTED,  // No ha enviado documentos
        PENDING,        // En revisión
        APPROVED,       // Aprobado
        REJECTED,       // Rechazado
        EXPIRED         // Expirado (requiere renovación)
    }

    enum KYCTier {
        TIER_0,  // Sin verificación - Límites bajos
        TIER_1,  // KYC básico - Límites medios
        TIER_2   // KYC completo - Sin límites
    }

    // ============================================
    // Structs
    // ============================================
    struct KYCData {
        address user;
        KYCStatus status;
        KYCTier tier;
        uint256 submittedAt;
        uint256 approvedAt;
        uint256 expiresAt;
        string documentHash;  // IPFS hash de documentos
        string rejectionReason;
        address verifier;
        uint256 resubmissionCount;
    }

    struct TierLimits {
        uint256 dailyDepositLimit;    // Límite diario en USD (18 decimales)
        uint256 dailyWithdrawLimit;   // Límite diario en USD (18 decimales)
        uint256 monthlyVolumeLimit;   // Límite mensual en USD (18 decimales)
        bool requiresKYC;             // Si requiere KYC
        bool canBeIntermediary;       // Si puede ser intermediario
        bool canCreateOffers;         // Si puede crear ofertas P2P
    }

    // ============================================
    // State Variables
    // ============================================
    mapping(address => KYCData) public kycData;
    mapping(KYCTier => TierLimits) public tierLimits;
    
    // Tracking de volumen para límites
    mapping(address => mapping(uint256 => uint256)) public dailyDeposits;   // user => day => amount
    mapping(address => mapping(uint256 => uint256)) public dailyWithdraws;  // user => day => amount
    mapping(address => mapping(uint256 => uint256)) public monthlyVolume;   // user => month => amount

    // Lista de usuarios por tier
    mapping(KYCTier => address[]) public usersByTier;
    mapping(address => uint256) public userTierIndex;

    // Configuración
    uint256 public constant KYC_VALIDITY_PERIOD = 365 days;  // 1 año
    uint256 public constant RESUBMISSION_COOLDOWN = 7 days;   // 7 días entre resubmisiones
    uint256 public kycFee;  // Fee en native token para procesar KYC

    // Estadísticas
    uint256 public totalKYCSubmitted;
    uint256 public totalKYCApproved;
    uint256 public totalKYCRejected;

    // ============================================
    // Events
    // ============================================
    event KYCSubmitted(
        address indexed user,
        KYCTier requestedTier,
        string documentHash,
        uint256 timestamp
    );

    event KYCApproved(
        address indexed user,
        KYCTier tier,
        address indexed verifier,
        uint256 timestamp,
        uint256 expiresAt
    );

    event KYCRejected(
        address indexed user,
        address indexed verifier,
        string reason,
        uint256 timestamp
    );

    event KYCExpired(
        address indexed user,
        KYCTier previousTier,
        uint256 timestamp
    );

    event KYCRevoked(
        address indexed user,
        KYCTier previousTier,
        address indexed revoker,
        string reason,
        uint256 timestamp
    );

    event TierLimitsUpdated(
        KYCTier tier,
        uint256 dailyDepositLimit,
        uint256 dailyWithdrawLimit,
        uint256 monthlyVolumeLimit
    );

    event KYCFeeUpdated(
        uint256 oldFee,
        uint256 newFee,
        uint256 timestamp
    );

    event VolumeRecorded(
        address indexed user,
        uint256 amount,
        string operationType,
        uint256 timestamp
    );
    
    event FeesWithdrawn(
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );
    
    event EmergencyWithdraw(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    // ============================================
    // Errors
    // ============================================
    error InvalidTier();
    error KYCAlreadySubmitted();
    error KYCNotPending();
    error InsufficientKYCFee();
    error CooldownPeriodActive();
    error DailyDepositLimitExceeded();
    error DailyWithdrawLimitExceeded();
    error MonthlyVolumeLimitExceeded();
    error KYCRequired();
    error KYCExpiredError(); // Renamed to avoid conflict with event
    error InvalidDocumentHash();
    error CannotDowngradeTier();

    // ============================================
    // Constructor
    // ============================================
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KYC_VERIFIER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        // Configurar límites por tier
        _setTierLimits(
            KYCTier.TIER_0,
            1_000 * 10**18,      // $1,000 USD diario deposit
            1_000 * 10**18,      // $1,000 USD diario withdraw
            5_000 * 10**18,      // $5,000 USD mensual
            false,               // No requiere KYC
            false,               // No puede ser intermediario
            true                 // Puede crear ofertas limitadas
        );

        _setTierLimits(
            KYCTier.TIER_1,
            10_000 * 10**18,     // $10,000 USD diario deposit
            10_000 * 10**18,     // $10,000 USD diario withdraw
            100_000 * 10**18,    // $100,000 USD mensual
            true,                // Requiere KYC
            false,               // No puede ser intermediario
            true                 // Puede crear ofertas
        );

        _setTierLimits(
            KYCTier.TIER_2,
            type(uint256).max,   // Sin límite deposit
            type(uint256).max,   // Sin límite withdraw
            type(uint256).max,   // Sin límite mensual
            true,                // Requiere KYC
            true,                // Puede ser intermediario
            true                 // Puede crear ofertas
        );

        kycFee = 0.01 ether;  // 0.01 BNB por defecto
    }

    // ============================================
    // Funciones Públicas
    // ============================================

    /**
     * @notice Usuario envía documentos KYC
     * @param documentHash Hash IPFS de documentos cifrados
     * @param requestedTier Tier solicitado (1 o 2)
     */
    function submitKYC(
        string calldata documentHash,
        KYCTier requestedTier
    ) external payable nonReentrant whenNotPaused {
        if (requestedTier == KYCTier.TIER_0) revert InvalidTier();
        if (bytes(documentHash).length == 0) revert InvalidDocumentHash();
        if (msg.value < kycFee) revert InsufficientKYCFee();

        KYCData storage data = kycData[msg.sender];

        // Si ya tiene KYC pendiente, verificar cooldown
        if (data.status == KYCStatus.PENDING) {
            revert KYCAlreadySubmitted();
        }

        // Si fue rechazado, verificar cooldown
        if (data.status == KYCStatus.REJECTED) {
            if (block.timestamp < data.submittedAt + RESUBMISSION_COOLDOWN) {
                revert CooldownPeriodActive();
            }
            data.resubmissionCount++;
        }

        // Registrar submission
        data.user = msg.sender;
        data.status = KYCStatus.PENDING;
        data.tier = requestedTier;
        data.submittedAt = block.timestamp;
        data.documentHash = documentHash;
        data.rejectionReason = "";
        data.verifier = address(0);

        totalKYCSubmitted++;

        emit KYCSubmitted(msg.sender, requestedTier, documentHash, block.timestamp);
    }

    /**
     * @notice Verifier aprueba KYC
     * @param user Usuario a aprobar
     * @param approvedTier Tier aprobado (puede ser menor al solicitado)
     */
    function approveKYC(
        address user,
        KYCTier approvedTier
    ) external onlyRole(KYC_VERIFIER_ROLE) whenNotPaused {
        if (approvedTier == KYCTier.TIER_0) revert InvalidTier();

        KYCData storage data = kycData[user];
        if (data.status != KYCStatus.PENDING) revert KYCNotPending();

        // Actualizar datos
        KYCTier previousTier = data.tier;
        data.status = KYCStatus.APPROVED;
        data.tier = approvedTier;
        data.approvedAt = block.timestamp;
        data.expiresAt = block.timestamp + KYC_VALIDITY_PERIOD;
        data.verifier = msg.sender;

        // Actualizar índices de tier
        _updateUserTier(user, previousTier, approvedTier);

        totalKYCApproved++;

        emit KYCApproved(user, approvedTier, msg.sender, block.timestamp, data.expiresAt);
    }

    /**
     * @notice Verifier rechaza KYC
     * @param user Usuario a rechazar
     * @param reason Razón del rechazo
     */
    function rejectKYC(
        address user,
        string calldata reason
    ) external onlyRole(KYC_VERIFIER_ROLE) whenNotPaused {
        KYCData storage data = kycData[user];
        if (data.status != KYCStatus.PENDING) revert KYCNotPending();

        data.status = KYCStatus.REJECTED;
        data.rejectionReason = reason;
        data.verifier = msg.sender;
        data.tier = KYCTier.TIER_0;  // Vuelve a Tier 0

        totalKYCRejected++;

        emit KYCRejected(user, msg.sender, reason, block.timestamp);
    }

    /**
     * @notice Revoca KYC de un usuario (por violaciones)
     * @param user Usuario a revocar
     * @param reason Razón de la revocación
     */
    function revokeKYC(
        address user,
        string calldata reason
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        KYCData storage data = kycData[user];
        if (data.status != KYCStatus.APPROVED) return;

        KYCTier previousTier = data.tier;
        data.status = KYCStatus.REJECTED;
        data.tier = KYCTier.TIER_0;
        data.rejectionReason = reason;

        // Actualizar índices
        _updateUserTier(user, previousTier, KYCTier.TIER_0);

        emit KYCRevoked(user, previousTier, msg.sender, reason, block.timestamp);
    }

    /**
     * @notice Marca KYC como expirado (llamado por keeper o cualquiera)
     * @param user Usuario con KYC expirado
     */
    function markKYCExpired(address user) external {
        KYCData storage data = kycData[user];
        
        if (data.status == KYCStatus.APPROVED && block.timestamp >= data.expiresAt) {
            KYCTier previousTier = data.tier;
            data.status = KYCStatus.EXPIRED;
            data.tier = KYCTier.TIER_0;

            // Actualizar índices
            _updateUserTier(user, previousTier, KYCTier.TIER_0);

            emit KYCExpired(user, previousTier, block.timestamp);
        }
    }

    /**
     * @notice Registra depósito para límites
     * @param user Usuario que deposita
     * @param amountUSD Monto en USD (18 decimales)
     */
    function recordDeposit(
        address user,
        uint256 amountUSD
    ) external onlyRole(OPERATOR_ROLE) {
        _checkAndUpdateDeposit(user, amountUSD);
        
        emit VolumeRecorded(user, amountUSD, "DEPOSIT", block.timestamp);
    }

    /**
     * @notice Registra retiro para límites
     * @param user Usuario que retira
     * @param amountUSD Monto en USD (18 decimales)
     */
    function recordWithdraw(
        address user,
        uint256 amountUSD
    ) external onlyRole(OPERATOR_ROLE) {
        _checkAndUpdateWithdraw(user, amountUSD);
        
        emit VolumeRecorded(user, amountUSD, "WITHDRAW", block.timestamp);
    }

    // ============================================
    // Funciones de Vista
    // ============================================

    /**
     * @notice Verifica si usuario está verificado
     * @param user Dirección del usuario
     * @return bool True si está verificado y no expirado
     */
    function isVerified(address user) external view returns (bool) {
        KYCData memory data = kycData[user];
        return data.status == KYCStatus.APPROVED && block.timestamp < data.expiresAt;
    }

    /**
     * @notice Obtiene tier del usuario
     * @param user Dirección del usuario
     * @return KYCTier Tier actual
     */
    function getTier(address user) external view returns (KYCTier) {
        KYCData memory data = kycData[user];
        
        // Si expiró, retorna Tier 0
        if (data.status == KYCStatus.APPROVED && block.timestamp >= data.expiresAt) {
            return KYCTier.TIER_0;
        }
        
        return data.tier;
    }

    /**
     * @notice Obtiene límites del tier
     * @param tier Tier a consultar
     * @return TierLimits Límites del tier
     */
    function getTierLimits(KYCTier tier) external view returns (TierLimits memory) {
        return tierLimits[tier];
    }

    /**
     * @notice Verifica si usuario puede depositar monto
     * @param user Usuario
     * @param amountUSD Monto en USD
     * @return bool True si puede depositar
     */
    function canDeposit(address user, uint256 amountUSD) external view returns (bool) {
        KYCData memory data = kycData[user];
        TierLimits memory limits = tierLimits[data.tier];
        
        uint256 today = block.timestamp / 1 days;
        uint256 dailyTotal = dailyDeposits[user][today] + amountUSD;
        
        return dailyTotal <= limits.dailyDepositLimit;
    }

    /**
     * @notice Verifica si usuario puede retirar monto
     * @param user Usuario
     * @param amountUSD Monto en USD
     * @return bool True si puede retirar
     */
    function canWithdraw(address user, uint256 amountUSD) external view returns (bool) {
        KYCData memory data = kycData[user];
        TierLimits memory limits = tierLimits[data.tier];
        
        uint256 today = block.timestamp / 1 days;
        uint256 dailyTotal = dailyWithdraws[user][today] + amountUSD;
        
        return dailyTotal <= limits.dailyWithdrawLimit;
    }

    /**
     * @notice Obtiene volumen restante para el mes
     * @param user Usuario
     * @return uint256 Volumen disponible en USD
     */
    function getRemainingMonthlyVolume(address user) external view returns (uint256) {
        KYCData memory data = kycData[user];
        TierLimits memory limits = tierLimits[data.tier];
        
        uint256 currentMonth = block.timestamp / 30 days;
        uint256 used = monthlyVolume[user][currentMonth];
        
        if (used >= limits.monthlyVolumeLimit) return 0;
        return limits.monthlyVolumeLimit - used;
    }

    /**
     * @notice Obtiene datos completos de KYC
     * @param user Usuario
     * @return KYCData Datos completos
     */
    function getKYCData(address user) external view returns (KYCData memory) {
        return kycData[user];
    }

    /**
     * @notice Obtiene usuarios por tier
     * @param tier Tier a consultar
     * @return address[] Lista de usuarios
     */
    function getUsersByTier(KYCTier tier) external view returns (address[] memory) {
        return usersByTier[tier];
    }

    /**
     * @notice Cuenta usuarios por tier
     * @param tier Tier a consultar
     * @return uint256 Cantidad de usuarios
     */
    function getUserCountByTier(KYCTier tier) external view returns (uint256) {
        return usersByTier[tier].length;
    }

    // ============================================
    // Funciones Internas
    // ============================================

    /**
     * @notice Verifica y actualiza depósito
     */
    function _checkAndUpdateDeposit(address user, uint256 amountUSD) internal {
        KYCData memory data = kycData[user];
        TierLimits memory limits = tierLimits[data.tier];
        
        uint256 today = block.timestamp / 1 days;
        uint256 currentMonth = block.timestamp / 30 days;
        
        // Verificar límite diario
        uint256 newDailyTotal = dailyDeposits[user][today] + amountUSD;
        if (newDailyTotal > limits.dailyDepositLimit) {
            revert DailyDepositLimitExceeded();
        }
        
        // Verificar límite mensual
        uint256 newMonthlyTotal = monthlyVolume[user][currentMonth] + amountUSD;
        if (newMonthlyTotal > limits.monthlyVolumeLimit) {
            revert MonthlyVolumeLimitExceeded();
        }
        
        // Actualizar
        dailyDeposits[user][today] = newDailyTotal;
        monthlyVolume[user][currentMonth] = newMonthlyTotal;
    }

    /**
     * @notice Verifica y actualiza retiro
     */
    function _checkAndUpdateWithdraw(address user, uint256 amountUSD) internal {
        KYCData memory data = kycData[user];
        TierLimits memory limits = tierLimits[data.tier];
        
        uint256 today = block.timestamp / 1 days;
        uint256 currentMonth = block.timestamp / 30 days;
        
        // Verificar límite diario
        uint256 newDailyTotal = dailyWithdraws[user][today] + amountUSD;
        if (newDailyTotal > limits.dailyWithdrawLimit) {
            revert DailyWithdrawLimitExceeded();
        }
        
        // Verificar límite mensual
        uint256 newMonthlyTotal = monthlyVolume[user][currentMonth] + amountUSD;
        if (newMonthlyTotal > limits.monthlyVolumeLimit) {
            revert MonthlyVolumeLimitExceeded();
        }
        
        // Actualizar
        dailyWithdraws[user][today] = newDailyTotal;
        monthlyVolume[user][currentMonth] = newMonthlyTotal;
    }

    /**
     * @notice Actualiza tier del usuario en índices
     */
    function _updateUserTier(address user, KYCTier oldTier, KYCTier newTier) internal {
        if (oldTier == newTier) return;

        // Remover del tier anterior
        if (oldTier != KYCTier.TIER_0) {
            uint256 index = userTierIndex[user];
            uint256 lastIndex = usersByTier[oldTier].length - 1;
            
            if (index != lastIndex) {
                address lastUser = usersByTier[oldTier][lastIndex];
                usersByTier[oldTier][index] = lastUser;
                userTierIndex[lastUser] = index;
            }
            
            usersByTier[oldTier].pop();
        }

        // Agregar al nuevo tier
        userTierIndex[user] = usersByTier[newTier].length;
        usersByTier[newTier].push(user);
    }

    /**
     * @notice Configura límites de tier
     */
    function _setTierLimits(
        KYCTier tier,
        uint256 dailyDepositLimit,
        uint256 dailyWithdrawLimit,
        uint256 monthlyVolumeLimit,
        bool requiresKYC,
        bool canBeIntermediary,
        bool canCreateOffers
    ) internal {
        tierLimits[tier] = TierLimits({
            dailyDepositLimit: dailyDepositLimit,
            dailyWithdrawLimit: dailyWithdrawLimit,
            monthlyVolumeLimit: monthlyVolumeLimit,
            requiresKYC: requiresKYC,
            canBeIntermediary: canBeIntermediary,
            canCreateOffers: canCreateOffers
        });
    }

    // ============================================
    // Funciones de Admin
    // ============================================

    /**
     * @notice Actualiza límites de un tier
     */
    function updateTierLimits(
        KYCTier tier,
        uint256 dailyDepositLimit,
        uint256 dailyWithdrawLimit,
        uint256 monthlyVolumeLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tierLimits[tier].dailyDepositLimit = dailyDepositLimit;
        tierLimits[tier].dailyWithdrawLimit = dailyWithdrawLimit;
        tierLimits[tier].monthlyVolumeLimit = monthlyVolumeLimit;

        emit TierLimitsUpdated(tier, dailyDepositLimit, dailyWithdrawLimit, monthlyVolumeLimit);
    }

    /**
     * @notice Actualiza fee de KYC
     */
    function updateKYCFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldFee = kycFee;
        kycFee = newFee;

        emit KYCFeeUpdated(oldFee, newFee, block.timestamp);
    }

    /**
     * @notice Retira fees acumulados
     * @dev FIXED: Implementa Checks-Effects-Interactions pattern
     */
    function withdrawFees(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        // CHECKS
        require(recipient != address(0), "Zero address");
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        // EFFECTS: Registrar antes de transferir
        emit FeesWithdrawn(recipient, balance, block.timestamp);
        
        // INTERACTIONS: Transferir al final con límite de gas
        (bool success, ) = recipient.call{value: balance, gas: 50000}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @notice Emergency function para recuperar tokens ERC20 atascados
     * @dev Solo admin puede recuperar tokens accidentalmente enviados
     */
    function emergencyWithdrawToken(
        address token,
        address recipient,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(recipient != address(0), "Zero address");
        require(token != address(0), "Zero token");
        require(amount > 0, "Zero amount");
        
        IERC20(token).safeTransfer(recipient, amount);
        emit EmergencyWithdraw(token, recipient, amount);
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
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Recibe BNB para fees
     */
    receive() external payable {}
}
