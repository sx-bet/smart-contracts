// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract IPermissions is AccessControl {
    bytes32 public constant OUTCOME_REPORTER_ROLE =
        keccak256("OUTCOME_REPORTER_ROLE");
    bytes32 public constant SYSTEM_PARAMETERS_ROLE =
        keccak256("SYSTEM_PARAMETERS_ROLE");
}
