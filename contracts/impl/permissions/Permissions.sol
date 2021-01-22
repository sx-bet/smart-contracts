// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

import "../../interfaces/permissions/IPermissions.sol";

contract Permissions is IPermissions {
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OUTCOME_REPORTER_ROLE, msg.sender);
        _setupRole(SYSTEM_PARAMETERS_ROLE, msg.sender);
    }
}
