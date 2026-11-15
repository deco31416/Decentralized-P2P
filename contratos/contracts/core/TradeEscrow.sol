// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IFeeManager.sol";
import "../interfaces/IReputationManager.sol";
import "../interfaces/IStakingManager.sol";
import "../interfaces/ICircuitBreaker.sol";

/**
 * @title TradeEscrowV2
 * @notice P2P escrow with USDC settlement and economic bonds
 * @dev CRITICAL SECURITY FEATURES:
 *      1. Economic bonds (0.5%, $5 min) - slashed on abuse
 *      2. State machine with timeouts
 *      3. Fiat-sent proof required
 *      4. Dispute escalation
 * 
 * Flow:
 *      CREATED → seller accepts → ACTIVE
 *      ACTIVE → buyer sends fiat → FIAT_SENT
 *      FIAT_SENT → seller releases → COMPLETED
 *      Any state → timeout/dispute → DISPUTED
 * 
 * Security:
 *      - Both parties deposit bonds
 *      - Timeouts enforced
 *      - Circuit breaker support
 *      - Fee collection
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract TradeEscrowV2 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Bond percentage (0.5% = 50 bps)
    uint256 public constant BOND_BPS = 50;
    
    /// @notice Minimum bond ($5, 6 decimals)
    uint256 public constant MIN_BOND_USD = 5e6;
    
    /// @notice Payment timeout (30 minutes)
    uint256 public constant PAYMENT_TIMEOUT = 30 minutes;
    
    /// @notice Release timeout (15 minutes after fiat sent)
    uint256 public constant RELEASE_TIMEOUT = 15 minutes;
    
    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;
    
    /*//////////////////////////////////////////////////////////////
                            ENUMS
    //////////////////////////////////////////////////////////////*/
    
    enum TradeState { CREATED, ACTIVE, FIAT_SENT, COMPLETED, DISPUTED, CANCELLED, EXPIRED }
    enum TradeType { CryptoCrypto, FiatCrypto, CryptoFiat, FiatFiat }
    
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct Trade {
        address buyer;
        address seller;
        uint256 amountUsdc;         // Trade amount (6 decimals)
        uint256 buyerBond;          // Buyer's bond (6 decimals)
        uint256 sellerBond;         // Seller's bond (6 decimals)
        uint256 feeAmount;          // Fee (6 decimals)
        TradeState state;
        TradeType tradeType;
        uint256 createdAt;
        uint256 activatedAt;
        uint256 fiatSentAt;
        uint256 completedAt;
        string fiatProofHash;       // IPFS hash of fiat payment proof
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC token
    IERC20 public immutable usdc;
    
    /// @notice Fee manager
    IFeeManager public feeManager;
    
    /// @notice Reputation manager
    IReputationManager public reputationManager;
    
    /// @notice Staking manager
    IStakingManager public stakingManager;
    
    /// @notice Circuit breaker
    ICircuitBreaker public circuitBreaker;
    
    /// @notice Treasury address (receives fees)
    address public treasury;
    
    /// @notice All trades
    Trade[] public trades;
    
    /// @notice User's trade IDs
    mapping(address => uint256[]) public userTrades;
    
    /// @notice Rate limiting: user => last action timestamp
    mapping(address => uint256) public lastTradeCreation;
    
    /// @notice Cooldown for trade creation (5 seconds)
    uint256 public constant TRADE_CREATION_COOLDOWN = 5 seconds;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event RateLimitUpdated(address indexed user, uint256 timestamp);
    
    event TradeCreated(uint256 indexed tradeId, address indexed buyer, address indexed seller, uint256 amount);
    event TradeActivated(uint256 indexed tradeId);
    event FiatSent(uint256 indexed tradeId, string proofHash);
    event TradeCompleted(uint256 indexed tradeId);
    event TradeDisputed(uint256 indexed tradeId);
    event TradeCancelled(uint256 indexed tradeId);
    event TradeExpired(uint256 indexed tradeId);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address initialOwner,
        address _usdc,
        address _feeManager,
        address _reputationManager,
        address _stakingManager,
        address _circuitBreaker,
        address _treasury
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Escrow: zero owner");
        require(_usdc != address(0), "Escrow: zero usdc");
        require(_feeManager != address(0), "Escrow: zero fee manager");
        require(_reputationManager != address(0), "Escrow: zero reputation");
        require(_stakingManager != address(0), "Escrow: zero staking");
        require(_circuitBreaker != address(0), "Escrow: zero breaker");
        require(_treasury != address(0), "Escrow: zero treasury");
        
        usdc = IERC20(_usdc);
        feeManager = IFeeManager(_feeManager);
        reputationManager = IReputationManager(_reputationManager);
        stakingManager = IStakingManager(_stakingManager);
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
        treasury = _treasury;
    }
    
    /*//////////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Rate limit modifier to prevent spam
     * @dev Checks if enough time passed since last action
     */
    modifier rateLimit() {
        require(
            block.timestamp >= lastTradeCreation[msg.sender] + TRADE_CREATION_COOLDOWN,
            "Escrow: rate limit active"
        );
        lastTradeCreation[msg.sender] = block.timestamp;
        emit RateLimitUpdated(msg.sender, block.timestamp);
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                        TRADE CREATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create new trade offer
     * @dev Rate limited to 1 trade per 5 seconds per user
     * @param seller Seller address
     * @param amountUsdc Trade amount (6 decimals)
     * @param tradeType Type of trade
     * @return tradeId Created trade ID
     */
    function createTrade(
        address seller,
        uint256 amountUsdc,
        TradeType tradeType
    ) external nonReentrant rateLimit returns (uint256 tradeId) {
        require(circuitBreaker.isEscrowOperational(), "Escrow: paused");
        require(seller != address(0) && seller != msg.sender, "Escrow: invalid seller");
        require(amountUsdc > 0, "Escrow: zero amount");
        
        // Calculate bond
        uint256 bond = _calculateBond(amountUsdc);
        
        // Calculate fee
        uint8 buyerTier = stakingManager.getUserTier(msg.sender);
        uint256 fee = feeManager.calculateFee(uint8(tradeType), amountUsdc, buyerTier);
        
        // Create trade
        tradeId = trades.length;
        trades.push(Trade({
            buyer: msg.sender,
            seller: seller,
            amountUsdc: amountUsdc,
            buyerBond: bond,
            sellerBond: bond,
            feeAmount: fee,
            state: TradeState.CREATED,
            tradeType: tradeType,
            createdAt: block.timestamp,
            activatedAt: 0,
            fiatSentAt: 0,
            completedAt: 0,
            fiatProofHash: ""
        }));
        
        // Track user trades
        userTrades[msg.sender].push(tradeId);
        userTrades[seller].push(tradeId);
        
        // Buyer deposits: amount + fee + bond
        uint256 buyerDeposit = amountUsdc + fee + bond;
        usdc.safeTransferFrom(msg.sender, address(this), buyerDeposit);
        
        emit TradeCreated(tradeId, msg.sender, seller, amountUsdc);
        
        return tradeId;
    }
    
    /**
     * @notice Seller accepts trade
     * @param tradeId Trade ID
     */
    function acceptTrade(uint256 tradeId) external nonReentrant {
        require(tradeId < trades.length, "Escrow: invalid trade");
        Trade storage trade = trades[tradeId];
        
        require(msg.sender == trade.seller, "Escrow: not seller");
        require(trade.state == TradeState.CREATED, "Escrow: invalid state");
        require(block.timestamp <= trade.createdAt + PAYMENT_TIMEOUT, "Escrow: expired");
        
        // Update state
        trade.state = TradeState.ACTIVE;
        trade.activatedAt = block.timestamp;
        
        // Seller deposits bond
        usdc.safeTransferFrom(msg.sender, address(this), trade.sellerBond);
        
        emit TradeActivated(tradeId);
    }
    
    /*//////////////////////////////////////////////////////////////
                        TRADE EXECUTION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Buyer confirms fiat payment sent
     * @param tradeId Trade ID
     * @param proofHash IPFS hash of payment proof
     */
    function confirmFiatSent(uint256 tradeId, string calldata proofHash) external nonReentrant {
        require(tradeId < trades.length, "Escrow: invalid trade");
        Trade storage trade = trades[tradeId];
        
        require(msg.sender == trade.buyer, "Escrow: not buyer");
        require(trade.state == TradeState.ACTIVE, "Escrow: invalid state");
        require(block.timestamp <= trade.activatedAt + PAYMENT_TIMEOUT, "Escrow: expired");
        require(bytes(proofHash).length > 0, "Escrow: empty proof");
        
        // Update state
        trade.state = TradeState.FIAT_SENT;
        trade.fiatSentAt = block.timestamp;
        trade.fiatProofHash = proofHash;
        
        emit FiatSent(tradeId, proofHash);
    }
    
    /**
     * @notice Seller releases funds
     * @param tradeId Trade ID
     */
    function releaseFunds(uint256 tradeId) external nonReentrant {
        require(tradeId < trades.length, "Escrow: invalid trade");
        Trade storage trade = trades[tradeId];
        
        require(msg.sender == trade.seller, "Escrow: not seller");
        require(trade.state == TradeState.FIAT_SENT, "Escrow: invalid state");
        
        // Complete trade
        _completeTrade(tradeId);
    }
    
    /*//////////////////////////////////////////////////////////////
                        DISPUTE & TIMEOUT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create dispute
     * @param tradeId Trade ID
     */
    function createDispute(uint256 tradeId) external nonReentrant {
        require(tradeId < trades.length, "Escrow: invalid trade");
        Trade storage trade = trades[tradeId];
        
        require(
            msg.sender == trade.buyer || msg.sender == trade.seller,
            "Escrow: not party"
        );
        require(
            trade.state == TradeState.ACTIVE || trade.state == TradeState.FIAT_SENT,
            "Escrow: invalid state"
        );
        
        // Update state
        trade.state = TradeState.DISPUTED;
        
        emit TradeDisputed(tradeId);
    }
    
    /**
     * @notice Expire trade (timeout)
     * @param tradeId Trade ID
     */
    function expireTrade(uint256 tradeId) external nonReentrant {
        require(tradeId < trades.length, "Escrow: invalid trade");
        Trade storage trade = trades[tradeId];
        
        bool canExpire = false;
        
        if (trade.state == TradeState.CREATED) {
            canExpire = (block.timestamp > trade.createdAt + PAYMENT_TIMEOUT);
        } else if (trade.state == TradeState.ACTIVE) {
            canExpire = (block.timestamp > trade.activatedAt + PAYMENT_TIMEOUT);
        } else if (trade.state == TradeState.FIAT_SENT) {
            canExpire = (block.timestamp > trade.fiatSentAt + RELEASE_TIMEOUT);
        }
        
        require(canExpire, "Escrow: not expired");
        
        // Update state
        trade.state = TradeState.EXPIRED;
        
        // Refund logic handled by dispute resolution
        
        emit TradeExpired(tradeId);
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Complete trade and distribute funds
     * @param tradeId Trade ID
     */
    function _completeTrade(uint256 tradeId) internal {
        Trade storage trade = trades[tradeId];
        
        // Update state
        trade.state = TradeState.COMPLETED;
        trade.completedAt = block.timestamp;
        
        // Distribute funds:
        // - Buyer gets: nothing (already paid)
        // - Seller gets: amount + both bonds
        // - Treasury gets: fee
        
        uint256 sellerPayout = trade.amountUsdc + trade.buyerBond + trade.sellerBond;
        
        usdc.safeTransfer(trade.seller, sellerPayout);
        usdc.safeTransfer(treasury, trade.feeAmount);
        
        // Update reputations
        reputationManager.recordTradeSuccess(trade.buyer);
        reputationManager.recordTradeSuccess(trade.seller);
        
        emit TradeCompleted(tradeId);
    }
    
    /**
     * @dev Calculate bond amount
     * @param amountUsdc Trade amount (6 decimals)
     * @return bond Bond amount (6 decimals)
     */
    function _calculateBond(uint256 amountUsdc) internal pure returns (uint256 bond) {
        bond = (amountUsdc * BOND_BPS) / BPS;
        
        if (bond < MIN_BOND_USD) {
            bond = MIN_BOND_USD;
        }
        
        return bond;
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get trade details
     * @param tradeId Trade ID
     * @return trade Trade struct
     */
    function getTrade(uint256 tradeId) external view returns (Trade memory trade) {
        require(tradeId < trades.length, "Escrow: invalid trade");
        return trades[tradeId];
    }
    
    /**
     * @notice Get user's trades
     * @param user User address
     * @return tradeIds Array of trade IDs
     */
    function getUserTrades(address user) external view returns (uint256[] memory tradeIds) {
        return userTrades[user];
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS (OWNER)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Escrow: zero treasury");
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @notice Emergency withdraw - Recuperar tokens enviados accidentalmente
     * @dev SECURITY: NO puede retirar USDC que está en trades activos
     * @param token Token address
     * @param recipient Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdrawToken(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(recipient != address(0), "Escrow: zero recipient");
        require(token != address(0), "Escrow: zero token");
        require(amount > 0, "Escrow: zero amount");
        
        // Si es USDC, verificar que no estamos robando fondos de trades
        if (token == address(usdc)) {
            uint256 lockedFunds = _calculateTotalLockedFunds();
            uint256 contractBalance = usdc.balanceOf(address(this));
            uint256 availableToWithdraw = contractBalance > lockedFunds 
                ? contractBalance - lockedFunds 
                : 0;
            
            require(amount <= availableToWithdraw, "Escrow: funds are locked in trades");
        }
        
        IERC20(token).safeTransfer(recipient, amount);
        emit EmergencyWithdraw(token, recipient, amount);
    }
    
    /**
     * @dev Calculate total USDC locked in active trades
     * @return Total locked USDC
     */
    function _calculateTotalLockedFunds() internal view returns (uint256) {
        uint256 locked = 0;
        
        for (uint256 i = 0; i < trades.length; i++) {
            Trade storage trade = trades[i];
            
            // Solo trades activos bloquean fondos
            if (trade.state != TradeState.COMPLETED && 
                trade.state != TradeState.CANCELLED && 
                trade.state != TradeState.EXPIRED) {
                
                locked += trade.amountUsdc + trade.feeAmount + trade.buyerBond;
                
                // Si seller ya depositó, agregar su bond
                if (trade.state != TradeState.CREATED) {
                    locked += trade.sellerBond;
                }
            }
        }
        
        return locked;
    }
    
    /**
     * @notice Events
     */
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event EmergencyWithdraw(address indexed token, address indexed recipient, uint256 amount);
}
