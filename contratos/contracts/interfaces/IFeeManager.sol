// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFeeManager
 * @notice Interface for FeeManager contract
 */
interface IFeeManager {
    function collectFee(address token, uint256 amount, address from) external returns (uint256);
    function calculateFee(uint8 tradeType, uint256 amountUsd, uint8 userTier) external view returns (uint256);
}
