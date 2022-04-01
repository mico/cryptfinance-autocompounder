// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./../dependencies/IERC20.sol";

interface IWNATIVE is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}