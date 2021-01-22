// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;
pragma abicoder v2;

import "../../interfaces/staking/IStakingParameters.sol";
import "../../interfaces/permissions/IPermissions.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract StakingParameters is IStakingParameters {
    IPermissions private permissions;

    // Config variables
    uint256 public constant FRACTION_PRECISION = 10**20;
    mapping(address => uint256) public rewardMultipliers; // the convention is 10**20 = 100%
    address[] public poolTokens;
    uint256 public epochLength;
    uint256 public withdrawDelay;

    constructor(
        IPermissions _permissions,
        uint256 _epochLength,
        uint256 _withdrawDelay,
        address[] memory _poolTokens
    ) {
        permissions = _permissions;
        epochLength = _epochLength;
        withdrawDelay = _withdrawDelay;
        poolTokens = _poolTokens;
    }

    /// @notice Throws if the user is not the system parameters role
    modifier onlySystemParametersRole() {
        require(
            permissions.hasRole(
                permissions.SYSTEM_PARAMETERS_ROLE(),
                msg.sender
            ),
            "NOT_SYSTEM_PARAMETERS_ROLE"
        );
        _;
    }

    function setEpochLength(uint256 newEpochLength)
        public
        override
        onlySystemParametersRole
    {
        epochLength = newEpochLength;
    }

    function setRewardMultiplier(address token, uint256 newRewardMultiplier)
        public
        override
        onlySystemParametersRole
    {
        require(
            newRewardMultiplier <= FRACTION_PRECISION,
            "NEW_REWARD_MULTIPLIER_TOO_HIGH"
        );
        rewardMultipliers[token] = newRewardMultiplier;
    }

    function setPoolTokens(address[] memory _poolTokens)
        public
        override
        onlySystemParametersRole
    {
        poolTokens = _poolTokens;
    }

    function setWithdrawDelay(uint256 newWithdrawDelay)
        public
        override
        onlySystemParametersRole
    {
        withdrawDelay = newWithdrawDelay;
    }

    function getPoolTokens() public view override returns (address[] memory) {
        return poolTokens;
    }

    function getEpochLength() public view override returns (uint256) {
        return epochLength;
    }

    function getRewardMultiplier(address token)
        public
        view
        override
        returns (uint256)
    {
        return rewardMultipliers[token];
    }

    function getWithdrawDelay() public view override returns (uint256) {
        return withdrawDelay;
    }
}
