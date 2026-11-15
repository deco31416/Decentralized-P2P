// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICircuitBreaker
 * @notice Interface for CircuitBreaker contract
 */
interface ICircuitBreaker {
    function isEscrowOperational() external view returns (bool);
    function isWithdrawOperational() external view returns (bool);
    function isStakingOperational() external view returns (bool);
    function isDisputeOperational() external view returns (bool);
}
