// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZPXArb} from "./ZPXArb.sol";

// V2 placeholder: base ZPXArb already includes burnable behavior in V1.
contract ZPXArbV2_Burnable is ZPXArb {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initializeV2_Burnable() public reinitializer(2) {
        // No-op: V1 already initialized ERC20Burnable. Kept for upgrade scaffolding.
    }

    // leave space for future variables
    uint256[50] private __gap_v2;
}
