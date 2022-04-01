// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./../dependencies/IERC20.sol";
import "./../dependencies/SafeERC20.sol";
import "./ITestToken.sol";

contract MockFarm {
    using SafeERC20 for ITestToken;

    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. GRAPE to distribute.
        uint256 lastRewardTime; // Last time that GRAPE distribution occurs.
        uint256 accGrapePerShare; // Accumulated GRAPE per share, times 1e18. See below.
        bool isStarted; // if lastRewardBlock has passed
    }

    ITestToken public stakedToken;
    ITestToken public earnedToken;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    constructor (
        address _stakedToken,
        address _earnedToken
    ) {
        stakedToken = ITestToken(_stakedToken);
        earnedToken = ITestToken(_earnedToken);
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
        // require(_amount >= 0, "Error: Amount must be greater than 0.");
        UserInfo storage user = userInfo[_pid][msg.sender];
        user.amount = user.amount + _amount;

        stakedToken.safeTransferFrom(msg.sender, address(this), _amount);
        stakedToken.burn(address(this), _amount);

        uint256 _pending = user.rewardDebt;
        earnedToken.mint(address(this), _pending);
        earnedToken.safeTransfer(msg.sender, _pending);
        user.rewardDebt = 0;
    }

    function setPendingAmount(uint256 _pid, address _user, uint256 _amount) public {
        UserInfo storage user = userInfo[_pid][_user];
        user.rewardDebt = _amount;
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        if (_amount > user.amount) { _amount = user.amount; }
        // require(_amount > 0, "Error: Amount must be greater than 0.");
        user.amount = user.amount - _amount;

        stakedToken.mint(address(this), _amount);
        stakedToken.safeTransfer(msg.sender, _amount);

        uint256 _pending = user.rewardDebt;
        earnedToken.mint(address(this), _pending);
        earnedToken.safeTransfer(msg.sender, _pending);
        user.rewardDebt = 0;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        withdraw(_pid, 100000 ether);
    }
}