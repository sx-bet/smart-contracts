// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;
pragma abicoder v2;

import "../../interfaces/staking/ISportXStakingRewardsPool.sol";
import "../../interfaces/staking/IStaking.sol";
import "../../interfaces/staking/ISportXVault.sol";
import "../../interfaces/permissions/IPermissions.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract SportXStakingRewardsPool is ISportXStakingRewardsPool {
    using SafeERC20 for IERC20;

    IStaking private staking;
    IERC20 private sportX;
    ISportXVault private sportXVault;
    IPermissions private permissions;

    constructor(
        IStaking _staking,
        IERC20 _sportX,
        ISportXVault _sportXVault,
        IPermissions _permissions
    ) {
        staking = _staking;
        sportX = _sportX;
        sportXVault = _sportXVault;
        permissions = _permissions;
    }

    /// @notice Throws if the caller is not the Staking Contract
    modifier onlyStaking() {
        require(msg.sender == address(staking), "ONLY_STAKING_CONTRACT");
        _;
    }

    /// @notice Throws if the user is not a default admin
    modifier onlyDefaultAdminRole() {
        require(
            permissions.hasRole(permissions.DEFAULT_ADMIN_ROLE(), msg.sender),
            "CALLER_IS_NOT_DEFAULT_ADMIN"
        );
        _;
    }

    function emergencyWithdraw(uint256 amount)
        external
        override
        onlyDefaultAdminRole
    {
        sportX.safeTransfer(msg.sender, amount);
    }

    function stakeBehalf(address user, uint256 amount)
        external
        override
        onlyStaking
    {
        sportX.approve(address(sportXVault), amount);
        staking.stakeBehalf(user, amount);
    }
}
