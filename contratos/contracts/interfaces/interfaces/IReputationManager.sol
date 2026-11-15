// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IReputationManager
 * @notice Interface for ReputationManager contract
 */
interface IReputationManager {
    function adjustScore(address user, int256 delta, string memory reason) external;
    function getScore(address user) external view returns (int256);
    function isBanned(address user) external view returns (bool);
}
