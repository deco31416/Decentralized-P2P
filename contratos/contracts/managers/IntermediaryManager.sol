// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IntermediaryManager
 * @notice Gestor centralizado de validadores e intermediarios para todos los bridges
 * @dev Sistema unificado de gestión de participantes del ecosistema
 * 
 * Características principales:
 * - Registro y gestión de validadores (10k CAMBIO mínimo)
 * - Registro y gestión de intermediarios (50k CAMBIO mínimo)
 * - Sistema de reputación unificado (0-100)
 * - Slashing por comportamiento malicioso
 * - KYC/Verificación opcional por tiers
 * - Performance tracking y métricas
 * - Historial completo de operaciones
 * - Sistema de appeals para slashing
 * - Rewards automáticos por buen desempeño
 * - Activación/desactivación dinámica
 * 
 * Roles:
 * - Validator: Valida transacciones crypto-fiat (10k CAMBIO)
 * - Intermediary: Facilita trades fiat-fiat (50k CAMBIO + collateral)
 * 
 * Tiers de verificación:
 * - Tier 0: Sin verificación (límite bajo)
 * - Tier 1: KYC básico (límite medio)
 * - Tier 2: KYC completo + auditoría (sin límites)
 * 
 * Sistema de reputación:
 * - Inicia en 100
 * - +1 por operación exitosa
 * - -5 por timeout
 * - -10 por disputa menor
 * - -20 por disputa mayor
 * - -50 por fraude confirmado
 */
