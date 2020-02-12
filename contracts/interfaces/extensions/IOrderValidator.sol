pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../libraries/LibOrder.sol";
contract IOrderValidator {
    function getOrderStatus(LibOrder.Order memory, bytes memory)
        public
        view
        returns (string memory);

    function getMultiOrderStatus(LibOrder.Order[] memory, bytes[] memory)
        public
        view
        returns (string[] memory);

    function getFillStatus(LibOrder.FillDetails memory, bytes memory, address)
        public
        view
        returns (string memory);

    function getMetaFillStatus(
        LibOrder.FillDetails memory,
        address,
        bytes memory,
        bytes memory)
        public view returns (string memory);
}
