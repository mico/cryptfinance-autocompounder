// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ITestToken.sol";
import "./../dependencies/SafeERC20.sol";

contract MockRouter {

    using SafeERC20 for ITestToken;

    mapping(address => mapping(address => address)) public lpTokenAddress;

    function setLPTokenAddress(
        address _token1,
        address _token2,
        address _lpToken
    ) external {
        lpTokenAddress[_token1][_token2] = _lpToken;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 _amountIn, 
        uint256 _minAmount,
        address[] calldata _path, 
        address _to, 
        uint256 deadline
    ) external {

        ITestToken token1 = ITestToken(_path[0]);
        ITestToken token2 = ITestToken(_path[_path.length - 1]);

        token1.safeTransferFrom(msg.sender, address(this), _amountIn);
        token1.burn(address(this), _amountIn);

        token2.mint(address(this), _amountIn);
        token2.safeTransfer(_to, _amountIn);
    }

    function addLiquidity(
        address _token1,
        address _token2,
        uint256 _token1Amount,
        uint256 _token2Amount,
        uint256 _token1MinReturn,
        uint256 _token2MinReturn,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {

        require(lpTokenAddress[_token1][_token2] != address(0), "Error: Lp token not set.");

        ITestToken token1 = ITestToken(_token1);
        ITestToken token2 = ITestToken(_token2);

        _token1Amount = (_token1Amount*100)/100;
        _token2Amount = (_token2Amount*90)/100;

        // token1.safeTransferFrom(msg.sender, address(this), _token1Amount);
        // token2.safeTransferFrom(msg.sender, address(this), _token2Amount);

        token1.burn(msg.sender, _token1Amount);
        token2.burn(msg.sender, _token2Amount);

        ITestToken lpToken = ITestToken(lpTokenAddress[_token1][_token2]);
        uint256 _amount = (_token1Amount + _token2Amount) / 2;
        lpToken.mint(address(this), _amount);
        lpToken.safeTransfer(_to, _amount);

    }

}