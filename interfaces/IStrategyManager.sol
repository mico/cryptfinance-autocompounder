// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategyManager {
    function operators(address addr) external returns (bool);

    function performanceFee() external returns (uint256);

    function performanceFeeBountyPct() external returns (uint256);

    function stakedTokens(uint256 pid, address user) external view returns (uint256);
}