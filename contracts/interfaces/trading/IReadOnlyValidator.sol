pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../libraries/LibOrder.sol";

contract IReadOnlyValidator {
    function getOrderStatus(LibOrder.Order memory, bytes memory)
        public
        view
        returns (string memory);
    function getOrderStatusForTaker(
        LibOrder.Order memory,
        address,
        uint256,
        bytes memory)
        public view returns (string memory);
    function getCumulativeOrderStatusForTaker(
        LibOrder.Order[] memory,
        address,
        uint256[] memory,
        bytes[] memory)
        public view returns (string memory);
}
