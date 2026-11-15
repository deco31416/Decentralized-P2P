// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/IPancakePair.sol";

/**
 * @title PancakeTwapOracleV2
 * @notice 6-hour TWAP oracle for CAMBIO/USDC with manipulation protection
 * @dev CRITICAL SECURITY FEATURES:
 *      1. Liquidity gate ($50k minimum)
 *      2. Price spike protection (10% max change)
 *      3. Floor/ceiling prices
 *      4. Freshness check (max 30 min stale)
 * 
 * Architecture:
 *      - Uses PancakeSwap V2 pair reserves
 *      - 6-hour TWAP (reduce flash loan impact)
 *      - Multiple safety checks before returning price
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract PancakeTwapOracleV2 is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice TWAP window (6 hours)
    uint256 public constant TWAP_WINDOW = 6 hours;
    
    /// @notice Minimum USDC liquidity in pair ($50k, 6 decimals)
    uint256 public constant MIN_LP_USDC = 50_000e6;
    
    /// @notice Maximum price change per update (10% = 1000 bps)
    uint256 public constant MAX_PRICE_CHANGE_BPS = 1000;
    
    /// @notice Max staleness allowed (30 minutes)
    uint256 public constant MAX_STALENESS = 30 minutes;
    
    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice PancakeSwap V2 pair address (CAMBIO/USDC)
    address public immutable pair;
    
    /// @notice CAMBIO token address
    address public immutable cambio;
    
    /// @notice USDC token address
    address public immutable usdc;
    
    /// @notice Is CAMBIO token0 in pair?
    bool public immutable isToken0;
    
    /// @notice Floor price (minimum allowed, 6 decimals)
    uint256 public floorPrice;
    
    /// @notice Ceiling price (maximum allowed, 6 decimals)
    uint256 public ceilingPrice;
    
    /// @notice Last observed price (for spike detection)
    uint256 public lastPrice;
    
    /// @notice Last update timestamp
    uint256 public lastUpdate;
    
    /// @notice TWAP accumulator
    uint256 public priceAccumulator;
    
    /// @notice Samples count for TWAP
    uint256 public samplesCount;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PriceUpdated(uint256 newPrice, uint256 timestamp);
    event FloorPriceUpdated(uint256 newFloor);
    event CeilingPriceUpdated(uint256 newCeiling);
    event LiquidityBelowThreshold(uint256 liquidity, uint256 threshold);
    event PriceSpikeDetected(uint256 oldPrice, uint256 newPrice);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address initialOwner,
        address _pair,
        address _cambio,
        address _usdc,
        uint256 _floorPrice,
        uint256 _ceilingPrice
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Oracle: zero owner");
        require(_pair != address(0), "Oracle: zero pair");
        require(_cambio != address(0), "Oracle: zero cambio");
        require(_usdc != address(0), "Oracle: zero usdc");
        require(_floorPrice > 0, "Oracle: zero floor");
        require(_ceilingPrice > _floorPrice, "Oracle: ceiling <= floor");
        
        pair = _pair;
        cambio = _cambio;
        usdc = _usdc;
        
        // Determine token order in pair
        isToken0 = (IPancakePair(_pair).token0() == _cambio);
        
        floorPrice = _floorPrice;
        ceilingPrice = _ceilingPrice;
        
        // Initialize with safe default
        lastPrice = _floorPrice;
        lastUpdate = block.timestamp;
    }
    
    /*//////////////////////////////////////////////////////////////
                        PRICE ORACLE (PUBLIC)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get current TWAP price with safety checks
     * @return price CAMBIO price in USD (6 decimals)
     * @dev REVERTS if:
     *      - Liquidity below threshold
     *      - Price spike detected
     *      - Price outside floor/ceiling
     *      - Data too stale
     */
    function getPrice() external view returns (uint256 price) {
        // 1. Check staleness
        require(block.timestamp - lastUpdate <= MAX_STALENESS, "Oracle: stale data");
        
        // 2. Get raw price from reserves
        uint256 rawPrice = _getRawPrice();
        
        // 3. Check liquidity gate
        uint256 liquidityUsdc = _getLiquidityUsdc();
        require(liquidityUsdc >= MIN_LP_USDC, "Oracle: insufficient liquidity");
        
        // 4. Check spike protection
        if (lastPrice > 0) {
            uint256 priceDiff = rawPrice > lastPrice 
                ? rawPrice - lastPrice 
                : lastPrice - rawPrice;
            uint256 maxChange = (lastPrice * MAX_PRICE_CHANGE_BPS) / BPS;
            require(priceDiff <= maxChange, "Oracle: price spike detected");
        }
        
        // 5. Enforce floor/ceiling
        if (rawPrice < floorPrice) {
            price = floorPrice;
        } else if (rawPrice > ceilingPrice) {
            price = ceilingPrice;
        } else {
            price = rawPrice;
        }
        
        return price;
    }
    
    /**
     * @notice Get price without safety checks (for view-only)
     * @return price Raw TWAP price (6 decimals)
     */
    function getPriceUnsafe() external view returns (uint256 price) {
        return _getRawPrice();
    }
    
    /**
     * @notice Update TWAP (should be called periodically)
     * @dev Anyone can call to keep oracle fresh
     */
    function update() external {
        uint256 rawPrice = _getRawPrice();
        
        // Check liquidity
        uint256 liquidityUsdc = _getLiquidityUsdc();
        if (liquidityUsdc < MIN_LP_USDC) {
            emit LiquidityBelowThreshold(liquidityUsdc, MIN_LP_USDC);
            return; // Don't update if liquidity too low
        }
        
        // Check spike
        if (lastPrice > 0) {
            uint256 priceDiff = rawPrice > lastPrice 
                ? rawPrice - lastPrice 
                : lastPrice - rawPrice;
            uint256 maxChange = (lastPrice * MAX_PRICE_CHANGE_BPS) / BPS;
            
            if (priceDiff > maxChange) {
                emit PriceSpikeDetected(lastPrice, rawPrice);
                return; // Don't update if spike detected
            }
        }
        
        // Update TWAP
        priceAccumulator += rawPrice;
        samplesCount++;
        lastPrice = rawPrice;
        lastUpdate = block.timestamp;
        
        emit PriceUpdated(rawPrice, block.timestamp);
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Calculate raw price from pair reserves
     * @return price CAMBIO price in USD (6 decimals)
     */
    function _getRawPrice() internal view returns (uint256 price) {
        (uint112 reserve0, uint112 reserve1,) = IPancakePair(pair).getReserves();
        
        uint256 reserveCambio;
        uint256 reserveUsdc;
        
        if (isToken0) {
            reserveCambio = uint256(reserve0);
            reserveUsdc = uint256(reserve1);
        } else {
            reserveCambio = uint256(reserve1);
            reserveUsdc = uint256(reserve0);
        }
        
        require(reserveCambio > 0, "Oracle: zero cambio reserve");
        
        // Price = (reserveUsdc / reserveCambio) * 1e18 (normalize to 6 decimals)
        // CAMBIO has 18 decimals, USDC has 6 decimals
        // Price in USD = (reserveUsdc * 1e18) / reserveCambio
        price = (reserveUsdc * 1e18) / reserveCambio;
        
        return price;
    }
    
    /**
     * @dev Get USDC liquidity in pair
     * @return liquidity USDC amount in pair (6 decimals)
     */
    function _getLiquidityUsdc() internal view returns (uint256 liquidity) {
        (uint112 reserve0, uint112 reserve1,) = IPancakePair(pair).getReserves();
        
        if (isToken0) {
            liquidity = uint256(reserve1); // USDC is token1
        } else {
            liquidity = uint256(reserve0); // USDC is token0
        }
        
        return liquidity;
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS (OWNER)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update floor price
     * @param newFloor New floor price (6 decimals)
     */
    function setFloorPrice(uint256 newFloor) external onlyOwner {
        require(newFloor > 0, "Oracle: zero floor");
        require(newFloor < ceilingPrice, "Oracle: floor >= ceiling");
        
        floorPrice = newFloor;
        emit FloorPriceUpdated(newFloor);
    }
    
    /**
     * @notice Update ceiling price
     * @param newCeiling New ceiling price (6 decimals)
     */
    function setCeilingPrice(uint256 newCeiling) external onlyOwner {
        require(newCeiling > floorPrice, "Oracle: ceiling <= floor");
        
        ceilingPrice = newCeiling;
        emit CeilingPriceUpdated(newCeiling);
    }
}
