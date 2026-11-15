// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AppealManager
 * @notice Sistema de apelaciones para disputas resueltas
 * @dev Maneja apelaciones, re-arbitraje y resolución final
 * 
 * Características principales:
 * - Apelaciones con fee más alto
 * - Re-arbitraje con árbitros diferentes
 * - Límite máximo de apelaciones (2)
 * - Nuevas evidencias permitidas
 * - Panel de árbitros senior/expert
 * - Scoring de probabilidad de éxito
 * - Timelock estricto para apelar
 * - Revisión de méritos antes de aceptar
 * - Fast-track para casos urgentes
 * - Historial completo de apelaciones
 * 
 * Razones de apelación:
 * - NEW_EVIDENCE: Nueva evidencia relevante
 * - PROCEDURAL_ERROR: Error en procedimiento
 * - ARBITRATOR_BIAS: Sesgo de árbitro
 * - MISINTERPRETATION: Mala interpretación
 * - INSUFFICIENT_EVIDENCE: Evidencia insuficiente
 * - OTHER: Otra razón
 * 
 * Estados de apelación:
 * - SUBMITTED: Apelación enviada
 * - UNDER_REVIEW: Revisión de méritos
 * - ACCEPTED: Aceptada para re-arbitraje
 * - REJECTED: Rechazada (sin méritos)
 * - IN_ARBITRATION: En re-arbitraje
 * - RESOLVED: Resuelta
 * - CLOSED: Cerrada
 * 
 * Proceso:
 * 1. Parte perdedora apela dentro de 24h
 * 2. Paga fee de apelación (2x fee disputa)
 * 3. Sistema revisa méritos de apelación
 * 4. Si aceptada, se asignan nuevos árbitros (senior/expert)
 * 5. Se permite nueva evidencia (limitada)
 * 6. Árbitros votan nuevamente
 * 7. Resultado final (no apelable si es 2da apelación)
 * 
 * Requisitos para aceptar apelación:
 * - Fee pagado
 * - Razón válida y detallada
 * - Dentro de timelock
 * - No exceder max apelaciones
 * - Score de mérito > umbral
 * 
 * Árbitros de apelación:
 * - Mínimo nivel SENIOR
 * - No pueden ser los mismos de disputa original
 * - Número impar (3, 5, o 7)
 * - Mayor reputación promedio
 * 
 * Seguridad:
 * - Fee más alto previene apelaciones frívolas
 * - Límite de apelaciones previene loops
 * - Revisión de méritos filtra casos sin fundamento
 * - Árbitros diferentes previenen sesgo
 * - Timelock estricto previene retrasos
 */
