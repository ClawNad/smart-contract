// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Parameters for creating a new token on nad.fun's bonding curve.
struct TokenCreationParams {
    string name;
    string symbol;
    string tokenURI;
    uint256 amountOut; // Number of tokens to buy in initial purchase (0 for none).
    bytes32 salt; // Salt for deterministic CREATE2 address.
    uint8 actionId; // Unique action identifier (uint8 per nad.fun ABI).
}

/// @notice Parameters for buying tokens on the bonding curve.
struct BuyParams {
    address token;
    uint256 minAmountOut;
    address to;
}

/// @notice Parameters for selling tokens on the bonding curve.
struct SellParams {
    address token;
    uint256 amountIn;
    uint256 minAmountOut;
    address to;
}

/// @title IBondingCurveRouter
/// @notice Interface for nad.fun's bonding curve router (pre-graduation trades + token creation).
/// @dev Monad mainnet: 0x6F6B8F1a20703309951a5127c45B49b1CD981A22
interface IBondingCurveRouter {
    /// @notice Deploy a new token on the bonding curve.
    /// @dev Requires 10 MON deploy fee sent as msg.value (plus additional MON if amountOut > 0).
    /// @return token The created ERC-20 token address.
    /// @return pool  The bonding curve pool address.
    function create(TokenCreationParams calldata params) external payable returns (address token, address pool);

    /// @notice Buy tokens on the bonding curve.
    /// @return amountOut Number of tokens received.
    function buy(BuyParams calldata params) external payable returns (uint256 amountOut);

    /// @notice Sell tokens on the bonding curve.
    function sell(SellParams calldata params) external returns (uint256 amountOut);
}

/// @title ILens
/// @notice Read-only helper for querying nad.fun bonding curve state.
/// @dev Monad mainnet: 0x7e78A8DE94f21804F7a17F4E8BF9EC2c872187ea
interface ILens {
    /// @notice Calculate output amount for a given input.
    /// @param token   The token address.
    /// @param amountIn Input amount.
    /// @param isBuy   True for buy, false for sell.
    /// @return router   The correct router to use (bonding curve or DEX).
    /// @return amountOut Expected output amount.
    function getAmountOut(
        address token,
        uint256 amountIn,
        bool isBuy
    ) external view returns (address router, uint256 amountOut);

    /// @notice Calculate required input for a desired output.
    function getAmountIn(
        address token,
        uint256 amountOut,
        bool isBuy
    ) external view returns (address router, uint256 amountIn);

    /// @notice Check if a token has graduated from bonding curve to DEX.
    function isGraduated(address token) external view returns (bool);

    /// @notice Check if a token's LP is locked.
    function isLocked(address token) external view returns (bool);

    /// @notice Get bonding curve fill progress (0 to 1e18).
    function getProgress(address token) external view returns (uint256);

    /// @notice Get the remaining buyable tokens and required MON.
    function availableBuyTokens(address token) external view returns (uint256 availableAmount, uint256 requiredMon);

    /// @notice Calculate initial buy output for a given MON input (before token exists).
    function getInitialBuyAmountOut(uint256 amountIn) external view returns (uint256);
}
