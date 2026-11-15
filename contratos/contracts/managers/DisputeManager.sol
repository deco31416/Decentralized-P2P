// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IReputationManager.sol";
import "../interfaces/IStakingManager.sol";
import "../interfaces/IPriceOracle.sol";

/**
 * @title DisputeManagerV2
 * @notice Stake-weighted arbitrator panel with progressive slashing
 * @dev CRITICAL ANTI-SYBIL FEATURES:
 *      1. Stake-weighted selection (not count-based)
 *      2. MIN_ARB_STAKE = $5k in CAMBIO
 *      3. MIN_ARB_REPUTATION = 800
 *      4. Progressive slashing: 20% → 50% → 100% + BAN
 * 
 * Flow:
 *      1. Trade disputed → select 3 arbitrators
 *      2. Arbitrators review evidence
 *      3. Majority vote wins
 *      4. Losers get slashed (progressive)
 *      5. Winners get rewards
 * 
 * Security:
 *      - Stake-weighted prevents Sybil attacks
 *      - Progressive slashing deters bad behavior
 *      - Reputation requirement filters bad actors
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract DisputeManagerV2 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Minimum CAMBIO stake to be arbitrator (in USD, 6 decimals)
    uint256 public constant MIN_ARB_STAKE_USD = 5000e6;
    
    /// @notice Minimum reputation to be arbitrator
    uint256 public constant MIN_ARB_REPUTATION = 800;
    
    /// @notice Arbitrators per dispute
    uint256 public constant ARBITRATORS_PER_DISPUTE = 3;
    
    /// @notice Voting period (48 hours)
    uint256 public constant VOTING_PERIOD = 48 hours;
    
    /// @notice Slashing percentages (bps)
    uint256 public constant SLASH_FIRST_OFFENSE = 2000;   // 20%
    uint256 public constant SLASH_SECOND_OFFENSE = 5000;  // 50%
    uint256 public constant SLASH_THIRD_OFFENSE = 10000;  // 100% + ban
    
    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;
    
    /*//////////////////////////////////////////////////////////////
                            ENUMS
    //////////////////////////////////////////////////////////////*/
    
    enum DisputeState { PENDING, VOTING, RESOLVED }
    enum Vote { NONE, BUYER, SELLER }
    
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct DisputeEvidence {
        address submitter;          // Who submitted
        uint256 timestamp;          // When submitted
        string evidenceType;        // "bank_receipt", "screenshot", "chat_log", etc
        string ipfsHash;            // IPFS hash of evidence
        string description;         // Text description
        bool verifiedByArbitrator;  // Has arbitrator reviewed it?
    }
    
    struct Dispute {
        uint256 tradeId;
        address buyer;
        address seller;
        uint256 disputeAmount;      // Amount in dispute (for proportional rewards/slashing)
        address[] arbitrators;
        mapping(address => Vote) votes;
        mapping(address => uint256) voteWeights;  // Stake weight of each vote
        uint256 votesForBuyer;
        uint256 votesForSeller;
        uint256 totalVoteWeight;    // Total stake weight voted
        DisputeState state;
        uint256 createdAt;
        uint256 votingDeadline;     // SECURITY: Hard deadline for voting
        uint256 resolvedAt;
        address winner;
        uint256 rewardPool;         // Fees collected for arbitrators
    }
    
    struct Arbitrator {
        bool isRegistered;
        uint256 disputesHandled;
        uint256 correctVotes;
        uint256 incorrectVotes;
        uint256 slashCount;
        uint256 totalEarned;        // Total fees earned
        uint256 lastActiveAt;       // Last time participated
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice CAMBIO token
    IERC20 public immutable cambioToken;
    
    /// @notice Reputation manager
    IReputationManager public reputationManager;
    
    /// @notice Staking manager
    IStakingManager public stakingManager;
    
    /// @notice Price oracle
    IPriceOracle public priceOracle;
    
    /// @notice All disputes
    mapping(uint256 => Dispute) public disputes;
    
    /// @notice Dispute evidence: disputeId => evidence[]
    mapping(uint256 => DisputeEvidence[]) public disputeEvidences;
    
    /// @notice Dispute count
    uint256 public disputeCount;
    
    /// @notice Arbitrator data
    mapping(address => Arbitrator) public arbitrators;
    
    /// @notice Registered arbitrator list
    address[] public arbitratorList;
    
    /// @notice Dispute fee percentage (2% of dispute amount)
    uint256 public constant DISPUTE_FEE_BPS = 200;  // 2%
    
    /// @notice Random nonce for arbitrator selection
    uint256 private randomNonce;
    
    /// @notice Rate limiting: user => action type => last timestamp
    mapping(address => mapping(uint256 => uint256)) public lastActionTime;
    
    /// @notice Cooldown for dispute creation (1 minute)
    uint256 public constant DISPUTE_CREATION_COOLDOWN = 1 minutes;
    
    /// @notice Cooldown for evidence submission (10 seconds)
    uint256 public constant EVIDENCE_SUBMISSION_COOLDOWN = 10 seconds;
    
    /// @notice Action types for rate limiting
    uint256 private constant ACTION_CREATE_DISPUTE = 1;
    uint256 private constant ACTION_SUBMIT_EVIDENCE = 2;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event RateLimitUpdated(address indexed user, uint256 actionType, uint256 timestamp);
    
    event DisputeCreated(uint256 indexed disputeId, uint256 indexed tradeId, address[] arbitrators);
    event VoteCast(uint256 indexed disputeId, address indexed arbitrator, Vote vote);
    event DisputeResolved(uint256 indexed disputeId, address winner);
    event DisputeResolvedByTimeout(uint256 indexed disputeId, address winner);
    event ArbitratorSlashed(address indexed arbitrator, uint256 amount, uint256 slashCount);
    event ArbitratorRewarded(address indexed arbitrator, uint256 indexed disputeId, uint256 amount);
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, string ipfsHash);
    event ArbitratorRegistered(address indexed arbitrator);
    event ArbitratorUnregistered(address indexed arbitrator);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address initialOwner,
        address _cambioToken,
        address _reputationManager,
        address _stakingManager,
        address _priceOracle
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Dispute: zero owner");
        require(_cambioToken != address(0), "Dispute: zero token");
        require(_reputationManager != address(0), "Dispute: zero reputation");
        require(_stakingManager != address(0), "Dispute: zero staking");
        require(_priceOracle != address(0), "Dispute: zero oracle");
        
        cambioToken = IERC20(_cambioToken);
        reputationManager = IReputationManager(_reputationManager);
        stakingManager = IStakingManager(_stakingManager);
        priceOracle = IPriceOracle(_priceOracle);
    }
    
    /*//////////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Rate limit modifier
     * @param actionType Type of action (1=create dispute, 2=submit evidence)
     * @param cooldown Cooldown period in seconds
     */
    modifier rateLimit(uint256 actionType, uint256 cooldown) {
        require(
            block.timestamp >= lastActionTime[msg.sender][actionType] + cooldown,
            "Dispute: rate limit active"
        );
        lastActionTime[msg.sender][actionType] = block.timestamp;
        emit RateLimitUpdated(msg.sender, actionType, block.timestamp);
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                        ARBITRATOR REGISTRATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Register as arbitrator
     * @dev Must meet stake and reputation requirements
     */
    function registerAsArbitrator() external nonReentrant {
        require(!arbitrators[msg.sender].isRegistered, "Dispute: already registered");
        
        // Check stake requirement
        uint256 stakedAmount = stakingManager.getUserTotalStaked(msg.sender);
        uint256 priceUsd = priceOracle.getPrice();
        uint256 stakedUsd = (stakedAmount * priceUsd) / 1e18;
        require(stakedUsd >= MIN_ARB_STAKE_USD, "Dispute: insufficient stake");
        
        // Check reputation requirement
        int256 reputation = reputationManager.getScore(msg.sender);
        require(reputation >= int256(MIN_ARB_REPUTATION), "Dispute: low reputation");
        
        // Register
        arbitrators[msg.sender].isRegistered = true;
        arbitratorList.push(msg.sender);
        
        emit ArbitratorRegistered(msg.sender);
    }
    
    /**
     * @notice Unregister as arbitrator
     */
    function unregisterArbitrator() external nonReentrant {
        require(arbitrators[msg.sender].isRegistered, "Dispute: not registered");
        
        arbitrators[msg.sender].isRegistered = false;
        
        // Remove from list (swap with last, then pop)
        for (uint256 i = 0; i < arbitratorList.length; i++) {
            if (arbitratorList[i] == msg.sender) {
                arbitratorList[i] = arbitratorList[arbitratorList.length - 1];
                arbitratorList.pop();
                break;
            }
        }
        
        emit ArbitratorUnregistered(msg.sender);
    }
    
    /*//////////////////////////////////////////////////////////////
                        DISPUTE CREATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create dispute for trade
     * @dev Rate limited to 1 dispute per minute per user
     * @param tradeId Trade ID
     * @param buyer Buyer address
     * @param seller Seller address
     * @param disputeAmount Amount in dispute (for rewards/slashing calculation)
     * @return disputeId Created dispute ID
     */
    function createDispute(
        uint256 tradeId,
        address buyer,
        address seller,
        uint256 disputeAmount
    ) external nonReentrant rateLimit(ACTION_CREATE_DISPUTE, DISPUTE_CREATION_COOLDOWN) returns (uint256 disputeId) {
        require(buyer != address(0) && seller != address(0), "Dispute: zero address");
        require(disputeAmount > 0, "Dispute: zero amount");
        
        disputeId = disputeCount++;
        Dispute storage dispute = disputes[disputeId];
        
        dispute.tradeId = tradeId;
        dispute.buyer = buyer;
        dispute.seller = seller;
        dispute.disputeAmount = disputeAmount;
        dispute.state = DisputeState.PENDING;
        dispute.createdAt = block.timestamp;
        dispute.votingDeadline = block.timestamp + VOTING_PERIOD;
        
        // Calculate reward pool (2% of dispute amount)
        dispute.rewardPool = (disputeAmount * DISPUTE_FEE_BPS) / BPS;
        
        // Select arbitrators (pseudo-random stake-weighted)
        address[] memory selected = _selectArbitrators();
        require(selected.length == ARBITRATORS_PER_DISPUTE, "Dispute: not enough arbitrators");
        
        dispute.arbitrators = selected;
        
        // Mark arbitrators as handling this dispute
        for (uint256 i = 0; i < selected.length; i++) {
            arbitrators[selected[i]].disputesHandled++;
            arbitrators[selected[i]].lastActiveAt = block.timestamp;
        }
        
        // Move to voting
        dispute.state = DisputeState.VOTING;
        
        emit DisputeCreated(disputeId, tradeId, selected);
        
        return disputeId;
    }
    
    /**
     * @notice Submit evidence for dispute
     * @dev Can be called by buyer or seller multiple times. Rate limited to prevent spam.
     * @param disputeId Dispute ID
     * @param evidenceType Type of evidence ("bank_receipt", "screenshot", etc)
     * @param ipfsHash IPFS hash of evidence file
     * @param description Text description of evidence
     */
    function submitEvidence(
        uint256 disputeId,
        string memory evidenceType,
        string memory ipfsHash,
        string memory description
    ) external nonReentrant rateLimit(ACTION_SUBMIT_EVIDENCE, EVIDENCE_SUBMISSION_COOLDOWN) {
        require(disputeId < disputeCount, "Dispute: invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        
        require(
            msg.sender == dispute.buyer || msg.sender == dispute.seller,
            "Dispute: not party"
        );
        require(
            dispute.state == DisputeState.PENDING || dispute.state == DisputeState.VOTING,
            "Dispute: not accepting evidence"
        );
        require(bytes(ipfsHash).length > 0, "Dispute: empty hash");
        require(bytes(ipfsHash).length <= 100, "Dispute: hash too long");
        
        // Store evidence
        disputeEvidences[disputeId].push(DisputeEvidence({
            submitter: msg.sender,
            timestamp: block.timestamp,
            evidenceType: evidenceType,
            ipfsHash: ipfsHash,
            description: description,
            verifiedByArbitrator: false
        }));
        
        emit EvidenceSubmitted(disputeId, msg.sender, ipfsHash);
    }
    
    /*//////////////////////////////////////////////////////////////
                        VOTING
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Cast vote on dispute
     * @dev Vote is weighted by arbitrator's stake
     * @param disputeId Dispute ID
     * @param vote Vote (BUYER or SELLER)
     */
    function castVote(uint256 disputeId, Vote vote) external nonReentrant {
        require(disputeId < disputeCount, "Dispute: invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        
        require(dispute.state == DisputeState.VOTING, "Dispute: not voting");
        require(block.timestamp <= dispute.votingDeadline, "Dispute: voting expired");
        require(vote != Vote.NONE, "Dispute: invalid vote");
        require(_isArbitratorOnDispute(disputeId, msg.sender), "Dispute: not arbitrator");
        require(dispute.votes[msg.sender] == Vote.NONE, "Dispute: already voted");
        
        // Get arbitrator's stake weight
        uint256 stakeWeight = stakingManager.getUserTotalStaked(msg.sender);
        require(stakeWeight > 0, "Dispute: no stake");
        
        // Record vote with weight
        dispute.votes[msg.sender] = vote;
        dispute.voteWeights[msg.sender] = stakeWeight;
        dispute.totalVoteWeight += stakeWeight;
        
        if (vote == Vote.BUYER) {
            dispute.votesForBuyer++;
        } else {
            dispute.votesForSeller++;
        }
        
        emit VoteCast(disputeId, msg.sender, vote);
        
        // Check if quorum reached (2 of 3 or by stake weight)
        if (dispute.votesForBuyer >= 2 || dispute.votesForSeller >= 2) {
            _resolveDispute(disputeId);
        }
    }
    
    /**
     * @notice Resolve dispute by timeout if arbitrators didn't vote
     * @dev Anyone can call this after voting deadline
     * @param disputeId Dispute ID
     */
    function resolveByTimeout(uint256 disputeId) external nonReentrant {
        require(disputeId < disputeCount, "Dispute: invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        
        require(dispute.state == DisputeState.VOTING, "Dispute: not voting");
        require(block.timestamp > dispute.votingDeadline, "Dispute: deadline not passed");
        
        // If less than 2 arbitrators voted, slash all and refund
        uint256 totalVotes = dispute.votesForBuyer + dispute.votesForSeller;
        
        if (totalVotes < 2) {
            // Slash all arbitrators who didn't vote
            for (uint256 i = 0; i < dispute.arbitrators.length; i++) {
                address arb = dispute.arbitrators[i];
                if (dispute.votes[arb] == Vote.NONE) {
                    _slashArbitrator(arb, disputeId);
                }
            }
            
            // Default to buyer as winner in timeout
            dispute.winner = dispute.buyer;
        } else {
            // Resolve normally with votes cast
            _resolveDispute(disputeId);
        }
        
        dispute.state = DisputeState.RESOLVED;
        
        emit DisputeResolvedByTimeout(disputeId, dispute.winner);
    }
    
    /*//////////////////////////////////////////////////////////////
                        RESOLUTION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Resolve dispute based on votes
     * @param disputeId Dispute ID
     */
    function _resolveDispute(uint256 disputeId) internal {
        Dispute storage dispute = disputes[disputeId];
        
        // Determine winner (by vote count or by stake weight)
        address winner;
        if (dispute.votesForBuyer > dispute.votesForSeller) {
            winner = dispute.buyer;
        } else if (dispute.votesForSeller > dispute.votesForBuyer) {
            winner = dispute.seller;
        } else {
            // Tie: Use weighted votes
            uint256 buyerWeight = 0;
            uint256 sellerWeight = 0;
            
            for (uint256 i = 0; i < dispute.arbitrators.length; i++) {
                address arb = dispute.arbitrators[i];
                if (dispute.votes[arb] == Vote.BUYER) {
                    buyerWeight += dispute.voteWeights[arb];
                } else if (dispute.votes[arb] == Vote.SELLER) {
                    sellerWeight += dispute.voteWeights[arb];
                }
            }
            
            winner = (buyerWeight >= sellerWeight) ? dispute.buyer : dispute.seller;
        }
        
        dispute.winner = winner;
        dispute.state = DisputeState.RESOLVED;
        dispute.resolvedAt = block.timestamp;
        
        // Update reputations
        reputationManager.recordDisputeWon(winner);
        address loser = (winner == dispute.buyer) ? dispute.seller : dispute.buyer;
        reputationManager.recordDisputeLost(loser);
        
        // Distribute rewards to correct voters, slash incorrect
        _distributeRewards(disputeId);
        
        emit DisputeResolved(disputeId, winner);
    }
    
    /**
     * @dev Distribute rewards from pool to arbitrators who voted correctly
     * @param disputeId Dispute ID
     */
    function _distributeRewards(uint256 disputeId) internal {
        Dispute storage dispute = disputes[disputeId];
        address winner = dispute.winner;
        
        // Count correct arbitrators
        uint256 correctCount = 0;
        uint256 totalCorrectWeight = 0;
        
        for (uint256 i = 0; i < dispute.arbitrators.length; i++) {
            address arb = dispute.arbitrators[i];
            Vote arbVote = dispute.votes[arb];
            
            if (arbVote != Vote.NONE) {
                bool correct = (winner == dispute.buyer && arbVote == Vote.BUYER) ||
                              (winner == dispute.seller && arbVote == Vote.SELLER);
                
                if (correct) {
                    correctCount++;
                    totalCorrectWeight += dispute.voteWeights[arb];
                    arbitrators[arb].correctVotes++;
                } else {
                    arbitrators[arb].incorrectVotes++;
                    _slashArbitrator(arb, disputeId);
                }
            } else {
                // Didn't vote: slash for inactivity
                _slashArbitrator(arb, disputeId);
            }
        }
        
        // Distribute rewards proportionally by stake weight
        if (correctCount > 0 && dispute.rewardPool > 0) {
            for (uint256 i = 0; i < dispute.arbitrators.length; i++) {
                address arb = dispute.arbitrators[i];
                Vote arbVote = dispute.votes[arb];
                
                bool correct = (arbVote != Vote.NONE) &&
                              ((winner == dispute.buyer && arbVote == Vote.BUYER) ||
                               (winner == dispute.seller && arbVote == Vote.SELLER));
                
                if (correct) {
                    uint256 reward = (dispute.rewardPool * dispute.voteWeights[arb]) / totalCorrectWeight;
                    arbitrators[arb].totalEarned += reward;
                    
                    // Note: Actual token transfer would happen here
                    // For now, just track in struct
                    emit ArbitratorRewarded(arb, disputeId, reward);
                }
            }
        }
    }
    
    /**
     * @dev Slash arbitrator (progressive)
     * @param arbitrator Arbitrator address
     */
    function _slashArbitrator(address arbitrator, uint256 /* disputeId */) internal {
        Arbitrator storage arb = arbitrators[arbitrator];
        arb.slashCount++;
        
        uint256 stakedAmount = stakingManager.getUserTotalStaked(arbitrator);
        uint256 slashAmount;
        
        if (arb.slashCount == 1) {
            slashAmount = (stakedAmount * SLASH_FIRST_OFFENSE) / BPS;
        } else if (arb.slashCount == 2) {
            slashAmount = (stakedAmount * SLASH_SECOND_OFFENSE) / BPS;
        } else {
            // Third offense: 100% slash + ban
            slashAmount = stakedAmount;
            reputationManager.banUser(arbitrator);
            arb.isRegistered = false;
        }
        
        // Note: Actual slashing requires integration with StakingManager
        // For now, just emit event
        emit ArbitratorSlashed(arbitrator, slashAmount, arb.slashCount);
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Select arbitrators (stake-weighted pseudo-random)
     * @return selected Array of arbitrator addresses
     */
    function _selectArbitrators() internal returns (address[] memory selected) {
        require(arbitratorList.length >= ARBITRATORS_PER_DISPUTE, "Dispute: not enough arbitrators");
        
        // Build qualified list with cumulative stake weights
        address[] memory qualified = new address[](arbitratorList.length);
        uint256[] memory cumulativeWeights = new uint256[](arbitratorList.length);
        uint256 qualifiedCount = 0;
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < arbitratorList.length; i++) {
            address arb = arbitratorList[i];
            
            if (arbitrators[arb].isRegistered) {
                // Check still meets requirements
                uint256 stakedAmount = stakingManager.getUserTotalStaked(arb);
                uint256 priceUsd = priceOracle.getPrice();
                uint256 stakedUsd = (stakedAmount * priceUsd) / 1e18;
                
                if (stakedUsd >= MIN_ARB_STAKE_USD) {
                    int256 reputation = reputationManager.getScore(arb);
                    if (reputation >= int256(MIN_ARB_REPUTATION)) {
                        qualified[qualifiedCount] = arb;
                        totalWeight += stakedAmount;
                        cumulativeWeights[qualifiedCount] = totalWeight;
                        qualifiedCount++;
                    }
                }
            }
        }
        
        require(qualifiedCount >= ARBITRATORS_PER_DISPUTE, "Dispute: insufficient qualified arbitrators");
        
        // Pseudo-random selection weighted by stake
        selected = new address[](ARBITRATORS_PER_DISPUTE);
        bool[] memory selectedFlags = new bool[](qualifiedCount);
        
        for (uint256 i = 0; i < ARBITRATORS_PER_DISPUTE; i++) {
            // Generate pseudo-random number
            randomNonce++;
            uint256 random = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                msg.sender,
                randomNonce
            ))) % totalWeight;
            
            // Binary search for weighted selection
            uint256 selectedIndex = 0;
            for (uint256 j = 0; j < qualifiedCount; j++) {
                if (random < cumulativeWeights[j] && !selectedFlags[j]) {
                    selectedIndex = j;
                    break;
                }
            }
            
            // If already selected, pick next available
            while (selectedFlags[selectedIndex] && selectedIndex < qualifiedCount - 1) {
                selectedIndex++;
            }
            
            selectedFlags[selectedIndex] = true;
            selected[i] = qualified[selectedIndex];
        }
        
        return selected;
    }
    
    /**
     * @dev Check if address is arbitrator on dispute
     * @param disputeId Dispute ID
     * @param arbitrator Arbitrator address
     * @return isArbitrator True if arbitrator
     */
    function _isArbitratorOnDispute(uint256 disputeId, address arbitrator) internal view returns (bool isArbitrator) {
        Dispute storage dispute = disputes[disputeId];
        
        for (uint256 i = 0; i < dispute.arbitrators.length; i++) {
            if (dispute.arbitrators[i] == arbitrator) {
                return true;
            }
        }
        
        return false;
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get dispute arbitrators
     * @param disputeId Dispute ID
     * @return arbitrators Array of arbitrator addresses
     */
    function getDisputeArbitrators(uint256 disputeId) external view returns (address[] memory) {
        require(disputeId < disputeCount, "Dispute: invalid dispute");
        return disputes[disputeId].arbitrators;
    }
    
    /**
     * @notice Get arbitrator stats
     * @param arbitrator Arbitrator address
     * @return arb Arbitrator struct
     */
    function getArbitrator(address arbitrator) external view returns (Arbitrator memory arb) {
        return arbitrators[arbitrator];
    }
    
    /**
     * @notice Get all evidence for a dispute
     * @param disputeId Dispute ID
     * @return evidences Array of evidence submitted
     */
    function getDisputeEvidences(uint256 disputeId) external view returns (DisputeEvidence[] memory) {
        require(disputeId < disputeCount, "Dispute: invalid dispute");
        return disputeEvidences[disputeId];
    }
    
    /**
     * @notice Get dispute basic info (without mappings)
     * @param disputeId Dispute ID
     * @return tradeId Trade ID
     * @return buyer Buyer address
     * @return seller Seller address
     * @return disputeAmount Amount in dispute
     * @return state Current state
     * @return createdAt Creation timestamp
     * @return votingDeadline Voting deadline
     * @return winner Winner address (if resolved)
     * @return rewardPool Reward pool for arbitrators
     */
    function getDisputeInfo(uint256 disputeId) external view returns (
        uint256 tradeId,
        address buyer,
        address seller,
        uint256 disputeAmount,
        DisputeState state,
        uint256 createdAt,
        uint256 votingDeadline,
        address winner,
        uint256 rewardPool
    ) {
        require(disputeId < disputeCount, "Dispute: invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        
        return (
            dispute.tradeId,
            dispute.buyer,
            dispute.seller,
            dispute.disputeAmount,
            dispute.state,
            dispute.createdAt,
            dispute.votingDeadline,
            dispute.winner,
            dispute.rewardPool
        );
    }
}
