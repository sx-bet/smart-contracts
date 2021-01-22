// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

abstract contract IStaking {
    function finalizeEpoch() external virtual;

    function claimRewards(address staker, address token) external virtual;

    function stake(uint256 amount) external virtual;

    function metaStake(
        address staker,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual;

    function stakeBehalf(address staker, uint256 amount) external virtual;

    function unstake(uint256 amount) external virtual;

    function metaUnstake(
        address staker,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual;

    function withdraw(uint256 amount) external virtual;

    function metaWithdraw(
        address staker,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual;

    function getStakeNonces(address staker)
        public
        view
        virtual
        returns (uint256);

    function getUnstakeNonces(address staker)
        public
        view
        virtual
        returns (uint256);

    function getWithdrawNonces(address staker)
        public
        view
        virtual
        returns (uint256);

    function getPreviousEpochRewards(address token)
        public
        view
        virtual
        returns (uint256);

    function getPreviousEpochClaimedRewards(address token)
        public
        view
        virtual
        returns (uint256);

    function getEpoch() public view virtual returns (uint256);

    function getStakedAmounts(address staker)
        public
        view
        virtual
        returns (uint256);

    function getTotalStakedAmount() public view virtual returns (uint256);

    function getRewardsClaimed(
        uint256 epoch,
        address token,
        address staker
    ) public view virtual returns (bool);

    function getPendingWithdrawAmounts(address staker)
        public
        view
        virtual
        returns (uint256);

    function getLatestUnstakeTime(address staker)
        public
        view
        virtual
        returns (uint256);

    function canFinalizeEpoch() public view virtual returns (bool);

    function getStartEpochTime() public view virtual returns (uint256);
}
