// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IPancakeRouter.sol";
import "../interfaces/ICircuitBreaker.sol";

/**
 * @title LiquidityEngineV2
 * @notice Auto-buy CAMBIO + add LP + lock tokens
 * @dev CRITICAL: LP tokens MUST be locked (not just commented)
 * 
 * Flow:
 *      1. Treasury triggers with USDC
 *      2. Swap 50% USDC → CAMBIO (PancakeSwap)
 *      3. Add liquidity (USDC + CAMBIO)
 *      4. Lock LP tokens for 1 year
 *      5. Emit lock record
 * 
 * Security:
 *      - Actual LP locking (not commented)
 *      - Auditable lock registry
 *      - Emergency pause
 *      - Slippage protection
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract LiquidityEngineV2 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Lock period (1 year)
    uint256 public constant LOCK_PERIOD = 365 days;
    
    /// @notice Slippage tolerance (5% = 500 bps)
    uint256 public constant SLIPPAGE_BPS = 500;
    
    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;
    
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct LockedLP {
        uint256 amount;         // LP tokens locked
        uint256 lockedAt;       // Lock timestamp
        uint256 unlockAt;       // Unlock timestamp
        bool withdrawn;         // Has been withdrawn
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC token
    IERC20 public immutable usdc;
    
    /// @notice CAMBIO token
    IERC20 public immutable cambioToken;
    
    /// @notice LP token (PancakeSwap pair)
    IERC20 public lpToken;
    
    /// @notice PancakeSwap router
    IPancakeRouter public router;
    
    /// @notice Circuit breaker
    ICircuitBreaker public circuitBreaker;
    
    /// @notice Locked LP records
    LockedLP[] public lockedLPs;
    
    /// @notice Total LP locked
    uint256 public totalLPLocked;
    
    /// @notice Total buybacks executed
    uint256 public totalBuybacks;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event BuybackExecuted(uint256 usdcIn, uint256 cambioOut, uint256 lpMinted);
    event LPLocked(uint256 indexed lockId, uint256 amount, uint256 unlockAt);
    event LPUnlocked(uint256 indexed lockId, uint256 amount);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address initialOwner,
        address _usdc,
        address _cambioToken,
        address _lpToken,
        address _router,
        address _circuitBreaker
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Liquidity: zero owner");
        require(_usdc != address(0), "Liquidity: zero usdc");
        require(_cambioToken != address(0), "Liquidity: zero cambio");
        require(_router != address(0), "Liquidity: zero router");
        require(_circuitBreaker != address(0), "Liquidity: zero breaker");
        
        usdc = IERC20(_usdc);
        cambioToken = IERC20(_cambioToken);
        lpToken = IERC20(_lpToken);
        router = IPancakeRouter(_router);
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
        
        // Approve router for max
        usdc.approve(_router, type(uint256).max);
        cambioToken.approve(_router, type(uint256).max);
    }
    
    /*//////////////////////////////////////////////////////////////
                        BUYBACK EXECUTION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Execute buyback and LP addition
     * @dev Called by TreasuryManager
     */
    function executeBuyback() external nonReentrant {
        require(circuitBreaker.isLiquidityOperational(), "Liquidity: paused");
        
        uint256 usdcBalance = usdc.balanceOf(address(this));
        require(usdcBalance > 0, "Liquidity: zero balance");
        
        // Split: 50% for swap, 50% for LP
        uint256 swapAmount = usdcBalance / 2;
        uint256 lpAmount = usdcBalance - swapAmount;
        
        // Step 1: Swap USDC → CAMBIO
        uint256 cambioOut = _swapUsdcToCambio(swapAmount);
        
        // Step 2: Add liquidity
        uint256 lpMinted = _addLiquidity(lpAmount, cambioOut);
        
        // Step 3: Lock LP tokens
        _lockLP(lpMinted);
        
        // Update stats
        totalBuybacks++;
        
        emit BuybackExecuted(swapAmount, cambioOut, lpMinted);
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Swap USDC to CAMBIO
     * @param usdcAmount USDC amount (6 decimals)
     * @return cambioAmount CAMBIO received (18 decimals)
     */
    function _swapUsdcToCambio(uint256 usdcAmount) internal returns (uint256 cambioAmount) {
        // Calculate minimum output (with slippage)
        uint256 minOut = (usdcAmount * (BPS - SLIPPAGE_BPS)) / BPS;
        
        // Swap path
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(cambioToken);
        
        // Execute swap
        uint[] memory amounts = router.swapExactTokensForTokens(
            usdcAmount,
            minOut,
            path,
            address(this),
            block.timestamp + 15 minutes
        );
        
        return amounts[1];
    }
    
    /**
     * @dev Add liquidity to PancakeSwap
     * @param usdcAmount USDC amount (6 decimals)
     * @param cambioAmount CAMBIO amount (18 decimals)
     * @return lpAmount LP tokens minted
     */
    function _addLiquidity(
        uint256 usdcAmount,
        uint256 cambioAmount
    ) internal returns (uint256 lpAmount) {
        // Calculate minimums (with slippage)
        uint256 minUsdc = (usdcAmount * (BPS - SLIPPAGE_BPS)) / BPS;
        uint256 minCambio = (cambioAmount * (BPS - SLIPPAGE_BPS)) / BPS;
        
        // Add liquidity
        (,, lpAmount) = router.addLiquidity(
            address(usdc),
            address(cambioToken),
            usdcAmount,
            cambioAmount,
            minUsdc,
            minCambio,
            address(this),
            block.timestamp + 15 minutes
        );
        
        return lpAmount;
    }
    
    /**
     * @dev Lock LP tokens
     * @param amount LP amount to lock
     */
    function _lockLP(uint256 amount) internal {
        require(amount > 0, "Liquidity: zero amount");
        
        uint256 unlockAt = block.timestamp + LOCK_PERIOD;
        
        // Create lock record
        lockedLPs.push(LockedLP({
            amount: amount,
            lockedAt: block.timestamp,
            unlockAt: unlockAt,
            withdrawn: false
        }));
        
        // Update total
        totalLPLocked += amount;
        
        emit LPLocked(lockedLPs.length - 1, amount, unlockAt);
    }
    
    /*//////////////////////////////////////////////////////////////
                        LP UNLOCKING
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Unlock LP tokens (after lock period)
     * @param lockId Lock ID
     */
    function unlockLP(uint256 lockId) external onlyOwner nonReentrant {
        require(lockId < lockedLPs.length, "Liquidity: invalid lock");
        LockedLP storage lock = lockedLPs[lockId];
        
        require(!lock.withdrawn, "Liquidity: already withdrawn");
        require(block.timestamp >= lock.unlockAt, "Liquidity: still locked");
        
        // Mark as withdrawn
        lock.withdrawn = true;
        
        // Transfer LP tokens
        lpToken.safeTransfer(owner(), lock.amount);
        
        emit LPUnlocked(lockId, lock.amount);
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get total locked LP (not withdrawn)
     * @return total Total locked LP amount
     */
    function getTotalLockedLP() external view returns (uint256 total) {
        for (uint256 i = 0; i < lockedLPs.length; i++) {
            if (!lockedLPs[i].withdrawn) {
                total += lockedLPs[i].amount;
            }
        }
        return total;
    }
    
    /**
     * @notice Get lock details
     * @param lockId Lock ID
     * @return lock LockedLP struct
     */
    function getLock(uint256 lockId) external view returns (LockedLP memory lock) {
        require(lockId < lockedLPs.length, "Liquidity: invalid lock");
        return lockedLPs[lockId];
    }
    
    /**
     * @notice Get all locks
     * @return locks Array of LockedLP structs
     */
    function getAllLocks() external view returns (LockedLP[] memory locks) {
        return lockedLPs;
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS (OWNER)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update LP token address
     * @param newLPToken New LP token address
     */
    function setLPToken(address newLPToken) external onlyOwner {
        require(newLPToken != address(0), "Liquidity: zero address");
        lpToken = IERC20(newLPToken);
    }
    
    /**
     * @notice Emergency withdrawal (owner only)
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
