// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// import '@openzeppelin/contracts/access/Ownable.sol';
// import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
// import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
// import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
// import '@openzeppelin/contracts/security/Pausable.sol';
// import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
// import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
// import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import './dependencies/Ownable.sol';
import './dependencies/SafeERC20.sol';
import './dependencies/ReentrancyGuard.sol';
import './dependencies/Pausable.sol';
import './dependencies/IUniswapV2Router02.sol';
import './dependencies/IUniswapV2Factory.sol';
import './dependencies/IUniswapV2Pair.sol';

import './interfaces/IFarm.sol';
import './interfaces/IStrategyManager.sol';
import './interfaces/IWNATIVE.sol';

contract VaultStrategy is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    //*=============== User Defined Complex Types ===============*//
    
    struct BurnTokenInfo {
        IERC20 token; //Token Address
        uint256 weight; //Token Weight
        address burnAddress; //Address to send burn tokens to
    }

    //*=============== State Variables. ===============*//

    //Pool variables.
    IStrategyManager public strategyManager; // address of the StrategyManager staking contract.
    IFarm public masterChef; // address of the farm staking contract
    uint256 public pid; // pid of pool in the farm staking contract

    //Token variables.
    IERC20 public stakeToken; // token staked on the underlying farm
    IERC20 public token0; // first token of the lp (or 0 if it's a single token)
    IERC20 public token1; // second token of the lp (or 0 if it's a single token)
    IERC20 public earnToken; // reward token paid by the underlying farm
    address[] public extraEarnTokens; // some underlying farms can give rewards in multiple tokens

    //Swap variables.
    IUniswapV2Router02 public swapRouter; // router used for swapping tokens.
    address public WNATIVE; // address of the network's native currency.
    mapping(address => mapping(address => address[])) public swapPath; // paths for swapping 2 given tokens.

    //Burn token state variables. List storage along with 
    BurnTokenInfo[] public burnTokens;
    uint256 public totalBurnTokenWghts;

    //Misc variables.
    uint256 public sharesTotal = 0;
    bool public initialized;
    bool public emergencyWithdrawn;

    //*=============== Events. ===============*//

    event Initialize();
    event Farm();
    event Pause();
    event Unpause();
    event EmergencyWithdraw();
    event TokenToEarn(address token);
    event WrapNative();

    //*=============== Modifiers. ===============*//

    modifier onlyOperator() { 
        require(strategyManager.operators(msg.sender), "Error: onlyOperator, NOT_ALLOWED");
        _;
    }

    //*=============== Constructor/Initializer. ===============*//

    function initialize(
        uint256 _pid,
        bool _isLpToken,
        address[6] calldata _addresses,
        address[] calldata _earnToToken0Path,
        address[] calldata _earnToToken1Path,
        address[] calldata _token0ToEarnPath,
        address[] calldata _token1ToEarnPath
    ) external onlyOwner {
        require(!initialized, 'Error: Already initialized');
        initialized = true;

        //State variable initialization.
        strategyManager = IStrategyManager(_addresses[0]);
        stakeToken = IERC20(_addresses[1]);
        earnToken = IERC20(_addresses[2]);
        masterChef = IFarm(_addresses[3]);
        swapRouter = IUniswapV2Router02(_addresses[4]);
        WNATIVE = _addresses[5];
        pid = _pid;

        //Set paths for swapping between tokens.
        if (_isLpToken) {
            token0 = IERC20(IUniswapV2Pair(_addresses[1]).token0());
            token1 = IERC20(IUniswapV2Pair(_addresses[1]).token1());

            _setSwapPath(address(earnToken), address(token0), _earnToToken0Path);
            _setSwapPath(address(earnToken), address(token1), _earnToToken1Path);

            _setSwapPath(address(token0), address(earnToken), _token0ToEarnPath);
            _setSwapPath(address(token1), address(earnToken), _token1ToEarnPath);
        } else {
            _setSwapPath(address(earnToken), address(stakeToken), _earnToToken0Path);
            _setSwapPath(address(stakeToken), address(earnToken), _token0ToEarnPath);
        }
        
        emit Initialize();
    }

    //*=============== Functions. ===============*//

    //Default receive function. Handles native token pools.
    receive() external payable {}

    //Pause/Unpause functions.
    function pause() external virtual onlyOperator {
        _pause();
        emit Pause();
    } 

    function unpause() external virtual onlyOperator {
        require(!emergencyWithdrawn, 'unpause: CANNOT_UNPAUSE_AFTER_EMERGENCY_WITHDRAW');
        _unpause();
        emit Unpause();
    }

    //Wrap native tokens if present.
    function wrapNative() public virtual {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            IWNATIVE(WNATIVE).deposit{value: balance}();
            emit WrapNative();
        }
    }

    //Farm functions.
    function _farmDeposit(uint256 amount) internal {
        stakeToken.safeIncreaseAllowance(address(masterChef), amount);
        masterChef.deposit(pid, amount);
    }

    function _farmWithdraw(uint256 amount) internal {
        masterChef.withdraw(pid, amount);
    }

    function _farmEmergencyWithdraw() internal {
        masterChef.emergencyWithdraw(pid);
    }

    function _totalStaked() internal view returns (uint256 amount) {
        (amount, ) = masterChef.userInfo(pid, address(this));
    }

    function totalStakeTokens() public view virtual returns (uint256) {
        return _totalStaked() + stakeToken.balanceOf(address(this));
    }

    function _farm() internal virtual { 
        uint256 depositAmount = stakeToken.balanceOf(address(this));
        _farmDeposit(depositAmount);
    }

    function _farmHarvest() internal virtual {
        _farmDeposit(0);
    }

    function farm() external virtual nonReentrant whenNotPaused {
        _farm();
        emit Farm();
    }

    function emergencyWithdraw() external virtual onlyOperator {
        if (!paused()) { _pause(); }
        emergencyWithdrawn = true;
        _farmEmergencyWithdraw();
        emit EmergencyWithdraw();
    }

    //Functions to interact with farm. {deposit, withdraw, earn}

    //Deposit - funds are put in this contract before this is called.
    function deposit(
        uint256 _depositAmount
    ) external virtual onlyOwner nonReentrant whenNotPaused returns (uint256) {

        //Calculate totalStakedTokens and deposit into farm.
        uint256 totalStakedBefore = totalStakeTokens() - _depositAmount;
        _farm(); 
        uint256 totalStakedAfter = totalStakeTokens();

        //Adjusts for deposit fees on the underlying farm and token transfer taxes.
        _depositAmount = totalStakedAfter - totalStakedBefore;

        //Calculates and returns the sharesAdded variable..
        uint256 sharesAdded = _depositAmount;
        if (totalStakedBefore > 0 && sharesTotal > 0) {
            sharesAdded = (_depositAmount * sharesTotal) / totalStakedBefore;
        }
        sharesTotal = sharesTotal + sharesAdded;

        return sharesAdded;
    }

    function withdraw(
        uint256 _withdrawAmount,
        address _withdrawTo
    ) external virtual onlyOwner nonReentrant returns (uint256) {
        
        uint256 totalStakedOnFarm = _totalStaked();
        uint256 totalStake = totalStakeTokens();

        //Number of shares that the withdraw amount represents (rounded up).
        uint256 sharesRemoved = (_withdrawAmount * sharesTotal - 1) / totalStake + 1;
        if (sharesRemoved > sharesTotal) { sharesRemoved = sharesTotal; }
        sharesTotal = sharesTotal - sharesRemoved;
        
        //Withdraw
        if (totalStakedOnFarm > 0) { _farmWithdraw(_withdrawAmount); }

        //Catch transfer fees & insufficient balance.
        uint256 stakeBalance = stakeToken.balanceOf(address(this));
        if (_withdrawAmount > stakeBalance) { _withdrawAmount = stakeBalance; }
        if (_withdrawAmount > totalStake) { _withdrawAmount = totalStake; }

        //Safe transfer tokens.
        stakeToken.safeTransfer(_withdrawTo, _withdrawAmount);

        return sharesRemoved;
    }

    function earn(
        address _bountyHunter
    ) external virtual onlyOwner returns (uint256 bountyReward) {
        if (paused()) { return 0; }

        //Log tokens before harvest.
        uint256 earnAmountBefore = earnToken.balanceOf(address(this));

        //Harvest and convert all tokens to those earnt.
        _farmHarvest();
        if (address(earnToken) == WNATIVE) { wrapNative(); }
        for (uint256 i; i < extraEarnTokens.length; i++) {
            if (extraEarnTokens[i]==WNATIVE) { wrapNative(); }
            tokenToEarn(extraEarnTokens[i]);
        }

        //Calculate full amount harvested.
        uint256 harvestAmount = earnToken.balanceOf(address(this)) - earnAmountBefore;

        //If there has been any harvested then calculate the fees to distribute.
        if (harvestAmount > 0) {
            bountyReward = _distributeFees(harvestAmount, _bountyHunter);
        }

        //Reasses the amount earnt.
        uint256 earnAmount = earnToken.balanceOf(address(this));

        //Perform single stake strategy...
        if (address(token0) == address(0)) {
            //If the stake and earn token are different the swap between the two.
            if (stakeToken != earnToken) {
                _safeSwap(earnAmount, swapPath[address(earnToken)][address(stakeToken)], address(this), false);
            }
            _farm();
            return bountyReward;
        }

        //Perform LP stake strategy...
        if (token0 != earnToken) {
            _safeSwap(earnAmount / 2, swapPath[address(earnToken)][address(token0)], address(this), false);
        }
        if (token1 != earnToken) {
            _safeSwap(earnAmount / 2, swapPath[address(earnToken)][address(token1)], address(this), false);
        }

        //Add liquidiy it the chosen amount is >0. - This is where we can have leftover bits.
        uint256 token0Amt = token0.balanceOf(address(this));
        uint256 token1Amt = token1.balanceOf(address(this));
        if (token0Amt > 0 && token1Amt > 0) {
            token0.safeIncreaseAllowance(address(swapRouter), token0Amt);
            token1.safeIncreaseAllowance(address(swapRouter), token1Amt);
            swapRouter.addLiquidity(
                address(token0),
                address(token1),
                token0Amt,
                token1Amt,
                0,
                0,
                address(this),
                block.timestamp
            );
        }

        //Deposit tokens and return the bountyReward.
        _farm();
        return bountyReward;
    }

    //Burn token manipulation functions.
    function addBurnToken(
        address _token, 
        uint256 _weight, 
        address _burnAddress,
        address[] calldata _earnToBurnPath,
        address[] calldata _burnToEarnPath
    ) external onlyOwner {
        //Add token to storage and update the associated state variables.
        burnTokens.push(BurnTokenInfo({token: IERC20(_token), weight: _weight, burnAddress: _burnAddress}));
        totalBurnTokenWghts += _weight;

        //Add the swap token paths.
        _setSwapPath(address(earnToken), address(_token), _earnToBurnPath);
        _setSwapPath(address(_token), address(earnToken), _burnToEarnPath);
    }

    function removeBurnToken(
        uint256 _index
    ) external onlyOwner {
        require(burnTokens.length > 0, "Error: No elements to remove.");
        require(burnTokens.length >= (_index+1), "Error: Index out of range."); 
        totalBurnTokenWghts -= burnTokens[_index].weight;
        burnTokens[_index] = burnTokens[burnTokens.length-1];
        burnTokens.pop();
    }

    function setBurnToken(
        address _token, 
        uint256 _weight,
        address _burnAddress,
        uint256 _index
    ) external onlyOwner {
        require(burnTokens.length >= (_index+1), "Error: Index out of range."); 
        totalBurnTokenWghts -= burnTokens[_index].weight;
        burnTokens[_index] = BurnTokenInfo({token: IERC20(_token), weight: _weight, burnAddress: _burnAddress});
        totalBurnTokenWghts += _weight;
    }

    function setSwapRouter(
        address _router
    ) external virtual onlyOwner {
        swapRouter = IUniswapV2Router02(_router);
    }

    function setExtraEarnTokens(
        address[] calldata _extraEarnTokens
    ) external virtual onlyOwner {
        require(_extraEarnTokens.length <= 5, "Error: Extra tokens set cap excluded");
        extraEarnTokens = _extraEarnTokens;
    }

    //swapPath manipulation functions.
    function _setSwapPath(
        address _token0,
        address _token1,
        address[] memory _path
    ) internal virtual {
        require(_path.length > 1, "Error: Path is not long enough.");
        require(_path[0]==_token0 && _path[_path.length-1]==_token1, "Error: Endpoints of path are incorrect.");
        swapPath[_token0][_token1] = _path;
    }

    function setSwapPath(
        address _token0,
        address _token1,
        address[] calldata _path
    ) external virtual onlyOwner {
        _setSwapPath(_token0, _token1, _path);
    }

    function removeSwapPath(
        address _token0,
        address _token1
    ) external virtual onlyOwner {
        delete swapPath[_token0][_token1];
    }

    //safeSwap function which increases the allowance & supports fees on transferring tokens.
    function _safeSwap(
        uint256 _amountIn,
        address[] memory _path,
        address _to,
        bool _ignoreErrors
    ) internal virtual {
        if (_amountIn>0) {
            IERC20(_path[0]).safeIncreaseAllowance(address(swapRouter), _amountIn);
            if (_ignoreErrors) {
                try
                    swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(_amountIn, 0, _path, _to, block.timestamp+40)
                {} catch {}
            } else {
                swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(_amountIn, 0, _path, _to, block.timestamp+40);
            }
        }
    }
    
    //Swap token to earn - used for extraEarnTokens & can be called externally to convert dust to earnedToken.
    function tokenToEarn(
        address _token
    ) public virtual nonReentrant whenNotPaused {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (amount > 0 && _token != address(earnToken) && _token != address(stakeToken)) {
            address[] memory path = swapPath[_token][address(earnToken)];
            if (path.length == 0) {
                if (_token == WNATIVE) {
                    path = new address[](2);
                    path[0] = _token;
                    path[1] = address(earnToken);
                } else {
                    path = new address[](3);
                    path[0] = _token;
                    path[1] = WNATIVE;
                    path[2] = address(earnToken);
                }
            }
            if (path[0] != address(earnToken) && path[0] != address(stakeToken)) {
                _safeSwap(amount, path, address(this), true);
            }
            emit TokenToEarn(_token);
        }
    }

    function _distributeFees(
        uint256 _amount, 
        address _bountyHunter
    ) internal virtual returns (uint256 bountyReward) { 
        uint256 performanceFee = (_amount * strategyManager.performanceFee()) / 10_000; //[0%, 5%]
        uint256 bountyRewardPct = _bountyHunter == address(0) ? 0 : strategyManager.performanceFeeBountyPct(); //[0%, 100%]]
        bountyReward = (performanceFee * bountyRewardPct) / 10_000;
        uint256 platformFee = performanceFee - bountyReward;

        //If no tokens to burn then send all to the bountyHunter.
        if (burnTokens.length == 0) {
            bountyReward  = _bountyHunter == address(0) ? 0 : performanceFee;
            platformFee = 0;
        }

        //Transfer the bounty reward to the bountyHunter.
        if (bountyReward > 0) {
            earnToken.safeTransfer(_bountyHunter, bountyReward);
        }

        //Burn the platformPerformanceFee tokens.
        if (platformFee > 0) {
            _burnEarnTokens(platformFee);
        }

        return bountyReward;
    }

    function _burnEarnTokens(
        uint256 _amount
    ) internal virtual {
        if (totalBurnTokenWghts == 0 || _amount==0) { return; }
        uint256 burnAmount;
        for (uint i=0; i<burnTokens.length; i++) {

            //Extract burn token info.
            BurnTokenInfo storage burnToken = burnTokens[i];
            burnAmount = (_amount * burnToken.weight) / totalBurnTokenWghts;

            //Either send or swap the burn token to the associated burn address.
            if (burnAmount==0) { 
                continue; 
            } else if (burnToken.token == earnToken) {
                earnToken.safeTransfer(burnToken.burnAddress, burnAmount);
            } else {
                _safeSwap(burnAmount, swapPath[address(earnToken)][address(burnToken.token)], burnToken.burnAddress, false);
            }
            
        }
    }

    //*=============== Extra Test Functions ===============*//
    function numBurnTokens() public view returns(uint256) {
        uint256 length = burnTokens.length;
        return length;
    }

}

