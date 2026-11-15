// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStakingManager
 * @notice Interface for StakingManager contract
 */
interface IStakingManager {
    function getUserTier(address user) external view returns (uint8);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function getStake(address user) external view returns (uint256);
}
