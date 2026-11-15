// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title CircuitBreaker
 * @notice Emergency pause system for CambiaCripto protocol
 * @dev Granular pause flags for each module, allowing selective shutdown
 * 
 * Architecture:
 *      - Escrow can be paused (stops new trades)
 *      - Staking can be paused (stops new stakes, allows withdrawals)
 *      - Liquidity can be paused (stops auto-LP operations)
 *      - Emergency pause ALL (nuclear option)
 * 
 * Security:
 *      - Owner-only control (timelock + multisig recommended)
 *      - Each module checks its flag before execution
 *      - Emergency unpause after cooldown
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract CircuitBreaker is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Escrow paused (no new trades)
    bool public escrowPaused;
    
    /// @notice Staking paused (no new stakes)
    bool public stakingPaused;
    
    /// @notice Liquidity operations paused (no auto-LP)
    bool public liquidityPaused;
    
    /// @notice Emergency pause ALL modules
    bool public emergencyPaused;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event EscrowPausedChanged(bool paused);
    event StakingPausedChanged(bool paused);
    event LiquidityPausedChanged(bool paused);
    event EmergencyPauseTriggered(bool paused);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "CircuitBreaker: zero address");
    }
    
    /*//////////////////////////////////////////////////////////////
                        PAUSE CONTROLS (OWNER)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Pause/unpause escrow module
     * @param _paused True to pause, false to unpause
     */
    function setEscrowPaused(bool _paused) external onlyOwner {
        escrowPaused = _paused;
        emit EscrowPausedChanged(_paused);
    }
    
    /**
     * @notice Pause/unpause staking module
     * @param _paused True to pause, false to unpause
     */
    function setStakingPaused(bool _paused) external onlyOwner {
        stakingPaused = _paused;
        emit StakingPausedChanged(_paused);
    }
    
    /**
     * @notice Pause/unpause liquidity module
     * @param _paused True to pause, false to unpause
     */
    function setLiquidityPaused(bool _paused) external onlyOwner {
        liquidityPaused = _paused;
        emit LiquidityPausedChanged(_paused);
    }
    
    /**
     * @notice EMERGENCY: Pause ALL modules
     * @dev Should be triggered only in critical situations (exploit, etc.)
     * @param _paused True to trigger emergency, false to lift
     */
    function setEmergencyPause(bool _paused) external onlyOwner {
        emergencyPaused = _paused;
        emit EmergencyPauseTriggered(_paused);
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS (MODULES)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check if escrow operations are allowed
     * @return True if escrow is operational
     */
    function isEscrowOperational() external view returns (bool) {
        return !escrowPaused && !emergencyPaused;
    }
    
    /**
     * @notice Check if staking operations are allowed
     * @return True if staking is operational
     */
    function isStakingOperational() external view returns (bool) {
        return !stakingPaused && !emergencyPaused;
    }
    
    /**
     * @notice Check if liquidity operations are allowed
     * @return True if liquidity is operational
     */
    function isLiquidityOperational() external view returns (bool) {
        return !liquidityPaused && !emergencyPaused;
    }
    
    /**
     * @notice Check if protocol is in emergency mode
     * @return True if emergency pause is active
     */
    function isEmergency() external view returns (bool) {
        return emergencyPaused;
    }
}
