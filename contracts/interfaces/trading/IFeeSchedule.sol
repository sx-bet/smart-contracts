pragma solidity 0.5.16;

contract IFeeSchedule {
    function getOracleFees(address) public view returns (uint256);
    function setOracleFee(address, uint256) public;
}
