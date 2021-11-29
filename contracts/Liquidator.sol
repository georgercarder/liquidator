//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Common.sol";
import "./Interfaces.sol";

contract Liquidator is Common {
  
  // hack address(0x00..) for compiler checksum warnings

  address private immutable balancerV2Vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
  address private immutable aaveLendingPool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
  address private immutable swapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

  function IsLendingPool(address suspect) view private returns(bool) {
    address demasked = demask(balancerV2Vault);
    if (suspect == demasked) {return true;}
    demasked = demask(aaveLendingPool); 
    if (suspect == demasked) {return true;}
    return false;
  }

  function Liquidate(
    address borrower,
    address cBorrowed, 
    address swapIntermediate,
    address cCollateral, 
    address beneficiary, 
    uint256 repayAmount,
    FlashLoanProvider flashLoanProvider
  ) external {
    address _comptroller = demask(comptroller);
    uint256 err = ComptrollerInterface(_comptroller).liquidateBorrowAllowed(
      cBorrowed, cCollateral, address(this), borrower, repayAmount); // this is liquidator
    // "fail early" just in case being frontrun etc.
    require(err == 0, "liquidate borrow not allowed.");

    address underlying = ICToken(cBorrowed).underlying();

    bytes memory params = abi.encode(borrower, cBorrowed, swapIntermediate, cCollateral, repayAmount);
    makeFlashLoanLiqAndSwap(underlying, repayAmount, params, flashLoanProvider);
    uint256 balance = IERC20(underlying).balanceOf(address(this));

    require(IERC20(underlying).transfer(beneficiary, balance), "transfer failed");
  }

  function makeFlashLoanLiqAndSwap(
    address asset, 
    uint256 amount, 
    bytes memory params,
    FlashLoanProvider flashLoanProvider
  ) private {
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;
    uint256[] memory modes = new uint256[](1); 
    address _lendingPool;

    if (flashLoanProvider == FlashLoanProvider.BALANCER) {
      _lendingPool = demask(balancerV2Vault);
      IERC20[] memory tokens = new IERC20[](1);
      tokens[0] = IERC20(asset);
      IBalancerV2Vault(_lendingPool).flashLoan(
        IFlashLoanRecipient(address(this)),
        tokens,
        amounts,
        params // userData
      );
    } else if (flashLoanProvider == FlashLoanProvider.AAVE) {
      _lendingPool = demask(aaveLendingPool);
      address[] memory assets = new address[](1);
      assets[0] = asset;
      ILendingPool(_lendingPool).flashLoan(
        address(this), // receiverAddress
        assets,
        amounts,
        modes, // trivial
        address(this), // onBehalfOf, 
        params,
        uint16(0) // referralCode 
      );
    } else {
      revert("fl provider not supported");
    }
    // liq and swap happen in `receiveFlashLoan` or `executeOperation`
  }

  function receiveFlashLoan( // balancer
    address[] calldata tokens, 
    uint256[] calldata amounts, 
    uint256[] calldata feeAmounts, 
    bytes calldata userData
  ) external {
    // this means we have the assets on loan
    useFlashLoan(tokens, amounts, feeAmounts, userData); 
    uint256 amountOwing = amounts[0] + feeAmounts[0];
    require(IERC20(tokens[0]).transfer(msg.sender, amountOwing), "transfer to balancer failed."); // note that balancer needs a transfer
  }

  function executeOperation( // aave
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator, 
    bytes calldata params
  ) external returns(bool) {
    // this means we have the assets on loan
    initiator; // silence compiler

    // pays the lendingPool back
    uint256 amountOwing = amounts[0] + premiums[0];
    IERC20(assets[0]).approve(msg.sender, amountOwing); // optimistically approves

    return useFlashLoan(assets, amounts, premiums, params);
  }

  function useFlashLoan(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    bytes calldata params
  ) private returns(bool) {
    require(IsLendingPool(msg.sender), "only lending pool can call this");
    (address swapIntermediate, address cCollateral) = decodeAndLiquidate(params);
    
    address collateral = ICToken(cCollateral).underlying();
    swap(
      IERC20(collateral).balanceOf(address(this)), // amountIn
      collateral, 
      swapIntermediate,
      assets[0] // borrowed
    );
    
    return true;
  }

  function decodeAndLiquidate(bytes memory params) private returns(address, address) {
    (address borrower, 
     address cBorrowed, 
     address swapIntermediate,
     address cCollateral, 
     uint256 repayAmount) = abi.decode(params, (address, address, address, address, uint256));
    
    IERC20(ICToken(cBorrowed).underlying()).approve(cBorrowed, repayAmount);
    liquidate(borrower, cBorrowed, cCollateral, repayAmount); 
    return (swapIntermediate, cCollateral); 
  }

  function liquidate(
    address borrower,
    address cBorrowed,
    address cCollateral,
    uint256 repayAmount
  ) private {
    uint256 res = ICToken(cBorrowed).liquidateBorrow(
      borrower, repayAmount, CTokenInterface(cCollateral));
    require(res == 0, "liquidateBorrow failed.");

    // we are paid in cToken.. so we must redeem
    uint256 cTokenBalance = IERC20(cCollateral).balanceOf(address(this));

    res = CErc20Interface(cCollateral).redeem(cTokenBalance);
    require(res == 0, "redeem failed.");
  }

  function swap(
    uint256 amountIn,
    address tokenIn,
    address swapIntermediate,
    address tokenOut
  ) private {

    address _swapRouter = demask(swapRouter);
    address[] memory path = new address[](3);
    path[0] = tokenIn;
    path[1] = swapIntermediate;
    path[2] = tokenOut;
    uint256 deadline = type(uint256).max;

    IERC20(path[0]).approve(_swapRouter, amountIn);
    IUniswapV2Router02(_swapRouter).swapExactTokensForTokens(
      amountIn, 
      0, // amountOutMin
      path, 
      address(this), // to 
      deadline
    );
    // we don't care about the returned `amounts` array 
    // since flashloan etc would fail if not ideal
  }

}

