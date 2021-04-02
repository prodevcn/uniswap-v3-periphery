// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

import '../interfaces/IPeripheryPayments.sol';
import '../interfaces/external/IWETH9.sol';

import '../libraries/TransferHelper.sol';

import './PeripheryImmutableState.sol';

abstract contract PeripheryPayments is IPeripheryPayments, PeripheryImmutableState {
    using SafeMath for uint256;

    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    /// @inheritdoc IPeripheryPayments
    function unwrapWETH9(
        uint256 amountMinimum, 
        address recipient
    ) external payable override {
        unwrapWETH9WithFee(amountMinimum, recipient, 0, address(0));
    }

    /// @inheritdoc IPeripheryPayments
    function unwrapWETH9WithFee(
        uint256 amountMinimum, 
        address recipient,
        uint256 feePercentage,
        address feeRecipient
    ) public payable override {
        require(feePercentage <= 10, 'Fee');

        uint256 balanceWETH9 = IWETH9(WETH9).balanceOf(address(this));
        if (amountMinimum > 0) require(balanceWETH9 >= amountMinimum, 'Insufficient WETH9');

        if (balanceWETH9 > 0) {
            IWETH9(WETH9).withdraw(balanceWETH9);
            uint256 feeAmount = feePercentage == 0 ? 0 : balanceWETH9.mul(feePercentage).div(100);
            if (feeAmount > 0) TransferHelper.safeTransferETH(feeRecipient, feeAmount);
            TransferHelper.safeTransferETH(recipient, balanceWETH9 - feeAmount);
        }
    }

    /// @inheritdoc IPeripheryPayments
    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable override {
        sweepTokenWithFee(token, amountMinimum, recipient, 0, address(0));
    }

    /// @inheritdoc IPeripheryPayments
    function sweepTokenWithFee(
        address token,
        uint256 amountMinimum,
        address recipient,
        uint256 feePercentage,
        address feeRecipient
    ) public payable override {
        require(feePercentage <= 10, 'Fee');

        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        if (amountMinimum > 0) require(balanceToken >= amountMinimum, 'Insufficient token');

        if (balanceToken > 0) {
            uint256 feeAmount = feePercentage == 0 ? 0 : balanceToken.mul(feePercentage).div(100);
            if (feeAmount > 0) TransferHelper.safeTransfer(token, feeRecipient, feeAmount);
            TransferHelper.safeTransfer(token, recipient, balanceToken - feeAmount);
        }
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        uint256 selfBalance;
        if (token == WETH9 && (selfBalance = address(this).balance) >= value) {
            // pay with WETH9 generated from ETH
            IWETH9(WETH9).deposit{value: selfBalance}(); // wrap whole balance
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
