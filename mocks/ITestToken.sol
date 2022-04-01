// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./../dependencies/IERC20.sol";

interface ITestToken is IERC20 {

    function token0() external view returns (address);

    function token1() external view returns (address);
    
    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;
}