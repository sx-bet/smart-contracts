pragma solidity 0.5.16;

contract ISystemParameters {
    function getOracleFeeRecipient() public view returns (address);
    function setNewOracleFeeRecipient(address) public;
}
