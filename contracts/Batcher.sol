//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Common.sol";
import "./Liquidator.sol";

contract Batcher is Common {

  Liquidator private liquidator;

  constructor() {
    liquidator = new Liquidator();
  }

  function BatchLiquidate(
    address[] calldata addresses,
    address beneficiary,
    uint256[] calldata  repayAmounts,
    FlashLoanProvider[] calldata flashLoanProviders
  ) external { 
    // note: this is unchecked in the sense that array lens are assumed to be commensurate 
    // failure in one, is failure in all.

    uint256 gasShare = gasleft() / repayAmounts.length;

    for (uint256 i; i<repayAmounts.length; i++) {
      try liquidator.Liquidate{gas:gasShare}( // limit the gas since a failure will burn all gas
          addresses[4*i],     // borrowers
          addresses[4*i + 1], // cBorroweds
          addresses[4*i + 2], // swapIntermediates
          addresses[4*i + 3], // cCollaterals
          beneficiary,
          repayAmounts[i],
          flashLoanProviders[i]
      ) {
      
      } catch {
      
      }
    } 
  }

}

