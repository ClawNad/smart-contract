// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILens} from "../../src/interfaces/INadFun.sol";

/// @notice Minimal mock of nad.fun's Lens contract for testing.
contract MockLens is ILens {
    mapping(address => uint256) public progressOverride;
    mapping(address => bool) public graduatedOverride;

    function setProgress(address token, uint256 progress) external {
        progressOverride[token] = progress;
    }

    function setGraduated(address token, bool graduated) external {
        graduatedOverride[token] = graduated;
    }

    function getAmountOut(address, uint256 amountIn, bool) external pure override returns (address, uint256) {
        return (address(0), amountIn);
    }

    function getAmountIn(address, uint256 amountOut, bool) external pure override returns (address, uint256) {
        return (address(0), amountOut);
    }

    function isGraduated(address token) external view override returns (bool) {
        return graduatedOverride[token];
    }

    function isLocked(address) external pure override returns (bool) {
        return false;
    }

    function getProgress(address token) external view override returns (uint256) {
        return progressOverride[token];
    }

    function availableBuyTokens(address) external pure override returns (uint256, uint256) {
        return (800_000_000 ether, 100 ether);
    }

    function getInitialBuyAmountOut(uint256) external pure override returns (uint256) {
        return 0;
    }
}
