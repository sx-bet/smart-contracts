pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../libraries/LibOrder.sol";

contract IEIP712FillHasher {
    function getOrderHash(LibOrder.Order memory) public  pure returns (bytes32);
    function getOrdersArrayHash(LibOrder.Order[] memory) public  pure returns (bytes32);
    function getMakerSigsArrayHash(bytes[] memory) public  pure returns (bytes32);
    function getTakerAmountsArrayHash(uint256[] memory) public  pure returns (bytes32);
    function getFillObjectHash(LibOrder.FillObject memory) public  pure returns (bytes32);
    function getDetailsHash(LibOrder.FillDetails memory) public  view returns (bytes32);
    function getDomainHash() public  view returns (bytes32);
}