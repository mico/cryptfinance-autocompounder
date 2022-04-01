// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

import "./ERC20.sol";

contract TestToken is ERC20 {

    address public token0;
    address public token1;

    function setTokens(address _token0, address _token1) external {
        token0 = _token0;
        token1 = _token1;
    }
    
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol){}
    
    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) public {
        _burn(_account, _amount);
    }

}