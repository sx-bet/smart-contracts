pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../libraries/LibOrder.sol";

contract ICancelOrder {
    function cancelOrder(LibOrder.Order memory order) public;
    function batchCancelOrders(LibOrder.Order[] memory makerOrders) public;
}
