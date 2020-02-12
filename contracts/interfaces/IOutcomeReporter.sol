pragma solidity 0.5.16;

import "../libraries/LibOutcome.sol";
contract IOutcomeReporter {
    function getReportedOutcome(bytes32)
        public
        view
        returns (LibOutcome.Outcome);
    function getReportTime(bytes32) public view returns (uint256);
    function reportOutcome(bytes32, LibOutcome.Outcome) public;
    function reportOutcomes(bytes32[] memory, LibOutcome.Outcome[] memory)
        public;
}
