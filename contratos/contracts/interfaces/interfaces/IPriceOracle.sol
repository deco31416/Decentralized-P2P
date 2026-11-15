// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @notice Interface for Price Oracle
 */
interface IPriceOracle {
    function getPrice(address token) external view returns (uint256 priceUsd, uint256 lastUpdate);
}
