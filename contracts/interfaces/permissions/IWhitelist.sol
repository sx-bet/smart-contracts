pragma solidity 0.5.16;

contract IWhitelist {
    function addAddressToWhitelist(address) public;
    function removeAddressFromWhitelist(address) public;
    function getWhitelisted(address) public view returns (bool);
}
