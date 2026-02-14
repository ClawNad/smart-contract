// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IBondingCurveRouter, TokenCreationParams, BuyParams, SellParams} from "../../src/interfaces/INadFun.sol";

/// @notice A simple ERC-20 token created by the mock router.
contract MockAgentToken is ERC20 {
    constructor(string memory name_, string memory symbol_, address mintTo, uint256 initialBuy)
        ERC20(name_, symbol_)
    {
        // Mint total supply of 1 billion to the pool (mock)
        _mint(address(this), 1_000_000_000 ether);

        // If there's an initial buy, send tokens to the buyer
        if (initialBuy > 0 && mintTo != address(0)) {
            _transfer(address(this), mintTo, initialBuy);
        }
    }
}

/// @notice Minimal mock of nad.fun's BondingCurveRouter for testing.
contract MockBondingCurveRouter is IBondingCurveRouter {
    uint256 public constant DEPLOY_FEE = 10 ether; // 10 MON

    uint256 private _tokenCount;

    event TokenCreated(address indexed token, address indexed creator, string name, string symbol);

    function create(TokenCreationParams calldata params)
        external
        payable
        override
        returns (address token, address pool)
    {
        require(msg.value >= DEPLOY_FEE, "Insufficient deploy fee");

        // Create a new mock token
        MockAgentToken newToken = new MockAgentToken(params.name, params.symbol, msg.sender, params.amountOut);
        token = address(newToken);
        pool = address(uint160(uint256(keccak256(abi.encodePacked(token, block.timestamp)))));

        _tokenCount++;

        // Refund excess MON
        uint256 excess = msg.value - DEPLOY_FEE;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "Refund failed");
        }

        emit TokenCreated(token, msg.sender, params.name, params.symbol);
    }

    function buy(BuyParams calldata) external payable override returns (uint256) {
        return 0;
    }

    function sell(SellParams calldata) external pure override returns (uint256) {
        return 0;
    }

    function tokenCount() external view returns (uint256) {
        return _tokenCount;
    }
}
