pragma solidity 0.5.16;

contract IAffiliateRegistry {
    function setAffiliate(address member, address affiliate) public;
    function setAffiliateFeeFrac(address affiliate, uint256 fee) public;
    function setDefaultAffiliate(address affiliate) public;
    function getAffiliate(address member) public view returns (address);
    function getAffiliateFeeFrac(address affiliate) public view returns (uint256);
    function getDefaultAffiliate() public view returns (address);
}
