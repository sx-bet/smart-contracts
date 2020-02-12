pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";


/// @title LibOrder
/// @notice Central definition for what an "order" is along with utilities for an order.
library LibOrder {
    using SafeMath for uint256;

    uint256 public constant ODDS_PRECISION = 10**20;

    struct Order {
        bytes32 marketHash;
        address baseToken;
        uint256 totalBetSize;
        uint256 percentageOdds;
        uint256 expiry;
        uint256 salt;
        address maker;
        address executor;
        bool isMakerBettingOutcomeOne;
    }

    struct FillObject {
        Order[] orders;
        bytes[] makerSigs;
        uint256[] takerAmounts;
        uint256 fillSalt;
    }

    struct FillDetails {
        string action;
        string market;
        string betting;
        string stake;
        string odds;
        string returning;
        FillObject fills;
    }

    /// @notice Checks the parameters of the given order to see if it conforms to the protocol.
    /// @param order The order to check.
    /// @return A status string in UPPER_SNAKE_CASE. It will return "OK" if everything checks out.
    // solhint-disable code-complexity
    function getParamValidity(Order memory order)
        internal
        view
        returns (string memory)
    {
        if (order.totalBetSize == 0) {return "TOTAL_BET_SIZE_ZERO";}
        if (order.percentageOdds == 0 || order.percentageOdds >= ODDS_PRECISION) {return "INVALID_PERCENTAGE_ODDS";}
        if (order.expiry < now) {return "ORDER_EXPIRED";}
        if (order.baseToken == address(0)) {return "BASE_TOKEN";}
        return "OK";
    }

    /// @notice Checks the signature of an order to see if
    ///         it was an order signed by the given maker.
    /// @param order The order to check.
    /// @param makerSig The signature to compare.
    /// @return true if the signature matches, false otherwise.
    function checkSignature(Order memory order, bytes memory makerSig)
        internal
        pure
        returns (bool)
    {
        bytes32 orderHash = getOrderHash(order);
        return ECDSA.recover(ECDSA.toEthSignedMessageHash(orderHash), makerSig) == order.maker;
    }

    /// @notice Checks if an order's parameters conforms to the protocol's specifications.
    /// @param order The order to check.
    function assertValidParams(Order memory order) internal view {
        require(
            order.totalBetSize > 0,
            "TOTAL_BET_SIZE_ZERO"
        );
        require(
            order.percentageOdds > 0 && order.percentageOdds < ODDS_PRECISION,
            "INVALID_PERCENTAGE_ODDS"
        );
        require(order.baseToken != address(0), "INVALID_BASE_TOKEN");
        require(order.expiry > now, "ORDER_EXPIRED");
    }

    /// @notice Checks if an order has valid parameters including
    ///         the signature and checks if the maker is not the taker.
    /// @param order The order to check.
    /// @param taker The hypothetical filler of this order, i.e., the taker.
    /// @param makerSig The signature to check.
    function assertValidAsTaker(Order memory order, address taker, bytes memory makerSig) internal view {
        assertValidParams(order);
        require(
            checkSignature(order, makerSig),
            "SIGNATURE_MISMATCH"
        );
        require(order.maker != taker, "TAKER_NOT_MAKER");
    }

    /// @notice Checks if the order has valid parameters
    ///         and checks if the sender is the maker.
    /// @param order The order to check.
    /// @param sender The address to compare the maker to.
    function assertValidAsMaker(Order memory order, address sender) internal view {
        assertValidParams(order);
        require(order.maker == sender, "CALLER_NOT_MAKER");
    }

    /// @notice Computes the hash of an order. Packs the arguments in order
    ///         of the Order struct.
    /// @param order The order to compute the hash of.
    function getOrderHash(Order memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                order.marketHash,
                order.baseToken,
                order.totalBetSize,
                order.percentageOdds,
                order.expiry,
                order.salt,
                order.maker,
                order.executor,
                order.isMakerBettingOutcomeOne
            )
        );
    }

    function getOddsPrecision() internal pure returns (uint256) {
        return ODDS_PRECISION;
    }
}