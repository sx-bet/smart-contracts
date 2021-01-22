// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;
pragma abicoder v2;

import "../../interfaces/staking/IFeePool.sol";
import "../../interfaces/staking/IStaking.sol";
import "../../interfaces/permissions/IPermissions.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract FeePool is IFeePool {
    using SafeERC20 for IERC20;

    IStaking private staking;
    IPermissions private permissions;

    constructor(IStaking _staking, IPermissions _permissions) {
        staking = _staking;
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

    function withdrawFee(
        address user,
        address baseToken,
        uint256 amount
    ) external override onlyStaking {
        IERC20(baseToken).safeTransfer(user, amount);
    }

    function emergencyWithdraw(address token, uint256 amount)
        external
        override
        onlyDefaultAdminRole
    {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
