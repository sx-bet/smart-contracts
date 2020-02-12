pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;


import "../../libraries/LibOrderAmounts.sol";
import "../../libraries/LibString.sol";
import "../../libraries/LibOrder.sol";
import "../../interfaces/trading/IFeeSchedule.sol";
import "../../interfaces/trading/IFills.sol";
import "../../interfaces/trading/ITokenTransferProxy.sol";
import "../../interfaces/trading/IReadOnlyValidator.sol";
import "../../interfaces/IOutcomeReporter.sol";
import "../../interfaces/trading/IEIP712FillHasher.sol";
import "../../interfaces/extensions/IOrderValidator.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


/// @title OrderValidator
/// @notice Functions to validate orders off-chain and
///         return a user-friendly string.
///         None of these are used in the actual protocol to determine
///         any state changes.
contract OrderValidator is IOrderValidator {
    using LibOrder for LibOrder.Order;
    using LibString for string;
    using SafeMath for uint256;

    ITokenTransferProxy private proxy;
    IFills private fills;
    IFeeSchedule private feeSchedule;
    IEIP712FillHasher private eip712FillHasher;
    IOutcomeReporter private outcomeReporter;

    constructor(
        ITokenTransferProxy _proxy,
        IFills _fills,
        IFeeSchedule _feeSchedule,
        IEIP712FillHasher _eip712FillHasher,
        IOutcomeReporter _outcomeReporter
    ) public {
        proxy = _proxy;
        fills = _fills;
        feeSchedule = _feeSchedule;
        eip712FillHasher = _eip712FillHasher;
        outcomeReporter = _outcomeReporter;
    }

    /// @notice Gets the current status of an order without considering
    ///         any individual taker.
    /// @param order The order to examine.
    /// @param makerSig The signature of maker on this order.
    /// @return A string representing the status. "OK" for valid.
    function getOrderStatus(
        LibOrder.Order memory order,
        bytes memory makerSig
    )
        public
        view
        returns (string memory)
    {
        string memory baseMakerOrderStatus = getBaseOrderStatus(
            order,
            makerSig
        );
        if (!baseMakerOrderStatus.equals("OK")) {return baseMakerOrderStatus;}
        uint256 remainingSpace = fills.remainingSpace(order);
        if (remainingSpace == 0) {
            return "FULLY_FILLED";
        }
        LibOrderAmounts.OrderAmounts memory orderAmounts = LibOrderAmounts.computeOrderAmounts(
            order,
            remainingSpace
        );
        string memory allowanceBalanceValidity = getMakerAllowanceAndBalanceStatus(
            orderAmounts,
            order.baseToken,
            order.maker
        );
        return allowanceBalanceValidity;
    }

    /// @notice Gets the current status of multiple orders without considering
    ///         any individual taker.
    /// @param orders The orders to examine.
    /// @param makerSigs The signature of the makers on this order.
    /// @return A string representing the status. "OK" for valid.
    function getMultiOrderStatus(
        LibOrder.Order[] memory orders,
        bytes[] memory makerSigs
    )
        public
        view
        returns (string[] memory)
    {
        string[] memory statuses = new string[](orders.length);

        for (uint256 i = 0; i < orders.length; i++) {
            statuses[i] = getOrderStatus(
                orders[i],
                makerSigs[i]
            );
        }

        return statuses;
    }

    /// @notice Gets the status of a multi-order fill
    /// @param fillDetails The fills to execute
    /// @param executorSig The signature of the executor, if any.
    /// @param taker The hypothetical taker.
    /// @return A string representing the status. "OK" for valid.
    function getFillStatus(
        LibOrder.FillDetails memory fillDetails,
        bytes memory executorSig,
        address taker
    )
        public
        view
        returns (string memory)
    {
        address executor = fillDetails.fills.orders[0].executor;
        if (executor != address(0)) {
            bytes32 fillHash = eip712FillHasher.getDetailsHash(fillDetails);

            if (fills.getFillHashSubmitted(fillHash)) {
                return "FILL_ALREADY_SUBMITTED";
            }

            if (ECDSA.recover(fillHash, executorSig) != executor) {
                return "EXECUTOR_SIGNATURE_MISMATCH";
            }
        }

        if (fillDetails.fills.orders.length > 1) {
            for (uint256 i = 1; i < fillDetails.fills.orders.length; i++) {
                if (fillDetails.fills.orders[i].executor != executor) {
                    return "INCONSISTENT_EXECUTORS";
                }
            }
        }

        return _getFillStatus(
            fillDetails.fills.orders,
            taker,
            fillDetails.fills.takerAmounts,
            fillDetails.fills.makerSigs
        );
    }

    /// @notice Gets the status of a meta multi-order fill
    /// @param fillDetails The fills to execute, meta style.
    /// @param taker The hypothetical taker.
    /// @param takerSig The taker's signature for this fill.
    /// @param executorSig The signature of the executor, if any.
    /// @return A string representing the status. "OK" for valid.
    function getMetaFillStatus(
        LibOrder.FillDetails memory fillDetails,
        address taker,
        bytes memory takerSig,
        bytes memory executorSig
    )
        public
        view
        returns (string memory)
    {
        bytes32 fillHash = eip712FillHasher.getDetailsHash(fillDetails);

        if (ECDSA.recover(fillHash, takerSig) != taker) {
            return "TAKER_SIGNATURE_MISMATCH";
        }

        if (fills.getFillHashSubmitted(fillHash)) {
            return "FILL_ALREADY_SUBMITTED";
        }

        address executor = fillDetails.fills.orders[0].executor;

        if (executor != address(0) &&
            ECDSA.recover(fillHash, executorSig) != executor) {
            return "EXECUTOR_SIGNATURE_MISMATCH";
        }

        if (fillDetails.fills.orders.length > 1) {
            for (uint256 i = 1; i < fillDetails.fills.orders.length; i++) {
                if (fillDetails.fills.orders[i].executor != executor) {
                    return "INCONSISTENT_EXECUTORS";
                }
            }
        }

        return _getFillStatus(
            fillDetails.fills.orders,
            taker,
            fillDetails.fills.takerAmounts,
            fillDetails.fills.makerSigs
        );
    }

    /// @notice Gets the combined status of several orders considering
    ///         a single taker and a taker amount for each order.
    /// @param makerOrders The orders to fill.
    /// @param taker The hypothetical taker.
    /// @param takerAmounts The hypothetical amounts to fill.
    /// @param makerSigs The signatures of the makers on these orders.
    /// @return A string representing the status. "OK" for valid.
    function _getFillStatus(
        LibOrder.Order[] memory makerOrders,
        address taker,
        uint256[] memory takerAmounts,
        bytes[] memory makerSigs
    )
        private
        view
        returns (string memory)
    {
        string memory baseMultiFillStatus = getBaseMultiFillStatus(
            makerOrders,
            taker,
            takerAmounts,
            makerSigs
        );
        if (!baseMultiFillStatus.equals("OK")) {
            return baseMultiFillStatus;
        }
        return getMultiAllowanceBalanceStatus(
            makerOrders,
            takerAmounts,
            taker
        );
    }

    /// @notice Gets the "base" status of an order without considering any token
    ///         allowances and balances.
    /// @param order A maker order.
    /// @param makerSig The signature of the maker on this order.
    /// @return A string representing the status. "OK" for valid.
    function getBaseOrderStatus(
        LibOrder.Order memory order,
        bytes memory makerSig
    )
        private
        view
        returns (string memory)
    {
        string memory paramValidity = order.getParamValidity();
        if (paramValidity.equals("OK") == false) {return paramValidity;}
        if (outcomeReporter.getReportTime(order.marketHash) != 0) {
            return "MARKET_NOT_TRADEABLE";
        }
        if (order.checkSignature(makerSig) == false) {
            return "BAD_SIGNATURE";
        }
        if (fills.isOrderCancelled(order)) {
            return "CANCELLED";
        }
        return "OK";
    }

    /// @notice Checks the maker's balances and allowances for given order amounts
    /// @param orderAmounts The computed balances to transfer as a result of the fill.
    /// @param baseTokenAddress The base token to use.
    /// @param maker The maker's balance to check.
    /// @return A string representing the status. "OK" for valid.
    function getMakerAllowanceAndBalanceStatus(
        LibOrderAmounts.OrderAmounts memory orderAmounts,
        address baseTokenAddress,
        address maker
    )
        private
        view
        returns (string memory)
    {
        IERC20 baseToken = IERC20(baseTokenAddress);
        if (baseToken.balanceOf(maker) < orderAmounts.takerAmount) {
            return "MAKER_INSUFFICIENT_BASE_TOKEN";
        }
        if (baseToken.allowance(maker, address(proxy)) < orderAmounts.takerAmount) {
            return "MAKER_INSUFFICIENT_BASE_TOKEN_ALLOWANCE";
        }
        return "OK";
    }

    /// @notice Gets the status in terms of token balances
    ///         and allowances if several orders were to be filled by a
    ///         single taker.
    ///
    ///         For this method, we can combine the orders and treat it as
    ///         one big order for the taker, but still need to check each
    ///         order individually for makers.
    ///
    ///         Assumes base token is same for every order.
    /// @param makerOrders The hypothetical orders to fill.
    /// @param takerAmounts The hypothetical amounts to fill for each order.
    /// @param taker The taker filling these orders.
    /// @return A string representing the status. "OK" for valid.
    function getMultiAllowanceBalanceStatus(
        LibOrder.Order[] memory makerOrders,
        uint256[] memory takerAmounts,
        address taker
    )
        private
        view
        returns (string memory)
    {
        address baseToken = makerOrders[0].baseToken;

        LibOrderAmounts.OrderAmounts memory totalOrderAmounts = LibOrderAmounts.computeTotalOrderAmounts(
            makerOrders,
            takerAmounts
        );

        for (uint256 i = 0; i < makerOrders.length; i++) {
            LibOrderAmounts.OrderAmounts memory individualOrderAmounts = LibOrderAmounts.computeOrderAmounts(
                makerOrders[i],
                takerAmounts[i]
            );
            string memory makerAllowanceBalanceValidity = getMakerAllowanceAndBalanceStatus(
                individualOrderAmounts,
                baseToken,
                makerOrders[i].maker
            );
            if (!makerAllowanceBalanceValidity.equals("OK")) {
                return makerAllowanceBalanceValidity;
            }
        }
        return getTakerAllowanceAndBalanceStatus(
            totalOrderAmounts,
            baseToken,
            taker
        );
    }

    /// @notice Gets the combined base status of several orders considering
    ///         a single taker and a taker amount for each order.
    ///         Does not consider balances or allowances.
    ///         The markets must be identical in order to combine taker amounts.
    /// @param makerOrders The orders to fill.
    /// @param taker The hypothetical taker.
    /// @param takerAmounts The hypothetical amounts to fill.
    /// @param signatures The signatures of the makers on these orders.
    /// @return A string representing the status. "OK" for valid.
    function getBaseMultiFillStatus(
        LibOrder.Order[] memory makerOrders,
        address taker,
        uint256[] memory takerAmounts,
        bytes[] memory signatures
    )
        private
        view
        returns (string memory)
    {
        for (uint256 i = 0; i < makerOrders.length; i++) {
            if (makerOrders[i].marketHash != makerOrders[0].marketHash) {return "MARKETS_NOT_IDENTICAL";}
            if (makerOrders[i].baseToken != makerOrders[0].baseToken) {return "BASE_TOKENS_NOT_IDENTICAL";}
            // Don't have to compare directions - all that matters is the amount end of the day
            string memory baseMakerOrderStatus = getBaseFillStatus(
                makerOrders[i],
                signatures[i],
                takerAmounts[i],
                taker
            );
            if (!baseMakerOrderStatus.equals("OK")) {return baseMakerOrderStatus;}
        }
        return "OK";
    }

    /// @notice Checks the fillability of an order along with the taker amount.
    ///         Does not check balances.
    /// @param order The order to fill.
    /// @param makerSig The maker's signature.
    /// @param takerAmount The hypothetical taker amount.
    /// @param taker The taker.
    /// @return A string representing the status. "OK" for valid.
    function getBaseFillStatus(
        LibOrder.Order memory order,
        bytes memory makerSig,
        uint256 takerAmount,
        address taker
    )
        private
        view
        returns (string memory)
    {
        if (takerAmount == 0) {return "TAKER_AMOUNT_NOT_POSITIVE";}
        string memory baseMakerOrderStatus = getBaseOrderStatus(
            order,
            makerSig
        );
        if (!baseMakerOrderStatus.equals("OK")) {return baseMakerOrderStatus;}
        if (taker == order.maker) {return "TAKER_NOT_MAKER";}
        if (!fills.orderHasSpace(order, takerAmount)) {return "INSUFFICIENT_SPACE";}
        return "OK";
    }

    /// @notice Checks the taker's balances and allowances for a given order to be filled.
    /// @param orderAmounts The computed balances to transfer as a result of the fill.
    /// @param baseTokenAddress The base token address
    /// @param taker The hypothetical taker.
    /// @return A string representing the status. "OK" for valid.
    function getTakerAllowanceAndBalanceStatus(
        LibOrderAmounts.OrderAmounts memory orderAmounts,
        address baseTokenAddress,
        address taker
    )
        private
        view
        returns (string memory)
    {
        IERC20 baseToken = IERC20(baseTokenAddress);
        if (baseToken.balanceOf(taker) < orderAmounts.takerEscrow) {
            return "TAKER_INSUFFICIENT_BASE_TOKEN";
        }
        if (baseToken.allowance(taker, address(proxy)) < orderAmounts.takerEscrow) {
            return "TAKER_INSUFFICIENT_BASE_TOKEN_ALLOWANCE";
        }
        return "OK";
    }
}
