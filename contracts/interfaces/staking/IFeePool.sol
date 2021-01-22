// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;
pragma abicoder v2;

abstract contract IFeePool {
    function withdrawFee(
        address user,
        address baseToken,
        uint256 amount
    ) external virtual;

    function emergencyWithdraw(address token, uint256 amount) external virtual;
}