contract IntermediaryManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Rol de validator
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    
    /// @notice Rol de intermediario
    bytes32 public constant INTERMEDIARY_ROLE = keccak256("INTERMEDIARY_ROLE");

    /// @notice Estados de un participante
    enum ParticipantStatus {
        Inactive,           // No registrado o desactivado
        Active,             // Activo y operando
        Suspended,          // Suspendido temporalmente
        UnderReview,        // Bajo revisión por disputa
        Banned,             // Baneado permanentemente
        PendingWithdrawal   // Esperando retiro de stake
    }

    /// @notice Tipos de participantes
    enum ParticipantType {
        Validator,
        Intermediary,
        Both    // Puede actuar como ambos
    }

    /// @notice Tiers de verificación
    enum VerificationTier {
        Tier0,  // Sin verificación - límite 1k USD
        Tier1,  // KYC básico - límite 10k USD
        Tier2   // KYC completo - sin límites
    }

    /// @notice Tipos de penalización
    enum SlashingReason {
        Timeout,            // -5 reputación, 5% stake
        MinorDispute,       // -10 reputación, 10% stake
        MajorDispute,       // -20 reputación, 15% stake
        Fraud,              // -50 reputación, 30% stake
        CollateralFailure,  // -15 reputación, 20% stake
        ManualSlashing      // Admin override
    }

    /// @notice Información completa de participante
    struct Participant {
        address account;
        ParticipantType participantType;
        ParticipantStatus status;
        VerificationTier tier;
        
        // Stakes
        uint256 validatorStake;
        uint256 intermediaryStake;
        uint256 totalStake;
        
        // Performance
        uint256 totalOperations;
        uint256 successfulOperations;
        uint256 disputedOperations;
        uint256 timeoutOperations;
        uint256 totalVolume;        // En USD
        
        // Reputación
        uint256 reputation;         // 0-100
        uint256 baseReputation;     // Inicial
        uint256 lastReputationUpdate;
        
        // Slashing
        uint256 totalSlashed;
        uint256 slashingEvents;
        uint256 lastSlashingTime;
        
        // Rewards
        uint256 totalRewards;
        uint256 pendingRewards;
        uint256 lastRewardClaim;
        
        // Configuración
        string[] supportedFiatCurrencies;
        string[] supportedRegions;
        uint256 maxOperationAmount;
        uint256 dailyOperationLimit;
        uint256 dailyOperationCount;
        uint256 lastOperationDate;
        
        // Metadata
        string kycHash;             // Hash de documentos KYC
        string contactInfo;         // Info de contacto encriptada
        uint256 registeredAt;
        uint256 lastActiveAt;
        bool acceptsNewOperations;
    }

    /// @notice Historial de operación
    struct OperationRecord {
        uint256 operationId;
        address participant;
        address bridge;             // Bridge que registró la operación
        uint256 amount;             // En USD
        bool successful;
        uint256 timestamp;
        string operationType;       // "crypto-fiat", "fiat-crypto", "fiat-fiat"
    }

    /// @notice Registro de slashing
    struct SlashingRecord {
        uint256 slashingId;
        address participant;
        SlashingReason reason;
        uint256 amountSlashed;
        uint256 reputationLost;
        string details;
        address initiator;
        uint256 timestamp;
        bool appealed;
        bool appealApproved;
    }

    /// @notice Solicitud de appeal
    struct AppealRequest {
        uint256 appealId;
        uint256 slashingId;
        address appellant;
        string reason;
        string evidence;
        uint256 requestedAt;
        uint256 reviewedAt;
        address reviewer;
        bool approved;
        string reviewNotes;
    }

    /// @notice Mapeo de participantes
    mapping(address => Participant) public participants;
    
    /// @notice Lista de validadores activos
    address[] public activeValidators;
    
    /// @notice Lista de intermediarios activos
    address[] public activeIntermediaries;
    
    /// @notice Historial de operaciones
    mapping(uint256 => OperationRecord) public operationRecords;
    uint256 public operationCount;
    
    /// @notice Operaciones por participante
    mapping(address => uint256[]) public participantOperations;
    
    /// @notice Historial de slashing
    mapping(uint256 => SlashingRecord) public slashingRecords;
    uint256 public slashingCount;
    
    /// @notice Slashings por participante
    mapping(address => uint256[]) public participantSlashings;
    
    /// @notice Appeals
    mapping(uint256 => AppealRequest) public appeals;
    uint256 public appealCount;
    
    /// @notice Bridges autorizados
    mapping(address => bool) public authorizedBridges;

    /// @notice Stakes mínimos
    uint256 public minValidatorStake = 10000 * 10**18;      // 10k CAMBIO
    uint256 public minIntermediaryStake = 50000 * 10**18;   // 50k CAMBIO
    
    /// @notice Límites por tier
    uint256 public tier0Limit = 1000 * 10**18;      // 1k USD
    uint256 public tier1Limit = 10000 * 10**18;     // 10k USD
    // Tier2 sin límite
    
    /// @notice Porcentajes de slashing por razón
    mapping(uint8 => uint256) public slashingPercentages;
    
    /// @notice Rewards por operación exitosa (0.1%)
    uint256 public rewardPercentage = 10; // basis points
    
    /// @notice Tiempo de cooldown para withdraw (7 días)
    uint256 public withdrawCooldown = 7 days;
    
    /// @notice Reputación mínima para operar
    uint256 public minReputationRequired = 50;

    /// @notice Referencia al token CAMBIO
    address public cambioToken;
    
    /// @notice Referencia al FeeManager
    address public feeManager;
    
    /// @notice Referencia al Treasury
    address public treasury;

    // ============================================
    // EVENTOS
    // ============================================

    event ParticipantRegistered(
        address indexed participant,
        ParticipantType participantType,
        uint256 stake
    );

    event StakeAdded(
        address indexed participant,
        uint256 amount,
        uint256 newTotal
    );

    event StakeWithdrawn(
        address indexed participant,
        uint256 amount,
        uint256 remaining
    );

    event OperationRecorded(
        uint256 indexed operationId,
        address indexed participant,
        bool successful,
        uint256 amount
    );

    event ReputationUpdated(
        address indexed participant,
        uint256 oldReputation,
        uint256 newReputation,
        string reason
    );

    event ParticipantSlashed(
        uint256 indexed slashingId,
        address indexed participant,
        SlashingReason reason,
        uint256 amount
    );

    event AppealSubmitted(
        uint256 indexed appealId,
        uint256 indexed slashingId,
        address indexed appellant
    );

    event AppealReviewed(
        uint256 indexed appealId,
        bool approved,
        address reviewer
    );

    event RewardsClaimed(
        address indexed participant,
        uint256 amount
    );

    event StatusChanged(
        address indexed participant,
        ParticipantStatus oldStatus,
        ParticipantStatus newStatus
    );

    event TierUpgraded(
        address indexed participant,
        VerificationTier oldTier,
        VerificationTier newTier
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _cambioToken,
        address _feeManager,
        address _treasury
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_cambioToken != address(0), "Invalid token");
        require(_feeManager != address(0), "Invalid fee manager");
        require(_treasury != address(0), "Invalid treasury");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        cambioToken = _cambioToken;
        feeManager = _feeManager;
        treasury = _treasury;

        // Configurar porcentajes de slashing
        slashingPercentages[uint8(SlashingReason.Timeout)] = 500;          // 5%
        slashingPercentages[uint8(SlashingReason.MinorDispute)] = 1000;    // 10%
        slashingPercentages[uint8(SlashingReason.MajorDispute)] = 1500;    // 15%
        slashingPercentages[uint8(SlashingReason.Fraud)] = 3000;           // 30%
        slashingPercentages[uint8(SlashingReason.CollateralFailure)] = 2000; // 20%
    }

    // ============================================
    // REGISTRO DE PARTICIPANTES
    // ============================================

    /**
     * @notice Registra un validator
     * @param stakeAmount Cantidad de CAMBIO a stakear
     * @param supportedCurrencies Monedas fiat soportadas
     * @param supportedRegions Regiones de operación
     * @param maxAmount Monto máximo por operación
     */
    function registerValidator(
        uint256 stakeAmount,
        string[] memory supportedCurrencies,
        string[] memory supportedRegions,
        uint256 maxAmount
    ) external nonReentrant whenNotPaused {
        require(stakeAmount >= minValidatorStake, "Insufficient stake");
        require(
            participants[msg.sender].status == ParticipantStatus.Inactive,
            "Already registered"
        );
        require(supportedCurrencies.length > 0, "No currencies");
        require(supportedRegions.length > 0, "No regions");
        require(maxAmount > 0, "Invalid max amount");

        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), stakeAmount);

        Participant storage participant = participants[msg.sender];
        participant.account = msg.sender;
        participant.participantType = ParticipantType.Validator;
        participant.status = ParticipantStatus.Active;
        participant.tier = VerificationTier.Tier0;
        participant.validatorStake = stakeAmount;
        participant.totalStake = stakeAmount;
        participant.reputation = 100;
        participant.baseReputation = 100;
        participant.lastReputationUpdate = block.timestamp;
        participant.maxOperationAmount = maxAmount;
        participant.dailyOperationLimit = 10;
        participant.registeredAt = block.timestamp;
        participant.lastActiveAt = block.timestamp;
        participant.acceptsNewOperations = true;

        for (uint256 i = 0; i < supportedCurrencies.length; i++) {
            participant.supportedFiatCurrencies.push(supportedCurrencies[i]);
        }

        for (uint256 i = 0; i < supportedRegions.length; i++) {
            participant.supportedRegions.push(supportedRegions[i]);
        }

        activeValidators.push(msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);

        emit ParticipantRegistered(msg.sender, ParticipantType.Validator, stakeAmount);
    }

    /**
     * @notice Registra un intermediary
     */
    function registerIntermediary(
        uint256 stakeAmount,
        string[] memory supportedCurrencies,
        string[] memory supportedRegions,
        uint256 maxAmount
    ) external nonReentrant whenNotPaused {
        require(stakeAmount >= minIntermediaryStake, "Insufficient stake");
        require(
            participants[msg.sender].status == ParticipantStatus.Inactive,
            "Already registered"
        );
        require(supportedCurrencies.length > 0, "No currencies");
        require(supportedRegions.length > 0, "No regions");
        require(maxAmount > 0, "Invalid max amount");

        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), stakeAmount);

        Participant storage participant = participants[msg.sender];
        participant.account = msg.sender;
        participant.participantType = ParticipantType.Intermediary;
        participant.status = ParticipantStatus.Active;
        participant.tier = VerificationTier.Tier0;
        participant.intermediaryStake = stakeAmount;
        participant.totalStake = stakeAmount;
        participant.reputation = 100;
        participant.baseReputation = 100;
        participant.lastReputationUpdate = block.timestamp;
        participant.maxOperationAmount = maxAmount;
        participant.dailyOperationLimit = 5;
        participant.registeredAt = block.timestamp;
        participant.lastActiveAt = block.timestamp;
        participant.acceptsNewOperations = true;

        for (uint256 i = 0; i < supportedCurrencies.length; i++) {
            participant.supportedFiatCurrencies.push(supportedCurrencies[i]);
        }

        for (uint256 i = 0; i < supportedRegions.length; i++) {
            participant.supportedRegions.push(supportedRegions[i]);
        }

        activeIntermediaries.push(msg.sender);
        _grantRole(INTERMEDIARY_ROLE, msg.sender);

        emit ParticipantRegistered(msg.sender, ParticipantType.Intermediary, stakeAmount);
    }

    /**
     * @notice Registra como ambos (validator + intermediary)
     */
    function registerBoth(
        uint256 validatorStakeAmount,
        uint256 intermediaryStakeAmount,
        string[] memory supportedCurrencies,
        string[] memory supportedRegions,
        uint256 maxAmount
    ) external nonReentrant whenNotPaused {
        require(validatorStakeAmount >= minValidatorStake, "Insufficient validator stake");
        require(intermediaryStakeAmount >= minIntermediaryStake, "Insufficient intermediary stake");
        require(
            participants[msg.sender].status == ParticipantStatus.Inactive,
            "Already registered"
        );

        uint256 totalStake = validatorStakeAmount + intermediaryStakeAmount;
        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), totalStake);

        Participant storage participant = participants[msg.sender];
        participant.account = msg.sender;
        participant.participantType = ParticipantType.Both;
        participant.status = ParticipantStatus.Active;
        participant.tier = VerificationTier.Tier0;
        participant.validatorStake = validatorStakeAmount;
        participant.intermediaryStake = intermediaryStakeAmount;
        participant.totalStake = totalStake;
        participant.reputation = 100;
        participant.baseReputation = 100;
        participant.lastReputationUpdate = block.timestamp;
        participant.maxOperationAmount = maxAmount;
        participant.dailyOperationLimit = 10;
        participant.registeredAt = block.timestamp;
        participant.lastActiveAt = block.timestamp;
        participant.acceptsNewOperations = true;

        for (uint256 i = 0; i < supportedCurrencies.length; i++) {
            participant.supportedFiatCurrencies.push(supportedCurrencies[i]);
        }

        for (uint256 i = 0; i < supportedRegions.length; i++) {
            participant.supportedRegions.push(supportedRegions[i]);
        }

        activeValidators.push(msg.sender);
        activeIntermediaries.push(msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);
        _grantRole(INTERMEDIARY_ROLE, msg.sender);

        emit ParticipantRegistered(msg.sender, ParticipantType.Both, totalStake);
    }

    // ============================================
    // GESTIÓN DE STAKE
    // ============================================

    /**
     * @notice Añade más stake
     */
    function addStake(uint256 amount, bool isValidator) external nonReentrant {
        Participant storage participant = participants[msg.sender];
        require(participant.status == ParticipantStatus.Active, "Not active");
        require(amount > 0, "Invalid amount");

        IERC20(cambioToken).safeTransferFrom(msg.sender, address(this), amount);

        if (isValidator) {
            participant.validatorStake += amount;
        } else {
            participant.intermediaryStake += amount;
        }
        participant.totalStake += amount;

        emit StakeAdded(msg.sender, amount, participant.totalStake);
    }

    /**
     * @notice Inicia proceso de retiro de stake
     */
    function initiateStakeWithdrawal(uint256 amount, bool isValidator) external nonReentrant {
        Participant storage participant = participants[msg.sender];
        require(participant.status == ParticipantStatus.Active, "Not active");
        require(amount > 0, "Invalid amount");

        uint256 currentStake = isValidator ? 
            participant.validatorStake : participant.intermediaryStake;
        require(amount <= currentStake, "Insufficient stake");

        uint256 minRequired = isValidator ? minValidatorStake : minIntermediaryStake;
        require(currentStake - amount >= minRequired, "Below minimum");

        participant.status = ParticipantStatus.PendingWithdrawal;
        participant.acceptsNewOperations = false;

        emit StatusChanged(msg.sender, ParticipantStatus.Active, ParticipantStatus.PendingWithdrawal);
    }

    /**
     * @notice Completa retiro de stake después del cooldown
     */
    function completeStakeWithdrawal(uint256 amount, bool isValidator) 
        external 
        nonReentrant 
    {
        Participant storage participant = participants[msg.sender];
        require(
            participant.status == ParticipantStatus.PendingWithdrawal,
            "Not pending withdrawal"
        );
        require(
            block.timestamp >= participant.lastActiveAt + withdrawCooldown,
            "Cooldown not met"
        );

        uint256 currentStake = isValidator ? 
            participant.validatorStake : participant.intermediaryStake;
        require(amount <= currentStake, "Insufficient stake");

        if (isValidator) {
            participant.validatorStake -= amount;
        } else {
            participant.intermediaryStake -= amount;
        }
        participant.totalStake -= amount;

        IERC20(cambioToken).safeTransfer(msg.sender, amount);

        participant.status = ParticipantStatus.Active;
        participant.acceptsNewOperations = true;

        emit StakeWithdrawn(msg.sender, amount, participant.totalStake);
    }

    // ============================================
    // REGISTRO DE OPERACIONES
    // ============================================

    /**
     * @notice Registra una operación (solo bridges autorizados)
     */
    function recordOperation(
        address participant,
        uint256 amountUSD,
        bool successful,
        string memory operationType
    ) external nonReentrant {
        require(authorizedBridges[msg.sender], "Not authorized bridge");
        require(participants[participant].status == ParticipantStatus.Active, "Not active");

        Participant storage p = participants[participant];
        
        // Verificar límites diarios
        if (block.timestamp > p.lastOperationDate + 1 days) {
            p.dailyOperationCount = 0;
            p.lastOperationDate = block.timestamp;
        }
        
        require(p.dailyOperationCount < p.dailyOperationLimit, "Daily limit reached");
        
        // Verificar límites por tier
        if (p.tier == VerificationTier.Tier0) {
            require(amountUSD <= tier0Limit, "Exceeds tier limit");
        } else if (p.tier == VerificationTier.Tier1) {
            require(amountUSD <= tier1Limit, "Exceeds tier limit");
        }

        operationCount++;
        
        OperationRecord storage record = operationRecords[operationCount];
        record.operationId = operationCount;
        record.participant = participant;
        record.bridge = msg.sender;
        record.amount = amountUSD;
        record.successful = successful;
        record.timestamp = block.timestamp;
        record.operationType = operationType;

        participantOperations[participant].push(operationCount);

        p.totalOperations++;
        p.dailyOperationCount++;
        p.totalVolume += amountUSD;
        p.lastActiveAt = block.timestamp;

        if (successful) {
            p.successfulOperations++;
            _updateReputation(participant, 1, "Successful operation");
            _accumulateRewards(participant, amountUSD);
        } else {
            p.disputedOperations++;
        }

        emit OperationRecorded(operationCount, participant, successful, amountUSD);
    }

    /**
     * @notice Registra timeout de operación
     */
    function recordTimeout(address participant) external {
        require(authorizedBridges[msg.sender], "Not authorized bridge");
        
        Participant storage p = participants[participant];
        p.timeoutOperations++;
        
        _updateReputation(participant, -5, "Operation timeout");
        _applySlashing(participant, SlashingReason.Timeout, "Operation timeout");
    }

    // ============================================
    // SISTEMA DE REPUTACIÓN
    // ============================================

    /**
     * @notice Actualiza reputación
     */
    function _updateReputation(
        address participant,
        int256 change,
        string memory reason
    ) internal {
        Participant storage p = participants[participant];
        uint256 oldReputation = p.reputation;

        if (change > 0) {
            p.reputation = p.reputation + uint256(change);
            if (p.reputation > 100) p.reputation = 100;
        } else if (change < 0) {
            uint256 decrease = uint256(-change);
            p.reputation = p.reputation > decrease ? p.reputation - decrease : 0;
        }

        p.lastReputationUpdate = block.timestamp;

        emit ReputationUpdated(participant, oldReputation, p.reputation, reason);

        // Suspender si reputación muy baja
        if (p.reputation < minReputationRequired && p.status == ParticipantStatus.Active) {
            p.status = ParticipantStatus.Suspended;
            p.acceptsNewOperations = false;
            emit StatusChanged(participant, ParticipantStatus.Active, ParticipantStatus.Suspended);
        }
    }

    /**
     * @notice Actualiza reputación manualmente (admin)
     */
    function updateReputationManual(
        address participant,
        int256 change,
        string memory reason
    ) external onlyRole(ADMIN_ROLE) {
        _updateReputation(participant, change, reason);
    }

    // ============================================
    // SISTEMA DE SLASHING
    // ============================================

    /**
     * @notice Aplica slashing
     */
    function _applySlashing(
        address participant,
        SlashingReason reason,
        string memory details
    ) internal {
        Participant storage p = participants[participant];
        
        uint256 slashPercentage = slashingPercentages[uint8(reason)];
        uint256 slashAmount = (p.totalStake * slashPercentage) / 10000;
        
        if (slashAmount > p.totalStake) {
            slashAmount = p.totalStake;
        }

        p.totalStake -= slashAmount;
        p.totalSlashed += slashAmount;
        p.slashingEvents++;
        p.lastSlashingTime = block.timestamp;

        // Distribuir proporcionalmente entre validator/intermediary stake
        if (p.validatorStake > 0 && p.intermediaryStake > 0) {
            uint256 validatorSlash = (slashAmount * p.validatorStake) / (p.validatorStake + p.intermediaryStake);
            uint256 intermediarySlash = slashAmount - validatorSlash;
            p.validatorStake -= validatorSlash;
            p.intermediaryStake -= intermediarySlash;
        } else if (p.validatorStake > 0) {
            p.validatorStake -= slashAmount;
        } else {
            p.intermediaryStake -= slashAmount;
        }

        // Transferir al treasury
        IERC20(cambioToken).safeTransfer(treasury, slashAmount);

        slashingCount++;
        SlashingRecord storage record = slashingRecords[slashingCount];
        record.slashingId = slashingCount;
        record.participant = participant;
        record.reason = reason;
        record.amountSlashed = slashAmount;
        record.details = details;
        record.initiator = msg.sender;
        record.timestamp = block.timestamp;

        participantSlashings[participant].push(slashingCount);

        emit ParticipantSlashed(slashingCount, participant, reason, slashAmount);

        // Suspender si stake cae por debajo del mínimo
        uint256 minRequired = p.participantType == ParticipantType.Validator ? 
            minValidatorStake : 
            (p.participantType == ParticipantType.Intermediary ? 
                minIntermediaryStake : 
                minValidatorStake + minIntermediaryStake);

        if (p.totalStake < minRequired) {
            p.status = ParticipantStatus.Suspended;
            p.acceptsNewOperations = false;
        }
    }

    /**
     * @notice Slashing manual (admin)
     */
    function applyManualSlashing(
        address participant,
        uint256 amount,
        string memory details
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        Participant storage p = participants[participant];
        require(amount <= p.totalStake, "Exceeds stake");

        p.totalStake -= amount;
        p.totalSlashed += amount;
        p.slashingEvents++;

        IERC20(cambioToken).safeTransfer(treasury, amount);

        slashingCount++;
        SlashingRecord storage record = slashingRecords[slashingCount];
        record.slashingId = slashingCount;
        record.participant = participant;
        record.reason = SlashingReason.ManualSlashing;
        record.amountSlashed = amount;
        record.details = details;
        record.initiator = msg.sender;
        record.timestamp = block.timestamp;

        participantSlashings[participant].push(slashingCount);

        emit ParticipantSlashed(slashingCount, participant, SlashingReason.ManualSlashing, amount);
    }

    // ============================================
    // SISTEMA DE APPEALS
    // ============================================

    /**
     * @notice Envía appeal contra slashing
     */
    function submitAppeal(
        uint256 slashingId,
        string memory reason,
        string memory evidence
    ) external nonReentrant {
        SlashingRecord storage slashing = slashingRecords[slashingId];
        require(slashing.participant == msg.sender, "Not your slashing");
        require(!slashing.appealed, "Already appealed");
        require(bytes(reason).length > 0, "Reason required");

        slashing.appealed = true;

        appealCount++;
        AppealRequest storage appeal = appeals[appealCount];
        appeal.appealId = appealCount;
        appeal.slashingId = slashingId;
        appeal.appellant = msg.sender;
        appeal.reason = reason;
        appeal.evidence = evidence;
        appeal.requestedAt = block.timestamp;

        emit AppealSubmitted(appealCount, slashingId, msg.sender);
    }

    /**
     * @notice Revisa un appeal
     */
    function reviewAppeal(
        uint256 appealId,
        bool approved,
        string memory reviewNotes
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        AppealRequest storage appeal = appeals[appealId];
        require(appeal.reviewedAt == 0, "Already reviewed");

        appeal.approved = approved;
        appeal.reviewedAt = block.timestamp;
        appeal.reviewer = msg.sender;
        appeal.reviewNotes = reviewNotes;

        SlashingRecord storage slashing = slashingRecords[appeal.slashingId];
        slashing.appealApproved = approved;

        if (approved) {
            // Devolver stake slasheado
            Participant storage p = participants[appeal.appellant];
            uint256 refundAmount = slashing.amountSlashed;
            
            IERC20(cambioToken).safeTransferFrom(treasury, address(this), refundAmount);
            
            p.totalStake += refundAmount;
            p.totalSlashed -= refundAmount;
            
            // Restaurar reputación
            if (p.reputation < 100) {
                p.reputation = p.baseReputation;
            }
        }

        emit AppealReviewed(appealId, approved, msg.sender);
    }

    // ============================================
    // SISTEMA DE REWARDS
    // ============================================

    /**
     * @notice Acumula rewards por operación exitosa
     */
    function _accumulateRewards(address participant, uint256 operationAmount) internal {
        Participant storage p = participants[participant];
        uint256 reward = (operationAmount * rewardPercentage) / 10000;
        
        p.pendingRewards += reward;
        p.totalRewards += reward;
    }

    /**
     * @notice Reclama rewards pendientes
     */
    function claimRewards() external nonReentrant {
        Participant storage p = participants[msg.sender];
        require(p.pendingRewards > 0, "No rewards");
        require(p.status == ParticipantStatus.Active, "Not active");

        uint256 rewards = p.pendingRewards;
        p.pendingRewards = 0;
        p.lastRewardClaim = block.timestamp;

        IERC20(cambioToken).safeTransferFrom(feeManager, msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    // ============================================
    // VERIFICACIÓN Y TIERS
    // ============================================

    /**
     * @notice Actualiza tier de verificación
     */
    function upgradeTier(
        address participant,
        VerificationTier newTier,
        string memory kycHash
    ) external onlyRole(ADMIN_ROLE) {
        Participant storage p = participants[participant];
        require(uint8(newTier) > uint8(p.tier), "Not an upgrade");

        VerificationTier oldTier = p.tier;
        p.tier = newTier;
        p.kycHash = kycHash;

        // Aumentar límites según tier
        if (newTier == VerificationTier.Tier1) {
            p.dailyOperationLimit = 20;
        } else if (newTier == VerificationTier.Tier2) {
            p.dailyOperationLimit = 100;
        }

        emit TierUpgraded(participant, oldTier, newTier);
    }

    // ============================================
    // GESTIÓN DE ESTADO
    // ============================================

    /**
     * @notice Suspende participante
     */
    function suspendParticipant(address participant, string memory /* reason */) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        Participant storage p = participants[participant];
        require(p.status == ParticipantStatus.Active, "Not active");

        p.status = ParticipantStatus.Suspended;
        p.acceptsNewOperations = false;

        emit StatusChanged(participant, ParticipantStatus.Active, ParticipantStatus.Suspended);
    }

    /**
     * @notice Reactiva participante
     */
    function reactivateParticipant(address participant) external onlyRole(ADMIN_ROLE) {
        Participant storage p = participants[participant];
        require(p.status == ParticipantStatus.Suspended, "Not suspended");
        require(p.reputation >= minReputationRequired, "Low reputation");

        p.status = ParticipantStatus.Active;
        p.acceptsNewOperations = true;

        emit StatusChanged(participant, ParticipantStatus.Suspended, ParticipantStatus.Active);
    }

    /**
     * @notice Banea participante permanentemente
     */
    function banParticipant(address participant, string memory /* reason */) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        Participant storage p = participants[participant];
        
        ParticipantStatus oldStatus = p.status;
        p.status = ParticipantStatus.Banned;
        p.acceptsNewOperations = false;

        emit StatusChanged(participant, oldStatus, ParticipantStatus.Banned);
    }

    // ============================================
    // CONFIGURACIÓN
    // ============================================

    function authorizeBridge(address bridge) external onlyRole(ADMIN_ROLE) {
        authorizedBridges[bridge] = true;
    }

    function deauthorizeBridge(address bridge) external onlyRole(ADMIN_ROLE) {
        authorizedBridges[bridge] = false;
    }

    function setMinValidatorStake(uint256 amount) external onlyRole(ADMIN_ROLE) {
        minValidatorStake = amount;
    }

    function setMinIntermediaryStake(uint256 amount) external onlyRole(ADMIN_ROLE) {
        minIntermediaryStake = amount;
    }

    function setSlashingPercentage(SlashingReason reason, uint256 percentage) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(percentage <= 5000, "Too high");
        slashingPercentages[uint8(reason)] = percentage;
    }

    function setRewardPercentage(uint256 percentage) external onlyRole(ADMIN_ROLE) {
        require(percentage <= 100, "Too high");
        rewardPercentage = percentage;
    }

    function setMinReputationRequired(uint256 reputation) external onlyRole(ADMIN_ROLE) {
        require(reputation <= 100, "Invalid reputation");
        minReputationRequired = reputation;
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

    function getParticipant(address account) 
        external 
        view 
        returns (Participant memory) 
    {
        return participants[account];
    }

    function getOperationRecord(uint256 operationId) 
        external 
        view 
        returns (OperationRecord memory) 
    {
        return operationRecords[operationId];
    }

    function getSlashingRecord(uint256 slashingId) 
        external 
        view 
        returns (SlashingRecord memory) 
    {
        return slashingRecords[slashingId];
    }

    function getAppeal(uint256 appealId) 
        external 
        view 
        returns (AppealRequest memory) 
    {
        return appeals[appealId];
    }

    function getParticipantOperations(address participant) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return participantOperations[participant];
    }

    function getParticipantSlashings(address participant) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return participantSlashings[participant];
    }

    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }

    function getActiveIntermediaries() external view returns (address[] memory) {
        return activeIntermediaries;
    }

    function isParticipantActive(address participant) external view returns (bool) {
        return participants[participant].status == ParticipantStatus.Active &&
               participants[participant].acceptsNewOperations &&
               participants[participant].reputation >= minReputationRequired;
    }

    function getParticipantStats(address participant) 
        external 
        view 
        returns (
            uint256 totalOps,
            uint256 successRate,
            uint256 reputation,
            uint256 totalVolume
        ) 
    {
        Participant storage p = participants[participant];
        uint256 rate = p.totalOperations > 0 ? 
            (p.successfulOperations * 100) / p.totalOperations : 0;
        
        return (
            p.totalOperations,
            rate,
            p.reputation,
            p.totalVolume
        );
    }
}
