// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILiquidityEngine  
 * @notice Interface for LiquidityEngine contract
 */
interface ILiquidityEngine {
    function executeBuyback(uint256 usdcAmount) external returns (uint256 cambioReceived);
    function executeBuyback() external; // Overload without parameters
}
