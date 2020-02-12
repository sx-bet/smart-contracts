pragma solidity 0.5.16;

contract ISuperAdminRole {
    function isSuperAdmin(address account) public view returns (bool);
    function addSuperAdmin(address account) public;
    function removeSuperAdmin(address account) public;
    function getSuperAdminCount() public view returns (uint256);
}
