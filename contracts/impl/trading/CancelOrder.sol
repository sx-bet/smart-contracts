pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "../../libraries/LibOrder.sol";
import "../../interfaces/permissions/ISuperAdminRole.sol";
import "../../interfaces/trading/IFills.sol";
import "../../interfaces/trading/ICancelOrder.sol";
import "../Initializable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";


/// @title CancelOrder
/// @notice Manages functionality to cancel orders
contract CancelOrder is ICancelOrder, Initializable {
    using LibOrder for LibOrder.Order;
    using SafeMath for uint256;

    ISuperAdminRole private superAdminRole;
    IFills private fills;

    event OrderCancel(
        address indexed maker,
        bytes32 orderHash,
        LibOrder.Order order
    );

    constructor(ISuperAdminRole _superAdminRole) public Initializable() {
        superAdminRole = _superAdminRole;
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

    /// @notice Initializes this contract with reference to other contracts
    ///         in the protocol.
    /// @param _fills The Fills contract.
    function initialize(IFills _fills)
        external
        notInitialized
        onlySuperAdmin(msg.sender)
    {
        fills = _fills;
        initialized = true;
    }

    /// @notice Cancels an order and prevents and further filling.
    ///         Uses the order hash to uniquely ID the order.
    /// @param order The order to cancel.
    function cancelOrder(LibOrder.Order memory order) public {
        assertCancelValid(order, msg.sender);
        fills.cancel(order);

        emit OrderCancel(
            order.maker,
            order.getOrderHash(),
            order
        );
    }

    /// @notice Cancels multiple orders and prevents further filling.
    /// @param makerOrders The orders to cancel.
    function batchCancelOrders(LibOrder.Order[] memory makerOrders) public {
        uint256 makerOrdersLength = makerOrders.length;
        for (uint256 i = 0; i < makerOrdersLength; i++) {
            cancelOrder(makerOrders[i]);
        }
    }

    /// @notice Checks if a cancel is valid by the canceller.
    /// @param order The order to cancel.
    /// @param canceller The canceller that must be the maker.
    function assertCancelValid(
        LibOrder.Order memory order,
        address canceller
    )
        private
        view
    {
        require(
            order.executor == address(0),
            "EXECUTOR_CANNOT_BE_SET"
        );
        order.assertValidAsMaker(canceller);
        require(
            fills.remainingSpace(order) > 0,
            "INSUFFICIENT_SPACE"
        );
    }
}
