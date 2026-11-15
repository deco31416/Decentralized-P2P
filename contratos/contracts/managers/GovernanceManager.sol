// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title GovernanceManager
 * @notice Sistema de gobernanza on-chain para CambiaCripto
 * @dev Permite a holders de CAMBIO token votar en propuestas
 * 
 * Características:
 * - Voting power proporcional a stake de CAMBIO
 * - Quorum mínimo para aprobar propuestas
 * - Timelock para ejecución de propuestas aprobadas
 * - Veto de emergencia por admin (primeros 6 meses)
 * 
 * Tipos de propuestas:
 * 1. Cambiar fees globales (FeeManager)
 * 2. Aprobar/remover intermediarios (IntermediaryManager)
 * 3. Actualizar límites de trading (P2PExchange)
 * 4. Agregar nuevas monedas fiat (FiatFeeManager)
 * 5. Cambiar timeouts de órdenes (P2PFiatExchange)
 * 6. Asignar/remover roles admin
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract GovernanceManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============================================
    // ROLES
    // ============================================
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");  // ADDED: Emergency guardian
    
    // ============================================
    // CONSTANTS
    // ============================================
    
    /// @notice Voting period (7 días)
    uint256 public constant VOTING_PERIOD = 7 days;
    
    /// @notice Timelock period (2 días)
    uint256 public constant TIMELOCK_PERIOD = 2 days;
    
    /// @notice Quorum mínimo (10% del supply total)
    uint256 public constant QUORUM_PERCENTAGE = 1000; // 10%
    
    /// @notice Mayoría requerida (51%)
    uint256 public constant MAJORITY_PERCENTAGE = 5100; // 51%
    
    /// @notice Basis points
    uint256 public constant BPS = 10_000;
    
    /// @notice Stake mínimo para proponer (10,000 CAMBIO)
    uint256 public constant MIN_PROPOSAL_STAKE = 10_000e18;
    
    // ============================================
    // ENUMS
    // ============================================
    
    enum ProposalState {
        Pending,        // Creada, esperando votación
        Active,         // En período de votación
        Succeeded,      // Aprobada, esperando timelock
        Queued,         // En timelock, esperando ejecución
        Executed,       // Ejecutada exitosamente
        Defeated,       // Rechazada
        Cancelled,      // Cancelada por proposer o admin
        Vetoed          // Vetoed por admin (solo primeros 6 meses)
    }
    
    enum ProposalType {
        ChangeFees,             // Cambiar fees globales
        ManageIntermediaries,   // Aprobar/remover intermediarios
        UpdateLimits,           // Actualizar límites de trading
        AddFiatCurrency,        // Agregar nueva moneda fiat
        ChangeTimeouts,         // Cambiar timeouts de órdenes
        GrantRole,              // Asignar rol
        RevokeRole,             // Remover rol
        EmergencyPause,         // Pausar sistema (emergencia)
        Custom                  // Propuesta custom con calldata
    }
    
    enum VoteType {
        Against,    // 0
        For,        // 1
        Abstain     // 2
    }
    
    // ============================================
    // STRUCTS
    // ============================================
    
    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        string title;
        string description;
        bytes callData;             // Calldata para ejecutar
        address target;             // Contrato target
        uint256 value;              // ETH/BNB a enviar
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 votesAbstain;
        uint256 createdAt;
        uint256 startBlock;
        uint256 endBlock;
        uint256 eta;                // Timestamp de ejecución post-timelock
        ProposalState state;
        mapping(address => Receipt) receipts;
    }
    
    struct Receipt {
        bool hasVoted;
        VoteType voteType;
        uint256 votes;              // Voting power usado
    }
    
    struct ProposalInfo {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        string title;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 votesAbstain;
        uint256 createdAt;
        uint256 endBlock;
        uint256 eta;
        ProposalState state;
    }
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    /// @notice CAMBIO token
    IERC20 public immutable cambioToken;
    
    /// @notice Total supply de CAMBIO
    uint256 public totalSupply;
    
    /// @notice Contador de propuestas
    uint256 public proposalCount;
    
    /// @notice Mapeo de propuestas
    mapping(uint256 => Proposal) public proposals;
    
    /// @notice IDs de propuestas (para iteración)
    uint256[] public proposalIds;
    
    /// @notice Timestamp de deployment (para veto admin primeros 6 meses)
    uint256 public immutable deploymentTime;
    
    /// @notice Registry de contratos del ecosistema
    mapping(string => address) public contractRegistry;
    
    // ============================================
    // EVENTS
    // ============================================
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string title,
        uint256 startBlock,
        uint256 endBlock
    );
    
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        VoteType voteType,
        uint256 votes
    );
    
    event ProposalQueued(
        uint256 indexed proposalId,
        uint256 eta
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId
    );
    
    event ProposalCancelled(
        uint256 indexed proposalId,
        address indexed canceller
    );
    
    event ProposalVetoed(
        uint256 indexed proposalId,
        address indexed admin,
        string reason
    );
    
    event ContractRegistered(
        string indexed name,
        address indexed contractAddress
    );
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor(
        address _cambioToken,
        address _admin
    ) {
        require(_cambioToken != address(0), "Invalid CAMBIO token");
        require(_admin != address(0), "Invalid admin");
        
        cambioToken = IERC20(_cambioToken);
        totalSupply = cambioToken.totalSupply();
        deploymentTime = block.timestamp;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PROPOSER_ROLE, _admin);
        _grantRole(EXECUTOR_ROLE, _admin);
    }
    
    // ============================================
    // PROPOSAL CREATION
    // ============================================
    
    /**
     * @notice Crear propuesta de gobernanza
     * @param proposalType Tipo de propuesta
     * @param title Título
     * @param description Descripción detallada
     * @param target Contrato a llamar (address(0) si no aplica)
     * @param value BNB a enviar (0 si no aplica)
     * @param callData Calldata a ejecutar
     */
    function propose(
        ProposalType proposalType,
        string memory title,
        string memory description,
        address target,
        uint256 value,
        bytes memory callData
    ) external nonReentrant returns (uint256 proposalId) {
        // Verificar stake mínimo
        require(
            cambioToken.balanceOf(msg.sender) >= MIN_PROPOSAL_STAKE,
            "Insufficient CAMBIO to propose"
        );
        
        require(bytes(title).length > 0, "Title required");
        require(bytes(description).length > 0, "Description required");
        
        proposalCount++;
        proposalId = proposalCount;
        
        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.proposalType = proposalType;
        proposal.title = title;
        proposal.description = description;
        proposal.target = target;
        proposal.value = value;
        proposal.callData = callData;
        proposal.createdAt = block.timestamp;
        proposal.startBlock = block.number;
        proposal.endBlock = block.number + (VOTING_PERIOD / 3); // ~3 seg por bloque en BSC
        proposal.state = ProposalState.Active;
        
        proposalIds.push(proposalId);
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            proposalType,
            title,
            proposal.startBlock,
            proposal.endBlock
        );
        
        return proposalId;
    }
    
    // ============================================
    // VOTING
    // ============================================
    
    /**
     * @notice Votar en propuesta
     * @param proposalId ID de la propuesta
     * @param voteType Tipo de voto (Against/For/Abstain)
     */
    function castVote(uint256 proposalId, VoteType voteType) 
        external 
        nonReentrant 
    {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.state == ProposalState.Active, "Proposal not active");
        require(block.number <= proposal.endBlock, "Voting ended");
        require(!proposal.receipts[msg.sender].hasVoted, "Already voted");
        
        // Voting power = balance de CAMBIO del voter
        uint256 votes = cambioToken.balanceOf(msg.sender);
        require(votes > 0, "No voting power");
        
        proposal.receipts[msg.sender] = Receipt({
            hasVoted: true,
            voteType: voteType,
            votes: votes
        });
        
        if (voteType == VoteType.For) {
            proposal.votesFor += votes;
        } else if (voteType == VoteType.Against) {
            proposal.votesAgainst += votes;
        } else {
            proposal.votesAbstain += votes;
        }
        
        emit VoteCast(msg.sender, proposalId, voteType, votes);
    }
    
    // ============================================
    // PROPOSAL LIFECYCLE
    // ============================================
    
    /**
     * @notice Finalizar votación y queue si aprobada
     * @param proposalId ID de la propuesta
     */
    function queue(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.state == ProposalState.Active, "Proposal not active");
        require(block.number > proposal.endBlock, "Voting not ended");
        
        // Verificar quorum
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst + proposal.votesAbstain;
        uint256 quorumRequired = (totalSupply * QUORUM_PERCENTAGE) / BPS;
        
        if (totalVotes < quorumRequired) {
            proposal.state = ProposalState.Defeated;
            return;
        }
        
        // Verificar mayoría
        uint256 majorityRequired = (totalVotes * MAJORITY_PERCENTAGE) / BPS;
        
        if (proposal.votesFor >= majorityRequired) {
            proposal.state = ProposalState.Succeeded;
            proposal.eta = block.timestamp + TIMELOCK_PERIOD;
            proposal.state = ProposalState.Queued;
            
            emit ProposalQueued(proposalId, proposal.eta);
        } else {
            proposal.state = ProposalState.Defeated;
        }
    }
    
    /**
     * @notice Ejecutar propuesta aprobada (post-timelock)
     * @param proposalId ID de la propuesta
     * @dev FIXED: Agrega delay de seguridad de 48h y validaciones robustas
     */
    function execute(uint256 proposalId) 
        external 
        nonReentrant 
        onlyRole(EXECUTOR_ROLE)
    {
        Proposal storage proposal = proposals[proposalId];
        
        // CHECKS
        require(proposal.state == ProposalState.Queued, "Not queued");
        require(block.timestamp >= proposal.eta, "Timelock not expired");
        
        // SECURITY: Delay adicional de 48h después de ETA
        require(block.timestamp >= proposal.eta + 48 hours, "Security delay not met");
        
        // SECURITY: Grace period - expira después de 14 días
        require(block.timestamp <= proposal.eta + 14 days, "Proposal expired");
        
        // EFFECTS: Actualizar estado ANTES de ejecutar
        proposal.state = ProposalState.Executed;
        
        // INTERACTIONS: Ejecutar calldata al final
        if (proposal.target != address(0)) {
            // Validar que target no sea address(0) crítico
            require(proposal.target != address(this), "Cannot call self");
            
            // Call con límite de gas para prevenir griefing
            (bool success, bytes memory returnData) = proposal.target.call{
                value: proposal.value,
                gas: 500000 // Límite de gas para prevenir DoS
            }(proposal.callData);
            
            require(success, string(abi.encodePacked("Execution failed: ", returnData)));
        }
        
        emit ProposalExecuted(proposalId);
    }
    
    /**
     * @notice Cancelar propuesta (solo proposer o admin)
     * @param proposalId ID de la propuesta
     */
    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        
        require(
            msg.sender == proposal.proposer || hasRole(ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        
        require(
            proposal.state == ProposalState.Active || 
            proposal.state == ProposalState.Queued,
            "Cannot cancel"
        );
        
        proposal.state = ProposalState.Cancelled;
        
        emit ProposalCancelled(proposalId, msg.sender);
    }
    
    /**
     * @notice Veto de emergencia (solo admin, primeros 6 meses)
     * @param proposalId ID de la propuesta
     * @param reason Razón del veto
     */
    function veto(uint256 proposalId, string memory reason) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(
            block.timestamp < deploymentTime + 180 days,
            "Veto period expired"
        );
        
        Proposal storage proposal = proposals[proposalId];
        
        require(
            proposal.state == ProposalState.Active ||
            proposal.state == ProposalState.Queued,
            "Cannot veto"
        );
        
        proposal.state = ProposalState.Vetoed;
        
        emit ProposalVetoed(proposalId, msg.sender, reason);
    }
    
    /**
     * @notice Emergency cancel - Guardian puede cancelar en las primeras 24h después de queue
     * @dev SECURITY: Previene ejecución maliciosa inmediata
     * @param proposalId ID de la propuesta
     * @param reason Razón de la cancelación de emergencia
     */
    function emergencyCancel(uint256 proposalId, string memory reason) 
        external 
        onlyRole(GUARDIAN_ROLE) 
        nonReentrant
    {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.state == ProposalState.Queued, "Not queued");
        require(block.timestamp <= proposal.eta - (48 hours - 24 hours), "Emergency window expired");
        
        proposal.state = ProposalState.Cancelled;
        
        emit EmergencyCancelled(proposalId, msg.sender, reason);
    }
    
    /**
     * @notice Emergency withdraw - Recuperar tokens/ETH enviados accidentalmente
     * @dev Solo admin puede recuperar fondos
     */
    function emergencyWithdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(recipient != address(0), "Zero address");
        require(amount > 0, "Zero amount");
        
        if (token == address(0)) {
            // Withdraw native token (BNB/ETH)
            (bool success, ) = recipient.call{value: amount, gas: 50000}("");
            require(success, "Transfer failed");
        } else {
            // Withdraw ERC20
            IERC20(token).safeTransfer(recipient, amount);
        }
        
        emit EmergencyWithdraw(token, recipient, amount);
    }
    
    /**
     * @notice Eventos de emergencia
     */
    event EmergencyCancelled(uint256 indexed proposalId, address indexed guardian, string reason);
    event EmergencyWithdraw(address indexed token, address indexed recipient, uint256 amount);
    
    // ============================================
    // VIEWS
    // ============================================
    
    /**
     * @notice Obtener estado de propuesta
     */
    function getProposal(uint256 proposalId) 
        external 
        view 
        returns (ProposalInfo memory) 
    {
        Proposal storage p = proposals[proposalId];
        
        return ProposalInfo({
            id: p.id,
            proposer: p.proposer,
            proposalType: p.proposalType,
            title: p.title,
            description: p.description,
            votesFor: p.votesFor,
            votesAgainst: p.votesAgainst,
            votesAbstain: p.votesAbstain,
            createdAt: p.createdAt,
            endBlock: p.endBlock,
            eta: p.eta,
            state: p.state
        });
    }
    
    /**
     * @notice Obtener receipt de voto
     */
    function getReceipt(uint256 proposalId, address voter)
        external
        view
        returns (bool hasVoted, VoteType voteType, uint256 votes)
    {
        Receipt storage receipt = proposals[proposalId].receipts[voter];
        return (receipt.hasVoted, receipt.voteType, receipt.votes);
    }
    
    /**
     * @notice Obtener todas las propuestas
     */
    function getAllProposals() external view returns (uint256[] memory) {
        return proposalIds;
    }
    
    /**
     * @notice Obtener propuestas activas
     */
    function getActiveProposals() external view returns (uint256[] memory) {
        uint256 count = 0;
        
        // Contar propuestas activas
        for (uint256 i = 0; i < proposalIds.length; i++) {
            if (proposals[proposalIds[i]].state == ProposalState.Active) {
                count++;
            }
        }
        
        // Crear array
        uint256[] memory activeIds = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < proposalIds.length; i++) {
            if (proposals[proposalIds[i]].state == ProposalState.Active) {
                activeIds[index] = proposalIds[i];
                index++;
            }
        }
        
        return activeIds;
    }
    
    /**
     * @notice Obtener voting power de address
     */
    function getVotingPower(address account) external view returns (uint256) {
        return cambioToken.balanceOf(account);
    }
    
    // ============================================
    // ADMIN FUNCTIONS
    // ============================================
    
    /**
     * @notice Registrar contrato del ecosistema
     */
    function registerContract(string memory name, address contractAddress)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(contractAddress != address(0), "Invalid address");
        contractRegistry[name] = contractAddress;
        
        emit ContractRegistered(name, contractAddress);
    }
    
    /**
     * @notice Actualizar total supply de CAMBIO
     */
    function updateTotalSupply() external {
        totalSupply = cambioToken.totalSupply();
    }
}