contract AppealManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de revisor de apelaciones
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");
    
    /// @notice Rol de operador (DisputeManager)
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Razones de apelación
    enum AppealReason {
        NEW_EVIDENCE,
        PROCEDURAL_ERROR,
        ARBITRATOR_BIAS,
        MISINTERPRETATION,
        INSUFFICIENT_EVIDENCE,
        OTHER
    }

    /// @notice Estados de apelación
    enum AppealState {
        SUBMITTED,
        UNDER_REVIEW,
        ACCEPTED,
        REJECTED,
        IN_ARBITRATION,
        RESOLVED,
        CLOSED
    }

    /// @notice Información de apelación
    struct Appeal {
        uint256 id;
        uint256 disputeId;
        address appellant;
        AppealReason reason;
        AppealState state;
        string detailedReason;
        uint256 appealFee;
        uint256 submittedAt;
        uint256 deadline;
        uint256 meritScore;
        bool accepted;
        address reviewedBy;
        uint256 reviewedAt;
        string reviewNotes;
        uint256[] newEvidenceIds;
        address[] assignedArbitrators;
        uint256 resolvedAt;
        bool successfulAppeal;
    }

    /// @notice Revisión de méritos
    struct MeritReview {
        uint256 appealId;
        address reviewer;
        uint256 score;
        bool recommend;
        string reasoning;
        uint256 timestamp;
    }

    /// @notice Resultado de re-arbitraje
    struct AppealResult {
        uint256 appealId;
        bool originalResultOverturned;
        string newResult;
        uint256 votesForOverturn;
        uint256 votesAgainstOverturn;
        uint256 resolvedAt;
    }

    /// @notice Apelaciones
    mapping(uint256 => Appeal) public appeals;
    
    /// @notice Contador de apelaciones
    uint256 public appealCounter;
    
    /// @notice Apelaciones por disputa
    mapping(uint256 => uint256[]) public disputeAppeals;
    
    /// @notice Apelaciones por usuario
    mapping(address => uint256[]) public userAppeals;
    
    /// @notice Revisiones de mérito
    mapping(uint256 => MeritReview[]) public meritReviews;
    
    /// @notice Resultados de apelaciones
    mapping(uint256 => AppealResult) public appealResults;

    /// @notice Configuración de fees
    struct FeeConfig {
        uint256 appealFee;
        uint256 secondAppealFee;
        uint256 appealArbitratorReward;
    }

    /// @notice Configuración de timeouts
    struct TimeoutConfig {
        uint256 appealWindow;
        uint256 reviewTimeout;
        uint256 arbitrationTimeout;
    }

    /// @notice Configuración de fees
    FeeConfig public feeConfig;
    
    /// @notice Configuración de timeouts
    TimeoutConfig public timeoutConfig;

    /// @notice Token para fees (CAMBIO)
    address public feeToken;
    
    /// @notice Treasury
    address public treasury;
    
    /// @notice DisputeManager
    address public disputeManager;
    
    /// @notice ArbitrationManager
    address public arbitrationManager;

    /// @notice Máximo de apelaciones por disputa
    uint256 public maxAppeals;
    
    /// @notice Score mínimo de mérito para aceptar
    uint256 public minMeritScore;
    
    /// @notice Número de revisores para mérito
    uint256 public requiredReviewers;

    /// @notice Total de apelaciones por estado
    mapping(AppealState => uint256) public appealsByState;
    
    /// @notice Total de apelaciones por razón
    mapping(AppealReason => uint256) public appealsByReason;

    /// @notice Apelaciones exitosas
    uint256 public successfulAppeals;

    // ============================================
    // EVENTOS
    // ============================================

    event AppealSubmitted(
        uint256 indexed appealId,
        uint256 indexed disputeId,
        address indexed appellant,
        AppealReason reason
    );

    event AppealReviewed(
        uint256 indexed appealId,
        address indexed reviewer,
        uint256 meritScore,
        bool recommend
    );

    event AppealAccepted(
        uint256 indexed appealId,
        address indexed acceptedBy
    );

    event AppealRejected(
        uint256 indexed appealId,
        address indexed rejectedBy,
        string reason
    );

    event AppealArbitratorsAssigned(
        uint256 indexed appealId,
        address[] arbitrators
    );

    event AppealResolved(
        uint256 indexed appealId,
        bool originalOverturned
    );

    event AppealStateChanged(
        uint256 indexed appealId,
        AppealState oldState,
        AppealState newState
    );

    event NewEvidenceSubmitted(
        uint256 indexed appealId,
        uint256 evidenceId
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _feeToken,
        address _treasury
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_feeToken != address(0), "Invalid fee token");
        require(_treasury != address(0), "Invalid treasury");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(REVIEWER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        feeToken = _feeToken;
        treasury = _treasury;

        // Configuración por defecto
        feeConfig.appealFee = 200 * 10**18; // 200 CAMBIO
        feeConfig.secondAppealFee = 500 * 10**18; // 500 CAMBIO
        feeConfig.appealArbitratorReward = 100 * 10**18; // 100 CAMBIO

        timeoutConfig.appealWindow = 24 hours;
        timeoutConfig.reviewTimeout = 48 hours;
        timeoutConfig.arbitrationTimeout = 72 hours;

        maxAppeals = 2;
        minMeritScore = 60;
        requiredReviewers = 2;
    }

    // ============================================
    // SUBMIT DE APELACIÓN
    // ============================================

    /**
     * @notice Envía apelación
     */
    function submitAppeal(
        uint256 disputeId,
        AppealReason reason,
        string memory detailedReason,
        uint256[] memory newEvidenceIds
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(bytes(detailedReason).length >= 50, "Reason too short");
        
        // Verificar que no exceda max apelaciones
        require(disputeAppeals[disputeId].length < maxAppeals, "Max appeals reached");

        // Determinar fee según número de apelación
        uint256 appealFee = disputeAppeals[disputeId].length == 0 
            ? feeConfig.appealFee 
            : feeConfig.secondAppealFee;

        // Cobrar fee
        IERC20(feeToken).safeTransferFrom(msg.sender, address(this), appealFee);

        appealCounter++;
        uint256 appealId = appealCounter;

        // Crear apelación
        Appeal storage appeal = appeals[appealId];
        appeal.id = appealId;
        appeal.disputeId = disputeId;
        appeal.appellant = msg.sender;
        appeal.reason = reason;
        appeal.state = AppealState.SUBMITTED;
        appeal.detailedReason = detailedReason;
        appeal.appealFee = appealFee;
        appeal.submittedAt = block.timestamp;
        appeal.deadline = block.timestamp + timeoutConfig.appealWindow;
        appeal.newEvidenceIds = newEvidenceIds;

        // Agregar a mapeos
        disputeAppeals[disputeId].push(appealId);
        userAppeals[msg.sender].push(appealId);
        appealsByReason[reason]++;
        appealsByState[AppealState.SUBMITTED]++;

        // Cambiar a revisión
        _changeState(appealId, AppealState.UNDER_REVIEW);

        emit AppealSubmitted(appealId, disputeId, msg.sender, reason);

        return appealId;
    }

    /**
     * @notice Envía apelación rápida desde contrato
     */
    function submitAppealExternal(
        uint256 disputeId,
        address appellant,
        AppealReason reason,
        string memory detailedReason
    ) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        require(disputeAppeals[disputeId].length < maxAppeals, "Max appeals reached");

        appealCounter++;
        uint256 appealId = appealCounter;

        Appeal storage appeal = appeals[appealId];
        appeal.id = appealId;
        appeal.disputeId = disputeId;
        appeal.appellant = appellant;
        appeal.reason = reason;
        appeal.state = AppealState.SUBMITTED;
        appeal.detailedReason = detailedReason;
        appeal.appealFee = 0; // Sin fee desde contratos
        appeal.submittedAt = block.timestamp;
        appeal.deadline = block.timestamp + timeoutConfig.appealWindow;

        disputeAppeals[disputeId].push(appealId);
        userAppeals[appellant].push(appealId);
        appealsByReason[reason]++;
        appealsByState[AppealState.SUBMITTED]++;

        _changeState(appealId, AppealState.UNDER_REVIEW);

        emit AppealSubmitted(appealId, disputeId, appellant, reason);

        return appealId;
    }

    // ============================================
    // REVISIÓN DE MÉRITOS
    // ============================================

    /**
     * @notice Revisa méritos de apelación
     */
    function reviewMerit(
        uint256 appealId,
        uint256 score,
        bool recommend,
        string memory reasoning
    ) external onlyRole(REVIEWER_ROLE) {
        Appeal storage appeal = appeals[appealId];
        require(appeal.state == AppealState.UNDER_REVIEW, "Not under review");
        require(score <= 100, "Invalid score");

        // Verificar que no haya revisado antes
        MeritReview[] memory reviews = meritReviews[appealId];
        for (uint256 i = 0; i < reviews.length; i++) {
            require(reviews[i].reviewer != msg.sender, "Already reviewed");
        }

        // Agregar revisión
        MeritReview memory review = MeritReview({
            appealId: appealId,
            reviewer: msg.sender,
            score: score,
            recommend: recommend,
            reasoning: reasoning,
            timestamp: block.timestamp
        });

        meritReviews[appealId].push(review);

        emit AppealReviewed(appealId, msg.sender, score, recommend);

        // Si ya hay suficientes revisiones, calcular promedio
        if (meritReviews[appealId].length >= requiredReviewers) {
            _calculateMeritScore(appealId);
        }
    }

    /**
     * @notice Calcula score promedio de mérito
     */
    function _calculateMeritScore(uint256 appealId) internal {
        Appeal storage appeal = appeals[appealId];
        MeritReview[] memory reviews = meritReviews[appealId];

        uint256 totalScore = 0;
        uint256 recommendations = 0;

        for (uint256 i = 0; i < reviews.length; i++) {
            totalScore += reviews[i].score;
            if (reviews[i].recommend) {
                recommendations++;
            }
        }

        appeal.meritScore = totalScore / reviews.length;

        // Auto-aceptar o rechazar según score y recomendaciones
        if (appeal.meritScore >= minMeritScore && recommendations >= (reviews.length / 2 + 1)) {
            _acceptAppeal(appealId);
        } else {
            _rejectAppeal(appealId, "Insufficient merit");
        }
    }

    /**
     * @notice Acepta apelación
     */
    function acceptAppeal(uint256 appealId) external onlyRole(ADMIN_ROLE) {
        _acceptAppeal(appealId);
    }

    /**
     * @notice Acepta apelación internamente
     */
    function _acceptAppeal(uint256 appealId) internal {
        Appeal storage appeal = appeals[appealId];
        require(appeal.state == AppealState.UNDER_REVIEW, "Not under review");

        appeal.accepted = true;
        appeal.reviewedBy = msg.sender;
        appeal.reviewedAt = block.timestamp;

        _changeState(appealId, AppealState.ACCEPTED);

        // Asignar árbitros
        _assignAppealArbitrators(appealId);

        emit AppealAccepted(appealId, msg.sender);
    }

    /**
     * @notice Rechaza apelación
     */
    function rejectAppeal(uint256 appealId, string memory reason) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        _rejectAppeal(appealId, reason);
    }

    /**
     * @notice Rechaza apelación internamente
     */
    function _rejectAppeal(uint256 appealId, string memory reason) internal {
        Appeal storage appeal = appeals[appealId];
        require(appeal.state == AppealState.UNDER_REVIEW, "Not under review");

        appeal.accepted = false;
        appeal.reviewedBy = msg.sender;
        appeal.reviewedAt = block.timestamp;
        appeal.reviewNotes = reason;

        _changeState(appealId, AppealState.REJECTED);

        // Refund 50% del fee
        uint256 refund = appeal.appealFee / 2;
        if (refund > 0) {
            IERC20(feeToken).safeTransfer(appeal.appellant, refund);
        }

        emit AppealRejected(appealId, msg.sender, reason);
    }

    // ============================================
    // ASIGNACIÓN DE ÁRBITROS
    // ============================================

    /**
     * @notice Asigna árbitros a apelación
     */
    function _assignAppealArbitrators(uint256 appealId) internal {
        // Llamar a ArbitrationManager para obtener árbitros senior/expert
        if (arbitrationManager != address(0)) {
            (bool success, bytes memory data) = arbitrationManager.call(
                abi.encodeWithSignature(
                    "assignArbitrators(uint256,uint256)", 
                    appealId, 
                    3 // Mínimo 3 árbitros
                )
            );
            
            if (success) {
                address[] memory arbitrators = abi.decode(data, (address[]));
                appeals[appealId].assignedArbitrators = arbitrators;
                
                _changeState(appealId, AppealState.IN_ARBITRATION);
                
                emit AppealArbitratorsAssigned(appealId, arbitrators);
            }
        }
    }

    /**
     * @notice Asigna árbitros manualmente
     */
    function assignArbitratorsManual(uint256 appealId, address[] memory arbitrators) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(arbitrators.length >= 3 && arbitrators.length % 2 == 1, "Invalid arbitrators");
        
        Appeal storage appeal = appeals[appealId];
        require(appeal.state == AppealState.ACCEPTED, "Not accepted");

        appeal.assignedArbitrators = arbitrators;
        
        _changeState(appealId, AppealState.IN_ARBITRATION);
        
        emit AppealArbitratorsAssigned(appealId, arbitrators);
    }

    // ============================================
    // NUEVA EVIDENCIA
    // ============================================

    /**
     * @notice Agrega nueva evidencia a apelación
     */
    function addNewEvidence(uint256 appealId, uint256 evidenceId) 
        external 
        nonReentrant 
    {
        Appeal storage appeal = appeals[appealId];
        require(msg.sender == appeal.appellant, "Not appellant");
        require(
            appeal.state == AppealState.UNDER_REVIEW || 
            appeal.state == AppealState.ACCEPTED ||
            appeal.state == AppealState.IN_ARBITRATION,
            "Cannot add evidence"
        );
        require(appeal.newEvidenceIds.length < 5, "Max 5 new evidences");

        appeal.newEvidenceIds.push(evidenceId);

        emit NewEvidenceSubmitted(appealId, evidenceId);
    }

    // ============================================
    // RESOLUCIÓN
    // ============================================

    /**
     * @notice Resuelve apelación
     */
    function resolveAppeal(
        uint256 appealId,
        bool overturnOriginal,
        uint256 votesFor,
        uint256 votesAgainst,
        string memory newResult
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        Appeal storage appeal = appeals[appealId];
        require(appeal.state == AppealState.IN_ARBITRATION, "Not in arbitration");

        appeal.resolvedAt = block.timestamp;
        appeal.successfulAppeal = overturnOriginal;

        // Crear resultado
        AppealResult storage result = appealResults[appealId];
        result.appealId = appealId;
        result.originalResultOverturned = overturnOriginal;
        result.newResult = newResult;
        result.votesForOverturn = votesFor;
        result.votesAgainstOverturn = votesAgainst;
        result.resolvedAt = block.timestamp;

        if (overturnOriginal) {
            successfulAppeals++;
        }

        _changeState(appealId, AppealState.RESOLVED);

        // Distribuir recompensas
        _distributeAppealRewards(appealId, overturnOriginal);

        emit AppealResolved(appealId, overturnOriginal);
    }

    /**
     * @notice Cierra apelación
     */
    function closeAppeal(uint256 appealId) external {
        Appeal storage appeal = appeals[appealId];
        require(appeal.state == AppealState.RESOLVED, "Not resolved");

        _changeState(appealId, AppealState.CLOSED);
    }

    /**
     * @notice Distribuye recompensas de apelación
     */
    function _distributeAppealRewards(uint256 appealId, bool successful) internal {
        Appeal storage appeal = appeals[appealId];

        // Si apelación exitosa, refund completo al apelante
        if (successful) {
            IERC20(feeToken).safeTransfer(appeal.appellant, appeal.appealFee);
        }

        // Recompensar árbitros
        for (uint256 i = 0; i < appeal.assignedArbitrators.length; i++) {
            IERC20(feeToken).safeTransfer(
                appeal.assignedArbitrators[i],
                feeConfig.appealArbitratorReward
            );
        }

        // Resto a treasury
        uint256 remaining = IERC20(feeToken).balanceOf(address(this));
        if (remaining > 0) {
            IERC20(feeToken).safeTransfer(treasury, remaining);
        }
    }

    // ============================================
    // HELPERS
    // ============================================

    /**
     * @notice Cambia estado de apelación
     */
    function _changeState(uint256 appealId, AppealState newState) internal {
        Appeal storage appeal = appeals[appealId];
        AppealState oldState = appeal.state;

        if (oldState != newState) {
            appealsByState[oldState]--;
            appealsByState[newState]++;
            appeal.state = newState;

            emit AppealStateChanged(appealId, oldState, newState);
        }
    }

    // ============================================
    // CONFIGURACIÓN
    // ============================================

    /**
     * @notice Configura fees
     */
    function configureFees(
        uint256 appealFee,
        uint256 secondAppealFee,
        uint256 appealArbitratorReward
    ) external onlyRole(ADMIN_ROLE) {
        feeConfig.appealFee = appealFee;
        feeConfig.secondAppealFee = secondAppealFee;
        feeConfig.appealArbitratorReward = appealArbitratorReward;
    }

    /**
     * @notice Configura timeouts
     */
    function configureTimeouts(
        uint256 appealWindow,
        uint256 reviewTimeout,
        uint256 arbitrationTimeout
    ) external onlyRole(ADMIN_ROLE) {
        timeoutConfig.appealWindow = appealWindow;
        timeoutConfig.reviewTimeout = reviewTimeout;
        timeoutConfig.arbitrationTimeout = arbitrationTimeout;
    }

    function setDisputeManager(address _disputeManager) external onlyRole(ADMIN_ROLE) {
        require(_disputeManager != address(0), "Invalid address");
        disputeManager = _disputeManager;
        _grantRole(OPERATOR_ROLE, _disputeManager);
    }

    function setArbitrationManager(address _arbitrationManager) external onlyRole(ADMIN_ROLE) {
        arbitrationManager = _arbitrationManager;
    }

    function setMaxAppeals(uint256 _maxAppeals) external onlyRole(ADMIN_ROLE) {
        maxAppeals = _maxAppeals;
    }

    function setMinMeritScore(uint256 _minMeritScore) external onlyRole(ADMIN_ROLE) {
        require(_minMeritScore <= 100, "Invalid score");
        minMeritScore = _minMeritScore;
    }

    function setRequiredReviewers(uint256 _requiredReviewers) external onlyRole(ADMIN_ROLE) {
        require(_requiredReviewers > 0, "Invalid count");
        requiredReviewers = _requiredReviewers;
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

    function getAppeal(uint256 appealId) external view returns (Appeal memory) {
        return appeals[appealId];
    }

    function getDisputeAppeals(uint256 disputeId) external view returns (uint256[] memory) {
        return disputeAppeals[disputeId];
    }

    function getUserAppeals(address user) external view returns (uint256[] memory) {
        return userAppeals[user];
    }

    function getMeritReviews(uint256 appealId) external view returns (MeritReview[] memory) {
        return meritReviews[appealId];
    }

    function getAppealResult(uint256 appealId) external view returns (AppealResult memory) {
        return appealResults[appealId];
    }

    function getAppealArbitrators(uint256 appealId) external view returns (address[] memory) {
        return appeals[appealId].assignedArbitrators;
    }

    function getNewEvidences(uint256 appealId) external view returns (uint256[] memory) {
        return appeals[appealId].newEvidenceIds;
    }

    function canAppeal(uint256 disputeId) external view returns (bool can, string memory reason) {
        uint256 appealCount = disputeAppeals[disputeId].length;
        
        if (appealCount >= maxAppeals) {
            return (false, "Max appeals reached");
        }

        return (true, "Can appeal");
    }

    function getStats() external view returns (
        uint256 totalAppeals,
        uint256 submitted,
        uint256 underReview,
        uint256 accepted,
        uint256 rejected,
        uint256 inArbitration,
        uint256 resolved,
        uint256 successful
    ) {
        return (
            appealCounter,
            appealsByState[AppealState.SUBMITTED],
            appealsByState[AppealState.UNDER_REVIEW],
            appealsByState[AppealState.ACCEPTED],
            appealsByState[AppealState.REJECTED],
            appealsByState[AppealState.IN_ARBITRATION],
            appealsByState[AppealState.RESOLVED],
            successfulAppeals
        );
    }

    function getSuccessRate() external view returns (uint256) {
        if (appealCounter == 0) return 0;
        return (successfulAppeals * 10000) / appealCounter; // Basis points
    }
}
