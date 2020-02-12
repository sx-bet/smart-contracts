pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../libraries/LibOrder.sol";

contract IFillOrder {
    function fillOrders(LibOrder.FillDetails memory, bytes memory) public;
    function metaFillOrders(
        LibOrder.FillDetails memory,
        address,
        bytes memory,
        bytes memory)
        public;
}
