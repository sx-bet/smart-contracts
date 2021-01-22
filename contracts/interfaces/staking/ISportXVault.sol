// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

abstract contract ISportXVault {
    /// @notice Throws if not in emergency hatch mode
    function emergencyWithdraw() public virtual;

    function deposit(address staker, uint256 amount) public virtual;

    function withdraw(address staker, uint256 amount) public virtual;

    function openEmergencyHatch() external virtual;

    function getEmergencyHatch() public view virtual returns (bool);

    function getBalances(address holder) public view virtual returns (uint256);
}
