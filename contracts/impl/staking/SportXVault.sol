// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;
pragma abicoder v2;

import "../../interfaces/staking/ISportXVault.sol";
import "../../interfaces/staking/IStaking.sol";
import "../../interfaces/permissions/IPermissions.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract SportXVault is ISportXVault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IStaking private staking;
    IPermissions private permissions;
    IERC20 private sportX;

    bool private emergencyHatch;
    mapping(address => uint256) private balances;

    constructor(
        IStaking _staking,
        IPermissions _permissions,
        IERC20 _sportX
    ) {
        emergencyHatch = false;
        staking = _staking;
        permissions = _permissions;
        sportX = _sportX;
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

    /// @notice Throws if not in emergencyHatch mode
    modifier onlyDuringEmergencyHatch() {
        require(emergencyHatch, "NOT_IN_EMERGENCY_HATCH");
        _;
    }

    /// @notice Throws if not in emergency hatch mode
    function emergencyWithdraw() public override onlyDuringEmergencyHatch {
        uint256 callerBalance = balances[msg.sender];
        balances[msg.sender] = 0;
        sportX.safeTransfer(msg.sender, callerBalance);
    }

    function deposit(address staker, uint256 amount)
        public
        override
        onlyStaking
    {
        balances[staker] = balances[staker].add(amount);
        sportX.safeTransferFrom(staker, address(this), amount);
    }

    function withdraw(address staker, uint256 amount)
        public
        override
        onlyStaking
    {
        balances[staker] = balances[staker].sub(amount);
        sportX.safeTransfer(staker, amount);
    }

    function openEmergencyHatch() external override onlyDefaultAdminRole {
        emergencyHatch = true;
    }

    function getEmergencyHatch() public view override returns (bool) {
        return emergencyHatch;
    }

    function getBalances(address holder)
        public
        view
        override
        returns (uint256)
    {
        return balances[holder];
    }
}
