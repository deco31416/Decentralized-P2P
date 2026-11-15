// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ILiquidityEngine.sol";

/**
 * @title TreasuryManagerV2
 * @notice Single fee sink with automated distribution
 * @dev ALL protocol fees flow here first, then distributed
 * 
 * Distribution:
 *      25% Staking rewards
 *      20% Treasury (SocialFi/Lottery)
 *      15% Referral rewards
 *      10% Retained earnings 🔒
 *      10% Validator rewards
 *      10% SocialFi pool
 *      5% Lottery pool
 *      5% Market operations
 * 
 * Architecture:
 *      - Collects fees from TradeEscrow
 *      - Distributes to multiple destinations
 *      - Auto-triggers LiquidityEngine
 *      - Emergency withdrawals
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract TreasuryManagerV2 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Distribution percentages (bps)
    uint256 public constant STAKING_PERCENT = 2500;     // 25%
    uint256 public constant TREASURY_PERCENT = 2000;    // 20%
    uint256 public constant REFERRAL_PERCENT = 1500;    // 15%
    uint256 public constant RETAINED_PERCENT = 1000;    // 10%
    uint256 public constant VALIDATOR_PERCENT = 1000;   // 10%
    uint256 public constant SOCIALFI_PERCENT = 1000;    // 10%
    uint256 public constant LOTTERY_PERCENT = 500;      // 5%
    uint256 public constant MARKET_OPS_PERCENT = 500;   // 5%
    
    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;
    
    /// @notice Auto-buyback threshold ($1000 USDC)
    uint256 public constant BUYBACK_THRESHOLD = 1000e6;
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC token
    IERC20 public immutable usdc;
    
    /// @notice Liquidity engine
    ILiquidityEngine public liquidityEngine;
    
    /// @notice Destination wallets
    address public stakingPool;
    address public treasuryWallet;
    address public referralPool;
    address public retainedEarnings;
    address public validatorPool;
    address public socialFiPool;
    address public lotteryPool;
    address public marketOpsWallet;
    
    /// @notice Total fees collected
    uint256 public totalFeesCollected;
    
    /// @notice Total fees distributed
    uint256 public totalFeesDistributed;
    
    /// @notice Pending distribution buffer
    uint256 public pendingDistribution;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event FeesCollected(uint256 amount);
    event FeesDistributed(uint256 amount);
    event BuybackTriggered(uint256 amount);
    event WalletUpdated(string walletType, address newWallet);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address initialOwner,
        address _usdc,
        address _liquidityEngine,
        address _stakingPool,
        address _treasuryWallet,
        address _referralPool,
        address _retainedEarnings,
        address _validatorPool,
        address _socialFiPool,
        address _lotteryPool,
        address _marketOpsWallet
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Treasury: zero owner");
        require(_usdc != address(0), "Treasury: zero usdc");
        
        usdc = IERC20(_usdc);
        liquidityEngine = ILiquidityEngine(_liquidityEngine);
        
        stakingPool = _stakingPool;
        treasuryWallet = _treasuryWallet;
        referralPool = _referralPool;
        retainedEarnings = _retainedEarnings;
        validatorPool = _validatorPool;
        socialFiPool = _socialFiPool;
        lotteryPool = _lotteryPool;
        marketOpsWallet = _marketOpsWallet;
    }
    
    /*//////////////////////////////////////////////////////////////
                        FEE COLLECTION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Receive fees from protocol
     * @param amount Fee amount (6 decimals)
     */
    function collectFees(uint256 amount) external nonReentrant {
        require(amount > 0, "Treasury: zero amount");
        
        // Transfer fees to treasury
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update stats
        totalFeesCollected += amount;
        pendingDistribution += amount;
        
        emit FeesCollected(amount);
        
        // Auto-distribute if threshold reached
        if (pendingDistribution >= BUYBACK_THRESHOLD) {
            _distributeFees();
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        FEE DISTRIBUTION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Distribute pending fees
     * @dev Can be called by anyone
     */
    function distributeFees() external nonReentrant {
        require(pendingDistribution > 0, "Treasury: nothing to distribute");
        _distributeFees();
    }
    
    /**
     * @dev Internal distribution logic
     */
    function _distributeFees() internal {
        uint256 amount = pendingDistribution;
        require(amount > 0, "Treasury: zero amount");
        
        // Calculate distributions
        uint256 toStaking = (amount * STAKING_PERCENT) / BPS;
        uint256 toTreasury = (amount * TREASURY_PERCENT) / BPS;
        uint256 toReferral = (amount * REFERRAL_PERCENT) / BPS;
        uint256 toRetained = (amount * RETAINED_PERCENT) / BPS;
        uint256 toValidator = (amount * VALIDATOR_PERCENT) / BPS;
        uint256 toSocialFi = (amount * SOCIALFI_PERCENT) / BPS;
        uint256 toLottery = (amount * LOTTERY_PERCENT) / BPS;
        uint256 toMarketOps = (amount * MARKET_OPS_PERCENT) / BPS;
        
        // Distribute
        if (stakingPool != address(0)) usdc.safeTransfer(stakingPool, toStaking);
        if (treasuryWallet != address(0)) usdc.safeTransfer(treasuryWallet, toTreasury);
        if (referralPool != address(0)) usdc.safeTransfer(referralPool, toReferral);
        if (retainedEarnings != address(0)) usdc.safeTransfer(retainedEarnings, toRetained);
        if (validatorPool != address(0)) usdc.safeTransfer(validatorPool, toValidator);
        if (socialFiPool != address(0)) usdc.safeTransfer(socialFiPool, toSocialFi);
        if (lotteryPool != address(0)) usdc.safeTransfer(lotteryPool, toLottery);
        if (marketOpsWallet != address(0)) usdc.safeTransfer(marketOpsWallet, toMarketOps);
        
        // Update stats
        totalFeesDistributed += amount;
        pendingDistribution = 0;
        
        emit FeesDistributed(amount);
        
        // Trigger buyback if threshold met
        if (address(liquidityEngine) != address(0) && amount >= BUYBACK_THRESHOLD) {
            liquidityEngine.executeBuyback();
            emit BuybackTriggered(amount);
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get treasury balance
     * @return balance USDC balance (6 decimals)
     */
    function getBalance() external view returns (uint256 balance) {
        return usdc.balanceOf(address(this));
    }
    
    /**
     * @notice Get pending distribution amount
     * @return pending Pending amount (6 decimals)
     */
    function getPendingDistribution() external view returns (uint256 pending) {
        return pendingDistribution;
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS (OWNER)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update destination wallet
     * @param walletType Wallet identifier
     * @param newWallet New wallet address
     */
    function setWallet(string calldata walletType, address newWallet) external onlyOwner {
        require(newWallet != address(0), "Treasury: zero address");
        
        bytes32 hash = keccak256(bytes(walletType));
        
        if (hash == keccak256(bytes("staking"))) {
            stakingPool = newWallet;
        } else if (hash == keccak256(bytes("treasury"))) {
            treasuryWallet = newWallet;
        } else if (hash == keccak256(bytes("referral"))) {
            referralPool = newWallet;
        } else if (hash == keccak256(bytes("retained"))) {
            retainedEarnings = newWallet;
        } else if (hash == keccak256(bytes("validator"))) {
            validatorPool = newWallet;
        } else if (hash == keccak256(bytes("socialfi"))) {
            socialFiPool = newWallet;
        } else if (hash == keccak256(bytes("lottery"))) {
            lotteryPool = newWallet;
        } else if (hash == keccak256(bytes("marketops"))) {
            marketOpsWallet = newWallet;
        } else {
            revert("Treasury: invalid wallet type");
        }
        
        emit WalletUpdated(walletType, newWallet);
    }
    
    /**
     * @notice Update liquidity engine
     * @param newEngine New engine address
     */
    function setLiquidityEngine(address newEngine) external onlyOwner {
        liquidityEngine = ILiquidityEngine(newEngine);
    }
    
    /**
     * @notice Emergency withdrawal (owner only)
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     * @param to Destination address
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        require(to != address(0), "Treasury: zero address");
        IERC20(token).safeTransfer(to, amount);
    }
}
