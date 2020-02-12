pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "./LibOrder.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";


/// @title LibOrderAmounts
/// @notice Struct definition for the resulting individual computed amounts
///         when filling an order.
library LibOrderAmounts {
    using SafeMath for uint256;

    struct OrderAmounts {
        uint256 takerAmount;
        uint256 takerEscrow;
        uint256 potSize;
    }

    /// @notice Computes the tokens that should be transferred as a result of
    ///         the order and the specified fill amount.
    /// @param order The reference maker order
    /// @param takerAmount The amount to fill of this order.
    /// @return An OrderAmounts struct.
    function computeOrderAmounts(
        LibOrder.Order memory order,
        uint256 takerAmount
    )
        internal
        pure
        returns (LibOrderAmounts.OrderAmounts memory)
    {
        uint256 oddsPrecision = LibOrder.getOddsPrecision();
        uint256 potSize = takerAmount.mul(oddsPrecision).div(order.percentageOdds);
        uint256 takerEscrow = potSize.sub(takerAmount);

        return LibOrderAmounts.OrderAmounts({
            takerAmount: takerAmount,
            takerEscrow: takerEscrow,
            potSize: potSize
        });
    }

    /// @notice Combines two OrderAmounts into one by adding up
    ///         the values
    /// @param orderAmount1 The first OrderAmount
    /// @param orderAmount2 The second OrderAmount
    /// @return The combined OrderAmounts struct.
    function reduceOrderAmounts(
        LibOrderAmounts.OrderAmounts memory orderAmount1,
        LibOrderAmounts.OrderAmounts memory orderAmount2
    )
        internal
        pure
        returns (LibOrderAmounts.OrderAmounts memory)
    {
        return LibOrderAmounts.OrderAmounts({
            takerAmount: orderAmount1.takerAmount.add(orderAmount2.takerAmount),
            takerEscrow: orderAmount1.takerEscrow.add(orderAmount2.takerEscrow),
            potSize: orderAmount1.potSize.add(orderAmount2.potSize)
        });
    }

    /// @notice Takes a bunch of orders and taker amounts
    ///         and computes the total order amounts
    /// @param makerOrders The reference maker orders
    /// @param takerAmounts An array of taker amounts, one for each order
    /// @return The total OrderAmounts struct.
    function computeTotalOrderAmounts(
        LibOrder.Order[] memory makerOrders,
        uint256[] memory takerAmounts
    )
        internal
        pure
        returns (LibOrderAmounts.OrderAmounts memory)
    {
        LibOrderAmounts.OrderAmounts memory combinedOrderAmounts;
        uint256 makerOrdersLength = makerOrders.length;
        for (uint256 i = 0; i < makerOrdersLength; i++) {
            LibOrderAmounts.OrderAmounts memory orderAmounts = computeOrderAmounts(
                makerOrders[i],
                takerAmounts[i]
            );
            combinedOrderAmounts = reduceOrderAmounts(combinedOrderAmounts, orderAmounts);
        }
        return combinedOrderAmounts;
    }
}