pragma solidity 0.5.16;

contract IDetailedTokenDAI {
    function name() public view returns (bytes32);
    function symbol() public view returns (bytes32);
    function decimals() public view returns (uint256);
}
