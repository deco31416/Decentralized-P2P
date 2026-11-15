// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ReputationManagerV2
 * @notice Behavioral identity system without KYC
 * @dev Tracks user actions and calculates reputation score (0-1000)
 * 
 * Score Changes:
 *      Trade OK:     +10
 *      Trade Fail:   -50
 *      Dispute Won:  +30
 *      Dispute Lost: -80
 *      Score Range:  0-1000
 * 
 * Architecture:
 *      - No personal data stored (only address)
 *      - Score impacts trade limits and arbitrator eligibility
 *      - Cannot be gamed (requires actual trade history)
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract ReputationManagerV2 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Maximum reputation score
    uint256 public constant MAX_SCORE = 1000;
    
    /// @notice Starting score for new users
    uint256 public constant STARTING_SCORE = 500;
    
    /// @notice Points for successful trade
    int256 public constant POINTS_TRADE_OK = 10;
    
    /// @notice Penalty for failed trade
    int256 public constant POINTS_TRADE_FAIL = -50;
    
    /// @notice Points for winning dispute
    int256 public constant POINTS_DISPUTE_WON = 30;
    
    /// @notice Penalty for losing dispute
    int256 public constant POINTS_DISPUTE_LOST = -80;
    
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct UserReputation {
        uint256 score;              // Current score (0-1000)
        uint256 tradesCompleted;    // Total successful trades
        uint256 tradesFailed;       // Total failed trades
        uint256 disputesWon;        // Disputes won as party
        uint256 disputesLost;       // Disputes lost as party
        uint256 lastUpdate;         // Last score update timestamp
        bool isBanned;              // Permanent ban flag
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice User reputation data
    mapping(address => UserReputation) public reputations;
    
    /// @notice Authorized contracts (TradeEscrow, DisputeManager)
    mapping(address => bool) public authorizedContracts;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event ReputationUpdated(address indexed user, uint256 newScore, int256 change);
    event UserBanned(address indexed user);
    event UserUnbanned(address indexed user);
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "Reputation: zero address");
    }
    
    /*//////////////////////////////////////////////////////////////
                        REPUTATION TRACKING
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Record successful trade
     * @param user User address
     */
    function recordTradeSuccess(address user) external onlyAuthorized {
        require(!reputations[user].isBanned, "Reputation: user banned");
        
        UserReputation storage rep = reputations[user];
        
        // Initialize if first interaction
        if (rep.lastUpdate == 0) {
            rep.score = STARTING_SCORE;
        }
        
        // Update score
        rep.score = _adjustScore(rep.score, POINTS_TRADE_OK);
        rep.tradesCompleted++;
        rep.lastUpdate = block.timestamp;
        
        emit ReputationUpdated(user, rep.score, POINTS_TRADE_OK);
    }
    
    /**
     * @notice Record failed trade
     * @param user User address
     */
    function recordTradeFail(address user) external onlyAuthorized {
        require(!reputations[user].isBanned, "Reputation: user banned");
        
        UserReputation storage rep = reputations[user];
        
        // Initialize if first interaction
        if (rep.lastUpdate == 0) {
            rep.score = STARTING_SCORE;
        }
        
        // Update score
        rep.score = _adjustScore(rep.score, POINTS_TRADE_FAIL);
        rep.tradesFailed++;
        rep.lastUpdate = block.timestamp;
        
        emit ReputationUpdated(user, rep.score, POINTS_TRADE_FAIL);
    }
    
    /**
     * @notice Record dispute won
     * @param user User address
     */
    function recordDisputeWon(address user) external onlyAuthorized {
        require(!reputations[user].isBanned, "Reputation: user banned");
        
        UserReputation storage rep = reputations[user];
        
        // Initialize if first interaction
        if (rep.lastUpdate == 0) {
            rep.score = STARTING_SCORE;
        }
        
        // Update score
        rep.score = _adjustScore(rep.score, POINTS_DISPUTE_WON);
        rep.disputesWon++;
        rep.lastUpdate = block.timestamp;
        
        emit ReputationUpdated(user, rep.score, POINTS_DISPUTE_WON);
    }
    
    /**
     * @notice Record dispute lost
     * @param user User address
     */
    function recordDisputeLost(address user) external onlyAuthorized {
        require(!reputations[user].isBanned, "Reputation: user banned");
        
        UserReputation storage rep = reputations[user];
        
        // Initialize if first interaction
        if (rep.lastUpdate == 0) {
            rep.score = STARTING_SCORE;
        }
        
        // Update score
        rep.score = _adjustScore(rep.score, POINTS_DISPUTE_LOST);
        rep.disputesLost++;
        rep.lastUpdate = block.timestamp;
        
        emit ReputationUpdated(user, rep.score, POINTS_DISPUTE_LOST);
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get user's current reputation score
     * @param user User address
     * @return score Reputation score (0-1000)
     */
    function getScore(address user) external view returns (uint256 score) {
        UserReputation memory rep = reputations[user];
        
        // Return starting score if no history
        if (rep.lastUpdate == 0) {
            return STARTING_SCORE;
        }
        
        return rep.score;
    }
    
    /**
     * @notice Get full reputation data
     * @param user User address
     * @return rep UserReputation struct
     */
    function getReputation(address user) external view returns (UserReputation memory rep) {
        rep = reputations[user];
        
        // Initialize defaults if no history
        if (rep.lastUpdate == 0) {
            rep.score = STARTING_SCORE;
        }
        
        return rep;
    }
    
    /**
     * @notice Check if user is banned
     * @param user User address
     * @return banned True if banned
     */
    function isBanned(address user) external view returns (bool banned) {
        return reputations[user].isBanned;
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Adjust score with bounds checking
     * @param currentScore Current score
     * @param change Score change (can be negative)
     * @return newScore Adjusted score (0-1000)
     */
    function _adjustScore(uint256 currentScore, int256 change) internal pure returns (uint256 newScore) {
        int256 newScoreInt = int256(currentScore) + change;
        
        // Clamp to [0, MAX_SCORE]
        if (newScoreInt < 0) {
            newScore = 0;
        } else if (newScoreInt > int256(MAX_SCORE)) {
            newScore = MAX_SCORE;
        } else {
            newScore = uint256(newScoreInt);
        }
        
        return newScore;
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS (OWNER)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Ban user (emergency only)
     * @param user User to ban
     */
    function banUser(address user) external onlyOwner {
        reputations[user].isBanned = true;
        emit UserBanned(user);
    }
    
    /**
     * @notice Unban user
     * @param user User to unban
     */
    function unbanUser(address user) external onlyOwner {
        reputations[user].isBanned = false;
        emit UserUnbanned(user);
    }
    
    /**
     * @notice Authorize contract to update reputations
     * @param contractAddress Contract to authorize
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedContract(address contractAddress, bool authorized) external onlyOwner {
        require(contractAddress != address(0), "Reputation: zero address");
        authorizedContracts[contractAddress] = authorized;
        emit ContractAuthorized(contractAddress, authorized);
    }
    
    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender], "Reputation: not authorized");
        _;
    }
}
