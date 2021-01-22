// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;
pragma abicoder v2;

import "../../interfaces/staking/IStaking.sol";
import "../../interfaces/staking/IFeePool.sol";
import "../../interfaces/staking/ISportXVault.sol";
import "../../interfaces/staking/ISportXStakingRewardsPool.sol";
import "../../interfaces/permissions/IPermissions.sol";
import "../../interfaces/staking/IStakingParameters.sol";
import "../Initializable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Staking is IStaking, Initializable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 public constant FRACTION_PRECISION = 10**20;
    string public constant name = "SportX Staking";
    string public constant version = "1";
    bytes2 public constant EIP191_HEADER = 0x1901;
    bytes32 public EIP712_DOMAIN_SEPARATOR;
    bytes32 public constant EIP712_STAKE_TYPEHASH =
        keccak256(
            "Stake(address staker,uint256 amount,uint256 nonce,uint256 expiry)"
        );
    bytes32 public constant EIP712_UNSTAKE_TYPEHASH =
        keccak256(
            "Unstake(address staker,uint256 amount,uint256 nonce,uint256 expiry)"
        );
    bytes32 public constant EIP712_WITHDRAW_TYPEHASH =
        keccak256(
            "Withdraw(address staker,uint256 amount,uint256 nonce,uint256 expiry)"
        );

    IFeePool private feePool;
    IERC20 private sportX;
    ISportXVault private sportXVault;
    IStakingParameters private stakingParameters;
    IPermissions private permissions;
    ISportXStakingRewardsPool private sportXStakingRewardsPool;

    mapping(address => uint256) private stakeNonces;
    mapping(address => uint256) private unstakeNonces;
    mapping(address => uint256) private withdrawNonces;
    mapping(address => uint256) private previousEpochRewards; // mapping from token => amount
    mapping(address => uint256) private previousEpochClaimedRewards; // mapping from token => amount
    uint256 private epoch;
    mapping(address => uint256) private stakedAmounts;
    uint256 private totalStakedAmount;
    mapping(uint256 => mapping(address => mapping(address => bool)))
        private rewardsClaimed; // mapping from epoch => token => address => reward claimed true/false
    mapping(address => uint256) private pendingWithdrawAmounts;
    mapping(address => uint256) private latestUnstakeTime;
    uint256 private startEpochTime;

    event Stake(address indexed staker, uint256 amount, address tokenSender);
    event Unstake(address indexed staker, uint256 amount);
    event Withdraw(address indexed staker, uint256 amount);
    event EpochFinalized(uint256 newEpochNumber);
    event RewardsClaimed(
        address indexed staker,
        address indexed token,
        uint256 amount,
        uint256 epoch
    );

    constructor(
        IERC20 _sportX,
        IStakingParameters _stakingParameters,
        IPermissions _permissions,
        uint256 _chainId
    ) {
        sportX = _sportX;
        stakingParameters = _stakingParameters;
        permissions = _permissions;

        EIP712_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                _chainId,
                address(this)
            )
        );

        startEpochTime = block.timestamp;
    }

    /// @notice Throws if the caller is not a super admin.
    modifier onlySuperAdmin() {
        require(
            permissions.hasRole(permissions.DEFAULT_ADMIN_ROLE(), msg.sender),
            "NOT_DEFAULT_ADMIN_ROLE"
        );
        _;
    }

    /// @notice Initializes this contract with reference to other contracts
    ///         in the protocol.
    function initialize(
        ISportXVault _sportXVault,
        IFeePool _feePool,
        ISportXStakingRewardsPool _sportXStakingRewardsPool
    ) external notInitialized onlySuperAdmin {
        sportXVault = _sportXVault;
        feePool = _feePool;
        sportXStakingRewardsPool = _sportXStakingRewardsPool;
        initialized = true;
    }

    function finalizeEpoch() external override {
        require(canFinalizeEpoch(), "EPOCH_NOT_OVER");

        address[] memory poolTokens = stakingParameters.getPoolTokens();

        for (uint256 i = 0; i < poolTokens.length; i++) {
            address token = poolTokens[i];
            uint256 rewardMultiplier =
                stakingParameters.getRewardMultiplier(token);
            address rewardPool = getCorrectRewardsPoolAddress(token);
            previousEpochRewards[token] = IERC20(token)
                .balanceOf(rewardPool)
                .mul(rewardMultiplier)
                .div(FRACTION_PRECISION);

            previousEpochClaimedRewards[token] = 0;
        }

        epoch = epoch + 1;
        startEpochTime = block.timestamp;
        emit EpochFinalized(epoch);
    }

    function claimRewards(address staker, address token)
        external
        override
        nonReentrant
    {
        require(epoch > 0, "EPOCH_TOO_LOW");
        require(
            !rewardsClaimed[epoch - 1][token][staker],
            "REWARDS_ALREADY_CLAIMED"
        );
        uint256 reward =
            previousEpochRewards[token].mul(stakedAmounts[staker]).div(
                totalStakedAmount
            );
        if (previousEpochClaimedRewards[token] >= previousEpochRewards[token]) {
            revert("ALL_REWARDS_CLAIMED");
        } else if (
            reward >
            previousEpochRewards[token].sub(previousEpochClaimedRewards[token])
        ) {
            // There is not enough to fully fill the reward, so give the remaining
            uint256 adjustedReward =
                previousEpochRewards[token].sub(
                    previousEpochClaimedRewards[token]
                );
            previousEpochClaimedRewards[token] = previousEpochRewards[token];
            rewardsClaimed[epoch - 1][token][staker] = true;
            payoutReward(staker, token, adjustedReward);
            emit RewardsClaimed(staker, token, adjustedReward, epoch - 1);
        } else {
            previousEpochClaimedRewards[token] = previousEpochClaimedRewards[
                token
            ]
                .add(reward);
            rewardsClaimed[epoch - 1][token][staker] = true;
            payoutReward(staker, token, reward);
            emit RewardsClaimed(staker, token, reward, epoch - 1);
        }
    }

    function stake(uint256 amount) external override {
        _stake(msg.sender, amount, msg.sender);
    }

    function metaStake(
        address staker,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    EIP191_HEADER,
                    EIP712_DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            EIP712_STAKE_TYPEHASH,
                            staker,
                            amount,
                            nonce,
                            expiry
                        )
                    )
                )
            );

        require(staker != address(0), "INVALID_STAKER");
        require(staker == ecrecover(digest, v, r, s), "INVALID_SIGNATURE");
        require(expiry == 0 || block.timestamp <= expiry, "META_STAKE_EXPIRED");
        require(nonce == stakeNonces[staker]++, "INVALID_NONCE");

        _stake(staker, amount, staker);
    }

    function stakeBehalf(address staker, uint256 amount) external override {
        _stake(staker, amount, msg.sender);
    }

    function unstake(uint256 amount) external override {
        require(
            amount <= stakedAmounts[msg.sender],
            "INSUFFICIENT_STAKED_SPORTX"
        );
        _unstake(msg.sender, amount);
    }

    function metaUnstake(
        address staker,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(staker != address(0), "INVALID_STAKER");
        require(expiry == 0 || block.timestamp <= expiry, "META_STAKE_EXPIRED");
        require(nonce == unstakeNonces[staker]++, "INVALID_NONCE");
        require(amount <= stakedAmounts[staker], "INSUFFICIENT_STAKED_SPORTX");

        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    EIP191_HEADER,
                    EIP712_DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            EIP712_UNSTAKE_TYPEHASH,
                            staker,
                            amount,
                            nonce,
                            expiry
                        )
                    )
                )
            );

        require(staker == ecrecover(digest, v, r, s), "INVALID_SIGNATURE");

        _unstake(staker, amount);
    }

    function withdraw(uint256 amount) external override {
        require(
            amount <= pendingWithdrawAmounts[msg.sender],
            "INSUFFICIENT_UNSTAKED_SPORTX"
        );
        require(
            block.timestamp >
                latestUnstakeTime[msg.sender].add(
                    stakingParameters.getWithdrawDelay()
                ),
            "INSUFFICIENT_TIME_PASSED_SINCE_UNSTAKE"
        );
        _withdraw(msg.sender, amount);
    }

    function metaWithdraw(
        address staker,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(staker != address(0), "INVALID_STAKER");
        require(
            expiry == 0 || block.timestamp <= expiry,
            "META_WITHDRAW_EXPIRED"
        );
        require(nonce == withdrawNonces[staker]++, "INVALID_NONCE");
        require(
            amount <= pendingWithdrawAmounts[staker],
            "INSUFFICIENT_UNSTAKED_SPORTX"
        );
        require(
            block.timestamp >
                latestUnstakeTime[staker].add(
                    stakingParameters.getWithdrawDelay()
                ),
            "INSUFFICIENT_TIME_PASSED_SINCE_UNSTAKE"
        );

        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    EIP191_HEADER,
                    EIP712_DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            EIP712_WITHDRAW_TYPEHASH,
                            staker,
                            amount,
                            nonce,
                            expiry
                        )
                    )
                )
            );

        require(staker == ecrecover(digest, v, r, s), "INVALID_SIGNATURE");

        _withdraw(staker, amount);
    }

    function getStakeNonces(address staker)
        public
        view
        override
        returns (uint256)
    {
        return stakeNonces[staker];
    }

    function getUnstakeNonces(address staker)
        public
        view
        override
        returns (uint256)
    {
        return unstakeNonces[staker];
    }

    function getWithdrawNonces(address staker)
        public
        view
        override
        returns (uint256)
    {
        return withdrawNonces[staker];
    }

    function getPreviousEpochRewards(address token)
        public
        view
        override
        returns (uint256)
    {
        return previousEpochRewards[token];
    }

    function getPreviousEpochClaimedRewards(address token)
        public
        view
        override
        returns (uint256)
    {
        return previousEpochClaimedRewards[token];
    }

    function getEpoch() public view override returns (uint256) {
        return epoch;
    }

    function getStakedAmounts(address staker)
        public
        view
        override
        returns (uint256)
    {
        return stakedAmounts[staker];
    }

    function getTotalStakedAmount() public view override returns (uint256) {
        return totalStakedAmount;
    }

    function getRewardsClaimed(
        uint256 _epoch,
        address token,
        address staker
    ) public view override returns (bool) {
        return rewardsClaimed[_epoch][token][staker];
    }

    function getPendingWithdrawAmounts(address staker)
        public
        view
        override
        returns (uint256)
    {
        return pendingWithdrawAmounts[staker];
    }

    function getLatestUnstakeTime(address staker)
        public
        view
        override
        returns (uint256)
    {
        return latestUnstakeTime[staker];
    }

    function canFinalizeEpoch() public view override returns (bool) {
        return
            block.timestamp >
            startEpochTime.add(stakingParameters.getEpochLength());
    }

    function getStartEpochTime() public view override returns (uint256) {
        return startEpochTime;
    }

    function getCorrectRewardsPoolAddress(address token)
        private
        view
        returns (address)
    {
        if (token == address(sportX)) {
            return address(sportXStakingRewardsPool);
        } else {
            return address(feePool);
        }
    }

    function _withdraw(address staker, uint256 amount) private {
        pendingWithdrawAmounts[staker] = pendingWithdrawAmounts[staker].sub(
            amount
        );

        sportXVault.withdraw(staker, amount);
        emit Withdraw(staker, amount);
    }

    function _unstake(address staker, uint256 amount) private {
        stakedAmounts[staker] = stakedAmounts[staker].sub(amount);
        totalStakedAmount = totalStakedAmount.sub(amount);
        pendingWithdrawAmounts[staker] = pendingWithdrawAmounts[staker].add(
            amount
        );
        latestUnstakeTime[staker] = block.timestamp;
        emit Unstake(staker, amount);
    }

    function _stake(
        address staker,
        uint256 amount,
        address tokenSender
    ) private {
        stakedAmounts[staker] = stakedAmounts[staker].add(amount);
        totalStakedAmount = totalStakedAmount.add(amount);
        sportXVault.deposit(tokenSender, amount);
        emit Stake(staker, amount, tokenSender);
    }

    function payoutReward(
        address staker,
        address token,
        uint256 reward
    ) private {
        if (token == address(sportX)) {
            sportXStakingRewardsPool.stakeBehalf(staker, reward);
        } else {
            feePool.withdrawFee(staker, token, reward);
        }
    }
}
