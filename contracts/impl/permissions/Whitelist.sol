pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../interfaces/permissions/ISuperAdminRole.sol";
import "../../interfaces/permissions/IWhitelist.sol";


/// @title Whitelist
/// @notice The Whitelist contract has a whitelist of addresses, and provides basic authorization control functions.
///         This simplifies the implementation of "user permissions".
///         This Whitelist is special in that only super admins can add others to this whitelist.
///         This is copied verbatim, plus the SuperAdminRole authorization, from openzeppelin.
contract Whitelist is IWhitelist {
    ISuperAdminRole internal superAdminRole;

    mapping (address => bool) public whitelisted;

    constructor(ISuperAdminRole _superAdminRole) public {
        superAdminRole = _superAdminRole;
    }

    /// @notice Throws if the operator is not a super admin.
    /// @param operator The operator.
    modifier onlySuperAdmin(address operator) {
        require(
            superAdminRole.isSuperAdmin(operator),
            "NOT_A_SUPER_ADMIN"
        );
        _;
    }

    /// @notice Adds an operator to the whitelist
    ///         Only callable by the SuperAdmin role.
    /// @param operator The operator to add.
    function addAddressToWhitelist(address operator)
        public
        onlySuperAdmin(msg.sender)
    {
        whitelisted[operator] = true;
    }

    /// @notice Removes an address from the whitelist
    ///         Only callable by the SuperAdmin role.
    /// @param operator The operator to remove.
    function removeAddressFromWhitelist(address operator)
        public
        onlySuperAdmin(msg.sender)
    {
        whitelisted[operator] = false;
    }

    /// @notice Checks if the operator is whitelisted.
    /// @param operator The operator.
    /// @return true if the operator is whitelisted, false otherwise
    function getWhitelisted(address operator) public view returns (bool) {
        return whitelisted[operator];
    }
}