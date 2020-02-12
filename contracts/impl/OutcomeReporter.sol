pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../libraries/LibOutcome.sol";
import "../interfaces/IOutcomeReporter.sol";
import "../interfaces/permissions/IWhitelist.sol";
import "./Initializable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/// @title OutcomeReporter
/// @notice Allows OutcomeReporter admins to report an initial outcome on an event.
contract OutcomeReporter is IOutcomeReporter {
    using SafeMath for uint256;

    IWhitelist private outcomeReporterWhitelist;

    mapping(bytes32 => LibOutcome.Outcome) private reportedOutcomes;
    mapping(bytes32 => uint256) private reportTime;

    event OutcomeReported(bytes32 marketHash, LibOutcome.Outcome outcome);

    constructor(
        IWhitelist _outcomeReporterWhitelist
    ) public {
        outcomeReporterWhitelist = _outcomeReporterWhitelist;
    }

    /// @notice Throws if the caller is not an Outcome Reporter admin.
    modifier onlyOutcomeReporterAdmin() {
        require(
            outcomeReporterWhitelist.getWhitelisted(msg.sender),
            "NOT_OUTCOME_REPORTER_ADMIN"
        );
        _;
    }

    /// @notice Throws if the market is already reported
    /// @param marketHash The market to check.
    modifier notAlreadyReported(bytes32 marketHash) {
        require(
            reportTime[marketHash] == 0,
            "MARKET_ALREADY_REPORTED"
        );
        _;
    }

    /// @notice Reports the initial outcome of the market.
    ///         Only callable by OutcomeReporter admins.
    ///         Can only be reported once.
    /// @param marketHash The market to report.
    /// @param reportedOutcome The outcome to report.
    function reportOutcome(bytes32 marketHash, LibOutcome.Outcome reportedOutcome)
        public
        onlyOutcomeReporterAdmin
        notAlreadyReported(marketHash)
    {
        reportedOutcomes[marketHash] = reportedOutcome;
        reportTime[marketHash] = now;

        emit OutcomeReported(marketHash, reportedOutcome);
    }

    /// @notice Reports the outcome for several markets.
    /// @param marketHashes The market hashes to report.
    /// @param outcomes The outcomes to report.
    function reportOutcomes(
        bytes32[] memory marketHashes,
        LibOutcome.Outcome[] memory outcomes
    ) public {
        uint256 marketHashesLength = marketHashes.length;
        for (uint256 i = 0; i < marketHashesLength; i++) {
            reportOutcome(marketHashes[i], outcomes[i]);
        }
    }

    function getReportedOutcome(bytes32 marketHash)
        public
        view
        returns (LibOutcome.Outcome)
    {
        return reportedOutcomes[marketHash];
    }

    function getReportTime(bytes32 marketHash) public view returns (uint256) {
        return reportTime[marketHash];
    }
}
