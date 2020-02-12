pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../libraries/LibOrder.sol";

contract IFills {
    function getFilled(bytes32) public view returns (uint256);
    function getCancelled(bytes32) public view returns (bool);
    function getFillHashSubmitted(bytes32) public view returns (bool);
    function orderHasSpace(LibOrder.Order memory, uint256)
        public
        view
        returns (bool);
    function remainingSpace(LibOrder.Order memory)
        public
        view
        returns (uint256);
    function isOrderCancelled(LibOrder.Order memory) public view returns (bool);
    function fill(LibOrder.Order memory, uint256) public returns (uint256);
    function cancel(LibOrder.Order memory) public;
    function setFillHashSubmitted(bytes32) public;
}
