pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;


/// @title LibString
/// @notice Utility to efficiently compare strings when necessary.
library LibString {

    /// @notice Compares two strings by taking their hash.
    /// @param a The first string.
    /// @param b The second string.
    /// @return true or false depending on if the strings matched.
    function equals(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}