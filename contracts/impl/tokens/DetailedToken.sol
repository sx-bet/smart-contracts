pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;


/// @title DetailedToken
/// @notice A utility contract to help pull name, symbol and decimals
///         from ERC20 tokens.
///         Verbatim, this:
///         https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/token/ERC20/ERC20Detailed.sol
contract DetailedToken {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor (string memory name, string memory symbol, uint8 decimals) public {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
    }

    /// @notice Gets the name of the token.
    /// @return The name of the token.
    function name() public view returns (string memory) {
        return _name;
    }

    /// @notice Gets the symbol of the token.
    /// @return The symbol of the token.
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /// @notice Gets the decimals of the token.
    /// @return The decimals of the token.
    function decimals() public view returns (uint8) {
        return _decimals;
    }
}