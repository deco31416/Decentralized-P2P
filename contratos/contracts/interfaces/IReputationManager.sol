// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IReputationManager
 * @notice Interface for ReputationManager contract
 */
interface IReputationManager {
    function adjustScore(address user, int256 delta, string memory reason) external;
    function getScore(address user) external view returns (int256); // Returns int256, not uint256
    function isBanned(address user) external view returns (bool);
    function recordTradeSuccess(address user) external;
    function recordTradeFail(address user) external;
    function recordDisputeWon(address user) external;
    function recordDisputeLost(address user) external;
    function banUser(address user) external;
}
