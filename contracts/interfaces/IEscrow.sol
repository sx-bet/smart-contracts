pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../libraries/LibOutcome.sol";


contract IEscrow {
    struct Eligibility {
        bool hasEligibility;
        LibOutcome.Outcome outcome;
        uint256 amount;
    }

    function getReturnAmount(bytes32, address, address, LibOutcome.Outcome) public view returns (uint256);
    function getStakedAmount(bytes32, address, address, LibOutcome.Outcome) public view returns (uint256);
    function settleBet(address, bytes32, address) public;
    function updateStakedAmount(bytes32, address, address, LibOutcome.Outcome, uint256) public;
    function increaseReturnAmount(bytes32, address, address, LibOutcome.Outcome, uint256) public;
    function isMarketRedeemable(bytes32) public view returns (bool);
    function getEligibility(address, bytes32, address) public view returns (Eligibility memory);
}