pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../libraries/LibOutcome.sol";
import "../libraries/LibOrder.sol";
import "../interfaces/trading/IFillOrder.sol";
import "../interfaces/trading/IFeeSchedule.sol";
import "../interfaces/ISystemParameters.sol";
import "../interfaces/IOutcomeReporter.sol";
import "../interfaces/IAffiliateRegistry.sol";
import "../interfaces/IEscrow.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

/// @title Escrow
/// @notice Central location that stores all escrow when
///         swaps are traded.
contract Escrow is IEscrow {
    using SafeMath for uint256;

    ISystemParameters private systemParameters;
    IFillOrder private fillOrder;
    IOutcomeReporter private outcomeReporter;
    IFeeSchedule private feeSchedule;
    IAffiliateRegistry private affiliateRegistry;

    // marketHash => baseToken => owner => side => amount
    mapping(bytes32 => mapping(address => mapping(address => mapping(uint8 => uint256)))) returnAmounts;
    mapping(bytes32 => mapping(address => mapping(address => mapping(uint8 => uint256)))) stakedAmounts;

    struct BetFee {
        uint256 oracleFee;
        uint256 affiliateFee;
    }

    event BetSettled(
        address indexed owner,
        bytes32 indexed marketHash,
        address indexed baseToken,
        LibOutcome.Outcome outcome,
        uint256 settledAmount,
        uint256 oracleFeeAmount,
        uint256 affiliateFeeAmount
    );

    constructor(
        ISystemParameters _systemParameters,
        IFillOrder _fillOrder,
        IOutcomeReporter _outcomeReporter,
        IFeeSchedule _feeSchedule,
        IAffiliateRegistry _affiliateRegistry
    ) public {
        systemParameters = _systemParameters;
        fillOrder = _fillOrder;
        outcomeReporter = _outcomeReporter;
        feeSchedule = _feeSchedule;
        affiliateRegistry = _affiliateRegistry;
    }

    /// @notice Throws if the caller is not the FillOrder contract.
    modifier onlyFillOrder() {
        require(msg.sender == address(fillOrder), "ONLY_FILL_ORDER");
        _;
    }

    /// @notice Throws if the market's tokens are not redeemable.
    /// @param marketHash The market to check.
    modifier marketTokensRedeemable(bytes32 marketHash) {
        require(isMarketRedeemable(marketHash), "INVALID_REDEMPTION_TIME");
        _;
    }

    /// @notice Redeems outcome one or outcome two return amounts after a market
    ///         has been resolved.
    /// @param owner The user to redeem for.
    /// @param marketHash The market that is resolved.
    /// @param baseTokenAddress The token to resolve.
    function settleBet(
        address owner,
        bytes32 marketHash,
        address baseTokenAddress
    ) public marketTokensRedeemable(marketHash) {
        IERC20 baseToken = IERC20(baseTokenAddress);
        LibOutcome.Outcome marketResult = outcomeReporter.getReportedOutcome(
            marketHash
        );
        uint256 outcomeOneEligibility = returnAmounts[marketHash][baseTokenAddress][owner][uint8(
            LibOutcome.Outcome.OUTCOME_ONE
        )];
        uint256 outcomeTwoEligibility = returnAmounts[marketHash][baseTokenAddress][owner][uint8(
            LibOutcome.Outcome.OUTCOME_TWO
        )];
        uint256 outcomeOneStake = stakedAmounts[marketHash][baseTokenAddress][owner][uint8(
            LibOutcome.Outcome.OUTCOME_ONE
        )];
        uint256 outcomeTwoStake = stakedAmounts[marketHash][baseTokenAddress][owner][uint8(
            LibOutcome.Outcome.OUTCOME_TWO
        )];
        BetFee memory betFees;
        uint256 payout;

        if (
            marketResult == LibOutcome.Outcome.OUTCOME_ONE &&
            outcomeOneEligibility > 0
        ) {
            uint256 profits = outcomeOneEligibility.sub(outcomeOneStake);
            betFees = settleFees(baseTokenAddress, owner, profits);
            payout = outcomeOneEligibility.sub(betFees.oracleFee).sub(
                betFees.affiliateFee
            );
            returnAmounts[marketHash][baseTokenAddress][owner][uint8(
                LibOutcome.Outcome.OUTCOME_ONE
            )] = 0;
        } else if (
            marketResult == LibOutcome.Outcome.OUTCOME_TWO &&
            outcomeTwoEligibility > 0
        ) {
            uint256 profits = outcomeTwoEligibility.sub(outcomeTwoStake);
            betFees = settleFees(baseTokenAddress, owner, profits);
            payout = outcomeTwoEligibility.sub(betFees.oracleFee).sub(
                betFees.affiliateFee
            );
            returnAmounts[marketHash][baseTokenAddress][owner][uint8(
                LibOutcome.Outcome.OUTCOME_TWO
            )] = 0;
        } else if (
            marketResult == LibOutcome.Outcome.VOID &&
            (outcomeOneStake > 0 || outcomeTwoStake > 0)
        ) {
            if (outcomeOneStake > 0) {
                payout = outcomeOneStake;
                stakedAmounts[marketHash][baseTokenAddress][owner][uint8(
                    LibOutcome.Outcome.OUTCOME_ONE
                )] = 0;
            }
            if (outcomeTwoStake > 0) {
                payout = payout.add(outcomeTwoStake);
                stakedAmounts[marketHash][baseTokenAddress][owner][uint8(
                    LibOutcome.Outcome.OUTCOME_TWO
                )] = 0;
            }
        } else {
            revert("MARKET_WRONG_RESOLUTION");
        }

        require(baseToken.transfer(owner, payout), "CANNOT_TRANSFER_ESCROW");

        emit BetSettled(
            owner,
            marketHash,
            baseTokenAddress,
            marketResult,
            payout,
            betFees.oracleFee,
            betFees.affiliateFee
        );
    }

    /// @notice Updates the user's escrowed amount they have in the market.
    /// @param marketHash The market to redeem.
    /// @param baseToken The token with which they are betting.
    /// @param user The user to update.
    /// @param outcome The side to update.
    /// @param amount The amount to add.
    function updateStakedAmount(
        bytes32 marketHash,
        address baseToken,
        address user,
        LibOutcome.Outcome outcome,
        uint256 amount
    ) public onlyFillOrder {
        stakedAmounts[marketHash][baseToken][user][uint8(
            outcome
        )] = stakedAmounts[marketHash][baseToken][user][uint8(outcome)].add(
            amount
        );
    }

    /// @notice Updates the user's return amount
    /// @param marketHash The market for which they are betting on outcome one.
    /// @param baseToken The token with which they are betting.
    /// @param user The user to update.
    /// @param outcome The outcome to increase
    /// @param amount The amount to add.
    function increaseReturnAmount(
        bytes32 marketHash,
        address baseToken,
        address user,
        LibOutcome.Outcome outcome,
        uint256 amount
    ) public onlyFillOrder {
        returnAmounts[marketHash][baseToken][user][uint8(
            outcome
        )] = returnAmounts[marketHash][baseToken][user][uint8(outcome)].add(
            amount
        );
    }

    /// @notice Checks if the market's tokens are redeemable.
    /// @param marketHash The market to check.
    /// @return true if the market's tokens are redeemable, false otherwise.
    function isMarketRedeemable(bytes32 marketHash) public view returns (bool) {
        uint256 reportTime = outcomeReporter.getReportTime(marketHash);
        if (reportTime > 0) {
            return now > reportTime;
        } else {
            return false;
        }
    }

    /// @notice Checks if the owner has a valid redeemable bet.
    /// @param owner The owner of the bet.
    /// @param marketHash The market to check.
    /// @param baseToken The base token to check.
    /// @return true if the owner has a valid redeemable bet for this market, false otherwise.
    function getEligibility(
        address owner,
        bytes32 marketHash,
        address baseToken
    ) public view returns (Eligibility memory eligibility) {
        if (!isMarketRedeemable(marketHash)) {
            return
                Eligibility({
                    hasEligibility: false,
                    outcome: LibOutcome.Outcome.VOID,
                    amount: 0
                });
        }
        LibOutcome.Outcome marketResult = outcomeReporter.getReportedOutcome(
            marketHash
        );

        uint256 outcomeOneEligibility = returnAmounts[marketHash][baseToken][owner][uint8(
            LibOutcome.Outcome.OUTCOME_ONE
        )];
        uint256 outcomeTwoEligibility = returnAmounts[marketHash][baseToken][owner][uint8(
            LibOutcome.Outcome.OUTCOME_TWO
        )];
        uint256 outcomeOneStake = stakedAmounts[marketHash][baseToken][owner][uint8(
            LibOutcome.Outcome.OUTCOME_ONE
        )];
        uint256 outcomeTwoStake = stakedAmounts[marketHash][baseToken][owner][uint8(
            LibOutcome.Outcome.OUTCOME_TWO
        )];

        if (
            marketResult == LibOutcome.Outcome.OUTCOME_ONE &&
            outcomeOneEligibility > 0
        ) {
            return
                Eligibility({
                    hasEligibility: true,
                    outcome: LibOutcome.Outcome.OUTCOME_ONE,
                    amount: outcomeOneEligibility
                });
        } else if (
            marketResult == LibOutcome.Outcome.OUTCOME_TWO &&
            outcomeTwoEligibility > 0
        ) {
            return
                Eligibility({
                    hasEligibility: true,
                    outcome: LibOutcome.Outcome.OUTCOME_TWO,
                    amount: outcomeTwoEligibility
                });
        } else if (
            marketResult == LibOutcome.Outcome.VOID &&
            (outcomeOneStake > 0 || outcomeTwoStake > 0)
        ) {
            return
                Eligibility({
                    hasEligibility: true,
                    outcome: LibOutcome.Outcome.VOID,
                    amount: outcomeOneStake.add(outcomeTwoStake)
                });
        } else {
            return
                Eligibility({
                    hasEligibility: false,
                    outcome: LibOutcome.Outcome.VOID,
                    amount: 0
                });
        }
    }

    function getReturnAmount(
        bytes32 marketHash,
        address baseToken,
        address owner,
        LibOutcome.Outcome outcome
    ) public view returns (uint256) {
        return returnAmounts[marketHash][baseToken][owner][uint8(outcome)];
    }

    function getStakedAmount(
        bytes32 marketHash,
        address baseToken,
        address owner,
        LibOutcome.Outcome outcome
    ) public view returns (uint256) {
        return stakedAmounts[marketHash][baseToken][owner][uint8(outcome)];
    }

    /// @notice Settles fees for an owner and for a market.
    /// @param baseToken The token to settle.
    /// @param owner The owner.
    /// @param profits How much profit the owner made off this bet.
    /// @return The fees that were settled.
    function settleFees(address baseToken, address owner, uint256 profits)
        private
        returns (BetFee memory)
    {
        address affiliate = affiliateRegistry.getAffiliate(owner);
        uint256 affiliateFeeFrac = affiliateRegistry.getAffiliateFeeFrac(
            affiliate
        );

        uint256 oracleFee = settleOracleFee(baseToken, profits);
        uint256 affiliateFee = settleAffiliateFee(
            baseToken,
            profits,
            affiliate,
            affiliateFeeFrac
        );

        return BetFee({oracleFee: oracleFee, affiliateFee: affiliateFee});
    }

    /// @notice Settles the affiliate fee for a market.
    /// @param baseToken The token to settle.
    /// @param profits The profits made on the bet.
    /// @param affiliate The affiliate set for the winner of the bet.
    /// @param affiliateFeeFrac The fee assigned to this affiliate.
    /// @return The affiliate fee paid.
    function settleAffiliateFee(
        address baseToken,
        uint256 profits,
        address affiliate,
        uint256 affiliateFeeFrac
    ) private returns (uint256) {
        IERC20 token = IERC20(baseToken);
        uint256 affiliateFeeAmount = profits.mul(affiliateFeeFrac).div(
            LibOrder.getOddsPrecision()
        );
        if (affiliateFeeAmount > 0) {
            require(
                token.transfer(affiliate, affiliateFeeAmount),
                "CANNOT_TRANSFER_AFFILIATE_FEE"
            );
        }
        return affiliateFeeAmount;
    }

    /// @notice Calculates oracle fee to be paid based on the market profits
    /// @param baseToken The base token to settle.
    /// @param profits Profit of user's outcome eligibility.
    /// @return The amount oracle fee to be paid.
    function settleOracleFee(address baseToken, uint256 profits)
        private
        returns (uint256)
    {
        IERC20 token = IERC20(baseToken);
        uint256 oracleFee = feeSchedule.getOracleFees(baseToken);
        uint256 oracleFeeAmount = profits.mul(oracleFee).div(
            LibOrder.getOddsPrecision()
        );
        address oracleFeeRecipient = systemParameters.getOracleFeeRecipient();

        if (oracleFeeAmount > 0) {
            require(
                token.transfer(oracleFeeRecipient, oracleFeeAmount),
                "CANNOT_TRANSFER_FEE"
            );
        }
        return oracleFeeAmount;
    }
}
