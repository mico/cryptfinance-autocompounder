// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVaultStrategy {
    function stakeToken() external view returns (address);

    function totalStakeTokens() external view returns (uint256);

    function sharesTotal() external view returns (uint256);

    function deposit(uint256 _depositAmount) external returns (uint256);

    function earn(address _bountyHunter) external returns (uint256);

    function withdraw(uint256 _withdrawAmount, address _withdrawTo) external returns (uint256);

    function setSwapRouter(address _router) external;

    function setSwapPath(
        address _token0,
        address _token1,
        address[] calldata _path
    ) external;

    function removeSwapPath(address _token0, address _token1) external;

    function setExtraEarnTokens(address[] calldata _extraEarnTokens) external;

    function addBurnToken(
        address _token, 
        uint256 _weight, 
        address _burnAddress, 
        address[] calldata _earnToBurnPath,
        address[] calldata _burnToEarnPath
    ) external; 

    function removeBurnToken(uint256 _index) external;  

    function setBurnToken(
        address _token,
        uint256 _weight,
        address _burnAddress,
        uint256 _index
    ) external;
}
