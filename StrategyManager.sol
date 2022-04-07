// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// import '@openzeppelin/contracts/access/Ownable.sol';
// import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
// import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
// import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import './dependencies/Ownable.sol';
import './dependencies/SafeERC20.sol';
import './dependencies/ReentrancyGuard.sol';
import './dependencies/EnumerableSet.sol';

import './interfaces/IFarm.sol';
import './interfaces/IVaultStrategy.sol';

contract StrategyManager is Ownable, ReentrancyGuard {

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    //*=============== User Defined Complex Types ===============*//

    struct PoolInfo {
        IERC20 stakeToken; // address of the token staked on the underlying farm
        IVaultStrategy strategy; // address of the strategy for the pool
    }

    //*=============== State Variables. ===============*//

    //Strategy manager operators.
    mapping(address => bool) public operators;

    //Farm & Pool info.
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => uint256)) public userPoolShares;
    mapping(address => EnumerableSet.UintSet) private userStakedPools;

    //Map used to ensure strategies cannot be added twice
    mapping(address => bool) public strategyExists; // 

    //Performance fee 
    uint256 constant PERFORMANCE_FEE_CAP = 500;
    uint256 public performanceFee = 400;
    uint256 public performanceFeeBountyPct = 2_500;

    //*=============== Events. ===============*//

    event Add(IERC20 stakeToken, IVaultStrategy strategy);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, address indexed to, uint256 indexed pid, uint256 amount);
    event Earn(address indexed user, uint256 indexed pid, uint256 bountyReward);
    event SetOperator(address addr, bool isOperator);
    event SetPerformanceFee(uint256 performanceFee);
    event SetPerformanceFeeBountyPct(uint256 performanceFeeBountyPct);
    event SetStrategyRouter(IVaultStrategy strategy, address router);
    event SetStrategySwapPath(IVaultStrategy _strategy, address _token0, address _token1, address[] _path);
    event RemoveStrategySwapPath(IVaultStrategy _strategy, address _token0, address _token1);
    event SetStrategyExtraEarnTokens(IVaultStrategy _strategy, address[] _extraEarnTokens);
    event AddStrategyBurnToken(IVaultStrategy _strategy, address _token, uint256 _weight, address _burnAddress);
    event SetStrategyBurnToken(IVaultStrategy _strategy, address _token, uint256 _weight, address _burnAddress, uint256 _index);
    event RemoveStrategyBurnToken(IVaultStrategy _strategy, uint256 _index);

    //*=============== Modifiers. ===============*//
    modifier onlyOperator() {
        require(operators[msg.sender], "Error: onlyOperator, NOT_ALLOWED");
        _;
    }

    //*=============== Constructor/Initializer. ===============*//

    constructor() {
        operators[msg.sender] = true;
    }
    //*=============== Functions. ===============*//

    //Default receive function. Handles native token pools.
    receive() external payable {}

    //Vault property functions.
    function setOperator(address _addr, bool _isOperator) external onlyOwner {
        operators[_addr] = _isOperator;
        emit SetOperator(_addr, _isOperator);
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        require(_performanceFee <= PERFORMANCE_FEE_CAP, "Error: Performance fee cap exceeded");
        performanceFee = _performanceFee;
        emit SetPerformanceFee(_performanceFee);
    }

    function setPerformanceFeeBountyPct(uint256 _performanceFeeBountyPct) external onlyOwner {
        require(_performanceFeeBountyPct <= 10_000, "Error: Performance fee bounty precentage cap exceeded");
        performanceFeeBountyPct = _performanceFeeBountyPct;
        emit SetPerformanceFeeBountyPct(_performanceFeeBountyPct);
    }

    //User staked pool functions.
    function userStakedPoolLength(address _user) external view returns (uint256) {
        return userStakedPools[_user].length();
    }

    function userStakedPoolAt(address _user, uint256 _index) external view returns (uint256) {
        return userStakedPools[_user].at(_index);
    }

    function userStakedTokens(address _user, uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        IVaultStrategy strategy = pool.strategy;

        uint256 sharesTotal = strategy.sharesTotal();
        uint256 userShares = userPoolShares[_pid][_user];

        return sharesTotal > 0 ? (userShares * strategy.totalStakeTokens()) / sharesTotal : 0; 
    }

    //Vault Manager functions
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(
        IVaultStrategy _strategy
    ) public onlyOperator {
        require(!strategyExists[address(_strategy)], "Error: Strategy already exists");
        IERC20 stakeToken = IERC20(_strategy.stakeToken());
        poolInfo.push(PoolInfo({stakeToken: stakeToken, strategy: _strategy}));
        strategyExists[address(_strategy)] = true;
        emit Add(stakeToken, _strategy);
    }

    //Individual strategy functions.
    function setStrategyRouter(
        IVaultStrategy _strategy,
        address _router
    ) external onlyOwner {
        _strategy.setSwapRouter(_router);
        emit SetStrategyRouter(_strategy, _router);
    }

    function setStrategySwapPath(
        IVaultStrategy _strategy,
        address _token0,
        address _token1,
        address[] calldata _path
    ) external onlyOwner {
        _strategy.setSwapPath(_token0, _token1, _path);
        emit SetStrategySwapPath(_strategy, _token0, _token1, _path);
    }

    function removeStrategySwapPath(
        IVaultStrategy _strategy,
        address _token0,
        address _token1
    ) external onlyOwner {
        _strategy.removeSwapPath(_token0, _token1);
        emit RemoveStrategySwapPath(_strategy, _token0, _token1);
    }

    function setStrategyExtraEarnTokens(
        IVaultStrategy _strategy, 
        address[] calldata _extraEarnTokens
    ) external onlyOwner {
        require(_extraEarnTokens.length <= 5, "Error: Extra tokens set cap excluded");

        //Sanity check for all being tokens.
        for (uint256 i; i < _extraEarnTokens.length; i++) {
            IERC20(_extraEarnTokens[i]).balanceOf(address(this));
        }

        _strategy.setExtraEarnTokens(_extraEarnTokens);
        emit SetStrategyExtraEarnTokens(_strategy, _extraEarnTokens);
    }

    function addStrategyBurnToken(
        IVaultStrategy _strategy,
        address _token, 
        uint256 _weight, 
        address _burnAddress, 
        address[] calldata _earnToBurnPath, 
        address[] calldata _burnToEarnPath
    ) external onlyOwner {
        _strategy.addBurnToken(_token, _weight, _burnAddress, _earnToBurnPath, _burnToEarnPath);
        emit AddStrategyBurnToken(_strategy, _token, _weight, _burnAddress);
    } 

    function setStrategyBurnToken(
        IVaultStrategy _strategy,
        address _token,
        uint256 _weight,
        address _burnAddress,
        uint256 _index
    ) external  onlyOwner {
        _strategy.setBurnToken(_token, _weight, _burnAddress, _index);
        emit SetStrategyBurnToken(_strategy, _token, _weight, _burnAddress, _index);
    }  

    function removeStrategyBurnToken(
        IVaultStrategy _strategy,
        uint256 _index
    ) external  onlyOwner {
        _strategy.removeBurnToken(_index);
        emit RemoveStrategyBurnToken(_strategy, _index);
    } 
    
    //Deposit functions.
    function _deposit(
        uint256 _pid,
        uint256 _depositAmount,
        address _for
    ) internal nonReentrant {
        require(_depositAmount > 0, "Error: Deposit amount must be greater than 0");
        PoolInfo memory pool = poolInfo[_pid];

        //Earn on behalf of protocol.
        if (pool.strategy.sharesTotal() > 0) { _protocolEarn(pool.strategy); }

        //Account for transfer tax.
        uint256 balanceBefore = pool.stakeToken.balanceOf(address(pool.strategy));
        pool.stakeToken.safeTransferFrom(address(msg.sender), address(pool.strategy), _depositAmount);
        _depositAmount = pool.stakeToken.balanceOf(address(pool.strategy)) - balanceBefore;

        //Deposit and add shares on behalf of user & log shares.
        uint256 sharesAdded = pool.strategy.deposit(_depositAmount);
        uint256 userShares = userPoolShares[_pid][_for];
        userPoolShares[_pid][_for] = userShares + sharesAdded;
        userStakedPools[_for].add(_pid);

        emit Deposit(_for, _pid, _depositAmount);
    }

    function deposit(
        uint256 _pid, 
        uint256 _depositAmount
    ) external {
        _deposit(_pid, _depositAmount, msg.sender);
    }

    function depositFor(
        uint256 _pid,
        uint256 _depositAmount,
        address _for
    ) external {
        _deposit(_pid, _depositAmount, _for);
    }

    //Withdraw functions.
    //_user is used to calculate the # of shares available and therefore is the accounts contributions that are affected.
    function _withdraw(
        address _user,
        address _to,
        uint256 _pid,
        uint256 _withdrawAmount
    ) internal nonReentrant {
        require(_withdrawAmount > 0, "Error: Deposit amount must be greater than 0");
        IVaultStrategy strategy = poolInfo[_pid].strategy;

        //Get the total amount of shares & earn on behalf of protocol.
        uint256 userShares = userPoolShares[_pid][_user];
        uint256 sharesTotal = strategy.sharesTotal();
        require(userShares > 0 && sharesTotal > 0, 'Error: No shares to withdraw.');
        _protocolEarn(strategy);

        //Set max amount of Tokens to withdraw.
        uint256 maxAmount = (userShares * strategy.totalStakeTokens()) / sharesTotal;
        if (_withdrawAmount > maxAmount) { _withdrawAmount = maxAmount; }

        //Withdraw and remove shares for the user.
        uint256 sharesRemoved = strategy.withdraw(_withdrawAmount, _to);
        userShares = userShares > sharesRemoved ? userShares - sharesRemoved : 0;
        userPoolShares[_pid][_user] = userShares;

        //Remove the pool for the user if they have no balance.
        if (userShares == 0) { userStakedPools[_user].remove(_pid); }

        emit Withdraw(_user, _to, _pid, _withdrawAmount);
    }

    function withdraw(uint256 _pid, uint256 _withdrawAmount) external {
        _withdraw(msg.sender, msg.sender, _pid, _withdrawAmount);
    }

    function emergencyWithdraw(uint256 _pid) external {
        _withdraw(msg.sender, msg.sender, _pid, type(uint256).max);
    }

    //Earn functions...
    function _earn(uint256 _pid) internal nonReentrant returns (uint256 bountyRewarded) {
        bountyRewarded = poolInfo[_pid].strategy.earn(msg.sender);
        emit Earn(msg.sender, _pid, bountyRewarded);
    }

    function earn(uint256 _pid) external returns (uint256) {
        return _earn(_pid);
    }

    function earnMany(uint256[] calldata _pids) external {
        for (uint256 i; i < _pids.length; i++) {
            _earn(_pids[i]);
        }
    }    

    //Earn with all fees going towards the protocol.
    function _protocolEarn(IVaultStrategy _strategy) internal {
        try _strategy.earn(address(0)) {} catch {} 
    }

}