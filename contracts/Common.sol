//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

contract Common {

  event Log(uint256 idx, uint256 number);

  enum FlashLoanProvider { BALANCER, AAVE } // dydx etc

  // hack address(0x00..) for compiler checksum warnings

  address internal immutable comptroller = address(0x003d9819210a31b4961b30ef54be2aed79b9c9cd3b);

  function demask(address maskedAddress) internal pure returns(address) {
    // trivial for now
    address unmasked = maskedAddress;
    return unmasked;
  }

}

