pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "./BaseFillOrder.sol";
import "../../interfaces/trading/IFillOrder.sol";
import "../../interfaces/trading/IEIP712FillHasher.sol";


/// @title MultiFillOrder
/// @notice Manages the public functionality to fill multiple orders at once
contract FillOrder is IFillOrder, BaseFillOrder {

    IEIP712FillHasher internal eip712FillHasher;

    constructor(ISuperAdminRole _superAdminRole, IEIP712FillHasher _eip712FillHasher) public BaseFillOrder(_superAdminRole) {
        eip712FillHasher = _eip712FillHasher;
    }

    /// @notice Fills a bunch of orders simulatenously.
    /// @param fillDetails The fills to execute.
    /// @param executorSig The signature of the executor on this fill if the executor is set.
    function fillOrders(
        LibOrder.FillDetails memory fillDetails,
        bytes memory executorSig
    )
        public
    {
        address executor = fillDetails.fills.orders[0].executor;
        bytes32 fillHash;

        require(
            fillDetails.fills.orders.length == fillDetails.fills.takerAmounts.length &&
            fillDetails.fills.orders.length == fillDetails.fills.makerSigs.length,
            "INCORRECT_ARRAY_LENGTHS"
        );

        if (executor != address(0)) {
            fillHash = eip712FillHasher.getDetailsHash(fillDetails);

            require(
                fills.getFillHashSubmitted(fillHash) == false,
                "FILL_ALREADY_SUBMITTED"
            );

            require(
                ECDSA.recover(
                    fillHash,
                    executorSig
                ) == executor,
                "EXECUTOR_SIGNATURE_MISMATCH"
            );

            if (fillDetails.fills.orders.length > 1) {
                for (uint256 i = 1; i < fillDetails.fills.orders.length; i++) {
                    require(
                        fillDetails.fills.orders[i].executor == executor,
                        "INCONSISTENT_EXECUTORS"
                    );
                }
            }

            fills.setFillHashSubmitted(fillHash);
        }

        _fillOrders(
            fillDetails.fills.orders,
            fillDetails.fills.takerAmounts,
            fillDetails.fills.makerSigs,
            msg.sender,
            fillHash
        );

    }

    /// @notice Fills a bunch of orders simulatenously in meta fashion
    /// @param fillDetails The details of the fill
    /// @param taker The taker for this fill.
    /// @param takerSig The signature of the taker for this fill.
    /// @param executorSig The signature of the executor on this order if the executor is set.
    function metaFillOrders(
        LibOrder.FillDetails memory fillDetails,
        address taker,
        bytes memory takerSig,
        bytes memory executorSig
    )
        public
    {
        bytes32 fillHash = eip712FillHasher.getDetailsHash(fillDetails);

        require(
            ECDSA.recover(
                fillHash,
                takerSig
            ) == taker,
            "TAKER_SIGNATURE_MISMATCH"
        );

        require(
            fills.getFillHashSubmitted(fillHash) == false,
            "FILL_ALREADY_SUBMITTED"
        );

        address executor = fillDetails.fills.orders[0].executor;

        if (executor != address(0)) {
            require(
                msg.sender == executor,
                "SENDER_MUST_BE_EXECUTOR"
            );
            require(
                ECDSA.recover(
                    fillHash,
                    executorSig
                ) == executor,
                "EXECUTOR_SIGNATURE_MISMATCH"
            );
        }

        require(
            fillDetails.fills.orders.length == fillDetails.fills.takerAmounts.length &&
            fillDetails.fills.orders.length == fillDetails.fills.makerSigs.length,
            "INCORRECT_ARRAY_LENGTHS"
        );

        if (fillDetails.fills.orders.length > 1) {
            for (uint256 i = 1; i < fillDetails.fills.orders.length; i++) {
                require(
                    fillDetails.fills.orders[i].executor == executor,
                    "INCONSISTENT_EXECUTORS"
                );
            }
        }

        _fillOrders(
            fillDetails.fills.orders,
            fillDetails.fills.takerAmounts,
            fillDetails.fills.makerSigs,
            taker,
            fillHash
        );

        fills.setFillHashSubmitted(fillHash);
    }

    /// @notice Internal method to fill multiple orders.
    ///         Checks if the fill can be optimized for the taker (i.e., transfers can be combined).
    /// @param makerOrders The orders to fill.
    /// @param takerAmounts The amount to fill for each order.
    /// @param makerSigs The maker signatures for each order.
    /// @param taker The taker of these orders.
    /// @param fillHash The fill hash, if applicable in the case of a meta fill.
    function _fillOrders(
        LibOrder.Order[] memory makerOrders,
        uint256[] memory takerAmounts,
        bytes[] memory makerSigs,
        address taker,
        bytes32 fillHash
    )
        private
    {
        bool areOrdersSimilar = areOrdersValidAndSimilar(
            makerOrders,
            takerAmounts,
            makerSigs,
            taker
        );
        // If we get here they are valid so no need to check again

        if (areOrdersSimilar) {
            _fillSimilarOrders(
                makerOrders,
                takerAmounts,
                taker,
                fillHash
            );
        } else {
            for (uint256 i = 0; i < makerOrders.length; i++) {
                _fillSingleOrder(
                    makerOrders[i],
                    takerAmounts[i],
                    taker,
                    fillHash
                );
            }
        }
    }

    /// @notice Internal method to fill multiple similar orders
    ///         Here, the taker transfers are batched to save gas.
    /// @param makerOrders The orders to fill.
    /// @param takerAmounts The amount to fill for each order.
    /// @param taker The taker of these orders.
    /// @param fillHash The fill hash, if applicable in the case of a meta fill.
    function _fillSimilarOrders(
        LibOrder.Order[] memory makerOrders,
        uint256[] memory takerAmounts,
        address taker,
        bytes32 fillHash
    )
        private
    {
        LibOrderAmounts.OrderAmounts memory totalOrderAmounts = LibOrderAmounts.computeTotalOrderAmounts(
            makerOrders,
            takerAmounts
        );

        settleOrderForTaker(
            makerOrders[0],
            totalOrderAmounts,
            taker
        );

        settleOrdersForMaker(
            makerOrders,
            takerAmounts,
            taker,
            fillHash
        );
    }

    /// @notice Checks if orders are valid and similar.
    ///         If they are, then we can optimize the fill
    /// @param makerOrders The orders to fill.
    /// @param takerAmounts The amount to fill for each order.
    /// @param makerSigs The maker signatures for each order.
    /// @param taker The taker of these orders.
    function areOrdersValidAndSimilar(
        LibOrder.Order[] memory makerOrders,
        uint256[] memory takerAmounts,
        bytes[] memory makerSigs,
        address taker
    )
        private
        view
        returns (bool)
    {
        bool isMakerBettingOutcomeOne = makerOrders[0].isMakerBettingOutcomeOne;
        bytes32 marketHash = makerOrders[0].marketHash;
        address baseToken = makerOrders[0].baseToken;

        for (uint256 i = 0; i < makerOrders.length; i++) {
            assertOrderValid(
                makerOrders[i],
                takerAmounts[i],
                taker,
                makerSigs[i]
            );
        }

        if (makerOrders.length > 1) {
            for (uint256 i = 1; i < makerOrders.length; i++) {
                if (makerOrders[i].isMakerBettingOutcomeOne != isMakerBettingOutcomeOne ||
                    makerOrders[i].marketHash != marketHash ||
                    makerOrders[i].baseToken != baseToken
                ) {
                    return false;
                }
            }
        }
        return true;
    }

    /// @notice Settles multiple orders for the maker at once.
    /// @param makerOrders The orders to fill.
    /// @param takerAmounts The amount to fill for each order.
    /// @param taker The taker of these orders.
    /// @param fillHash The fill hash, if applicable in the case of a meta fill.
    function settleOrdersForMaker(
        LibOrder.Order[] memory makerOrders,
        uint256[] memory takerAmounts,
        address taker,
        bytes32 fillHash
    )
        private
    {
        for (uint256 i = 0; i < makerOrders.length; i++) {
            LibOrderAmounts.OrderAmounts memory orderAmounts = LibOrderAmounts.computeOrderAmounts(
                makerOrders[i],
                takerAmounts[i]
            );

            uint256 newFillAmount = fills.fill(makerOrders[i], orderAmounts.takerAmount);

            settleOrderForMaker(
                makerOrders[i],
                orderAmounts
            );

            emit OrderFill(
                makerOrders[i].maker,
                makerOrders[i].marketHash,
                taker,
                newFillAmount,
                makerOrders[i].getOrderHash(),
                fillHash,
                makerOrders[i],
                orderAmounts
            );
        }
    }
}