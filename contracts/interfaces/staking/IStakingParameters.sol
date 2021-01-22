// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

abstract contract IStakingParameters {
    function setEpochLength(uint256 newEpochLength) public virtual;

    function setRewardMultiplier(address token, uint256 newRewardMultiplier)
        public
        virtual;

    function setPoolTokens(address[] memory _poolTokens) public virtual;

    function setWithdrawDelay(uint256 newWithdrawDelay) public virtual;

    function getPoolTokens() public view virtual returns (address[] memory);

    function getEpochLength() public view virtual returns (uint256);

    function getRewardMultiplier(address token)
        public
        view
        virtual
        returns (uint256);

    function getWithdrawDelay() public view virtual returns (uint256);
}
