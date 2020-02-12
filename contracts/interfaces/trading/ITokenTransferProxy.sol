pragma solidity 0.5.16;

contract ITokenTransferProxy {
    function transferFrom(address, address, address, uint256)
        public
        returns (bool);
}
