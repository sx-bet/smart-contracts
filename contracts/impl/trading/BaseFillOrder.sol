pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../libraries/LibOrder.sol";
import "../../libraries/LibOrderAmounts.sol";
import "../../libraries/LibOutcome.sol";
import "../../interfaces/IEscrow.sol";
import "../../interfaces/IOutcomeReporter.sol";
import "../../interfaces/permissions/ISuperAdminRole.sol";
import "../../interfaces/trading/ITokenTransferProxy.sol";
import "../../interfaces/trading/IFills.sol";
import "../Initializable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";


/// @title BaseFillOrder
/// @notice Manages the core internal functionality to fill orders and check their validity.
contract BaseFillOrder is Initializable {
    using LibOrder for LibOrder.Order;
    using SafeMath for uint256;

    ITokenTransferProxy internal proxy;
    IFills internal fills;
    IEscrow internal escrow;
    ISuperAdminRole internal superAdminRole;
    IOutcomeReporter internal outcomeReporter;

    event OrderFill(
        address indexed maker,
        bytes32 indexed marketHash,
        address indexed taker,
        uint256 newFilledAmount,
        bytes32 orderHash,
        bytes32 fillHash,
        LibOrder.Order order,
        LibOrderAmounts.OrderAmounts orderAmounts
    );

    constructor(ISuperAdminRole _superAdminRole) public Initializable() {
        superAdminRole = _superAdminRole;
    }

    /// @notice Initializes this contract with reference to other contracts.
    /// @param _fills The Fills contract.
    /// @param _escrow  The Escrow contract.
    /// @param _tokenTransferProxy The TokenTransferProxy contract.
    function initialize(
        IFills _fills,
        IEscrow _escrow,
        ITokenTransferProxy _tokenTransferProxy,
        IOutcomeReporter _outcomeReporter
    )
        external
        notInitialized
        onlySuperAdmin(msg.sender)
    {
        fills = _fills;
        escrow = _escrow;
        proxy = _tokenTransferProxy;
        outcomeReporter = _outcomeReporter;
        initialized = true;
    }

    /// @notice Throws if the caller is not a super admin.
    /// @param operator The caller of the method.
    modifier onlySuperAdmin(address operator) {
        require(
            superAdminRole.isSuperAdmin(operator),
            "NOT_A_SUPER_ADMIN"
        );
        _;
    }

    /// @notice Intermediate function to fill a single order
    /// @param order The order to be filled.
    /// @param takerAmount The amount to fill the order by.
    /// @param taker The taker of this order.
    /// @param fillHash The fill hash, if applicable.
    function _fillSingleOrder(
        LibOrder.Order memory order,
        uint256 takerAmount,
        address taker,
        bytes32 fillHash
    )
        internal
    {
        LibOrderAmounts.OrderAmounts memory orderAmounts = LibOrderAmounts.computeOrderAmounts(
            order,
            takerAmount
        );

        updateOrderState(
            order,
            orderAmounts,
            taker,
            fillHash
        );
    }

    /// @notice Intermediate function that settles the order for each maker and taker.
    /// @param order The order that is being filled.
    /// @param orderAmounts The resulting order amounts given the taker amount.
    /// @param taker The taker of this order.
    /// @param fillHash The fill hash, if applicable in the case of a meta fill.
    function updateOrderState(
        LibOrder.Order memory order,
        LibOrderAmounts.OrderAmounts memory orderAmounts,
        address taker,
        bytes32 fillHash
    )
        internal
    {
        uint256 newFillAmount = fills.fill(order, orderAmounts.takerAmount);

        settleOrderForMaker(
            order,
            orderAmounts
        );

        settleOrderForTaker(
            order,
            orderAmounts,
            taker
        );

        emit OrderFill(
            order.maker,
            order.marketHash,
            taker,
            newFillAmount,
            order.getOrderHash(),
            fillHash,
            order,
            orderAmounts
        );
    }

    /// @notice Intermediate function that settles the order for the maker.
    /// @param order The order that is being filled.
    /// @param orderAmounts The resulting order amounts given the taker amount.
    function settleOrderForMaker(
        LibOrder.Order memory order,
        LibOrderAmounts.OrderAmounts memory orderAmounts
    )
        internal
    {
        updateMakerEligibility(
            order,
            orderAmounts
        );

        settleTransfersForMaker(
            order,
            orderAmounts
        );
    }

    /// @notice Intermediate function that settles the order for the taker.
    /// @param order The order that is being filled.
    /// @param orderAmounts The resulting order amounts given the taker amount.
    /// @param taker The taker for this order.
    function settleOrderForTaker(
        LibOrder.Order memory order,
        LibOrderAmounts.OrderAmounts memory orderAmounts,
        address taker
    )
        internal
    {
        updateTakerEligibility(
            order,
            orderAmounts,
            taker
        );

        settleTransfersForTaker(
            order,
            orderAmounts,
            taker
        );
    }

    /// @notice Checks that the order is valid given the taker and taker amount.
    /// @param order The order to check.
    /// @param takerAmount The amount the order will be filled by.
    /// @param taker The taker who would fill this order.
    /// @param makerSig The maker signature for this order.
    function assertOrderValid(
        LibOrder.Order memory order,
        uint256 takerAmount,
        address taker,
        bytes memory makerSig
    )
        internal
        view
    {
        require(
            takerAmount > 0,
            "TAKER_AMOUNT_NOT_POSITIVE"
        );
        order.assertValidAsTaker(taker, makerSig);
        require(
            outcomeReporter.getReportTime(order.marketHash) == 0,
            "MARKET_NOT_TRADEABLE"
        );
        require(
            fills.orderHasSpace(order, takerAmount),
            "INSUFFICIENT_SPACE"
        );
    }

    /// @notice Transfers a token using TokenTransferProxy transferFrom function.
    /// @param token Address of token to transferFrom.
    /// @param from Address transfering token.
    /// @param to Address receiving token.
    /// @param value Amount of token to transfer.
    /// @return Success of token transfer.
    function transferViaProxy(
        address token,
        address from,
        address to,
        uint256 value
    )
        internal
        returns (bool)
    {
        return proxy.transferFrom(token, from, to, value);
    }

    /// @notice Updates the taker's eligibility for if they win the bet or tie.
    /// @param order The order that is being filled.
    /// @param orderAmounts The order amounts for this order.
    /// @param taker The taker of this order.
    function updateTakerEligibility(
        LibOrder.Order memory order,
        LibOrderAmounts.OrderAmounts memory orderAmounts,
        address taker
    )
        private
    {
        if (order.isMakerBettingOutcomeOne) {
            escrow.increaseReturnAmount(
                order.marketHash,
                order.baseToken,
                taker,
                LibOutcome.Outcome.OUTCOME_TWO,
                orderAmounts.potSize
            );
            escrow.updateStakedAmount(
                order.marketHash,
                order.baseToken,
                taker,
                LibOutcome.Outcome.OUTCOME_TWO,
                orderAmounts.takerEscrow
            );
        } else {
            escrow.increaseReturnAmount(
                order.marketHash,
                order.baseToken,
                taker,
                LibOutcome.Outcome.OUTCOME_ONE,
                orderAmounts.potSize
            );
            escrow.updateStakedAmount(
                order.marketHash,
                order.baseToken,
                taker,
                LibOutcome.Outcome.OUTCOME_ONE,
                orderAmounts.takerEscrow
            );
        }
    }

    /// @notice Updates the maker's eligibility for if they win the bet or tie.
    /// @param order The order that is being filled.
    /// @param orderAmounts The order amounts for this order.
    function updateMakerEligibility(
        LibOrder.Order memory order,
        LibOrderAmounts.OrderAmounts memory orderAmounts
    )
        private
    {
        if (order.isMakerBettingOutcomeOne) {
            escrow.increaseReturnAmount(
                order.marketHash,
                order.baseToken,
                order.maker,
                LibOutcome.Outcome.OUTCOME_ONE,
                orderAmounts.potSize
            );
            escrow.updateStakedAmount(
                order.marketHash,
                order.baseToken,
                order.maker,
                LibOutcome.Outcome.OUTCOME_ONE,
                orderAmounts.takerAmount
            );
        } else {
            escrow.increaseReturnAmount(
                order.marketHash,
                order.baseToken,
                order.maker,
                LibOutcome.Outcome.OUTCOME_TWO,
                orderAmounts.potSize
            );
            escrow.updateStakedAmount(
                order.marketHash,
                order.baseToken,
                order.maker,
                LibOutcome.Outcome.OUTCOME_TWO,
                orderAmounts.takerAmount
            );
        }
    }

    /// @notice Settles base tokens (not buyer and seller tokens) for the maker.
    /// @param order The order to settle.
    /// @param orderAmounts The resulting order amounts given the taker amount and parameters.
    function settleTransfersForMaker(
        LibOrder.Order memory order,
        LibOrderAmounts.OrderAmounts memory orderAmounts
    )
        private
    {
        require(
            transferViaProxy(
                order.baseToken,
                order.maker,
                address(escrow),
                orderAmounts.takerAmount
            ),
            "CANNOT_TRANSFER_TAKER_ESCROW"
        );
    }

    /// @notice Settles base tokens (not buyer and seller tokens) for the taker.
    /// @param order The order to settle.
    /// @param orderAmounts The resulting order amounts given the taker amount and parameters.
    /// @param taker The taker of this order.
    function settleTransfersForTaker(
        LibOrder.Order memory order,
        LibOrderAmounts.OrderAmounts memory orderAmounts,
        address taker
    )
        private
    {
        require(
            transferViaProxy(
                order.baseToken,
                taker,
                address(escrow),
                orderAmounts.takerEscrow
            ),
            "CANNOT_TRANSFER_TAKER_ESCROW"
        );
    }
}