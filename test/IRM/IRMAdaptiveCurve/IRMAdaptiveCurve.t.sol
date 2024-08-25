// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IIRM} from "evk/InterestRateModels/IIRM.sol";
import {IRMAdaptiveCurve} from "../../../src/IRM/IRMAdaptiveCurve.sol";

contract IRMAdaptiveCurveTest is Test {
    address internal constant VAULT = address(0x1234);
    int256 internal constant YEAR = int256(356 days);
    int256 internal constant WAD = 1e18;
    int256 internal constant TARGET_UTILIZATION = 0.9e18;
    int256 internal constant INITIAL_RATE_AT_TARGET = 0.04e18 / YEAR;
    int256 internal constant MIN_RATE_AT_TARGET = 0.001e18 / YEAR;
    int256 internal constant MAX_RATE_AT_TARGET = 2.0e18 / YEAR;
    int256 internal constant CURVE_STEEPNESS = 4e18;
    int256 internal constant ADJUSTMENT_SPEED = 50e18 / YEAR;

    IRMAdaptiveCurve irm;

    function setUp() public {
        irm = new IRMAdaptiveCurve(
            TARGET_UTILIZATION,
            INITIAL_RATE_AT_TARGET,
            MIN_RATE_AT_TARGET,
            MAX_RATE_AT_TARGET,
            CURVE_STEEPNESS,
            ADJUSTMENT_SPEED
        );
        vm.startPrank(VAULT);
    }

    function test_OnlyVaultCanMutateIRMState() public {
        irm.computeInterestRate(VAULT, 5, 6);

        vm.expectRevert(IIRM.E_IRMUpdateUnauthorized.selector);
        vm.startPrank(address(0x2345));
        irm.computeInterestRate(VAULT, 5, 6);
    }

    function test_IRMCalculations() public {
        // First call returns `INITIAL_RATE_AT_TARGET.
        uint256 rate1 = computeRateAtUtilization(0.9e18);
        assertEq(rate1, uint256(INITIAL_RATE_AT_TARGET) * 1e9);

        // Utilization remains at `TARGET_UTILIZATION` so the rate remains at `INITIAL_RATE_AT_TARGET`.
        skip(1 minutes);
        uint256 rate2 = computeRateAtUtilization(0.9e18);
        assertEq(rate2, uint256(INITIAL_RATE_AT_TARGET) * 1e9);
        skip(365 days);
        uint256 rate3 = computeRateAtUtilization(0.9e18);
        assertEq(rate3, uint256(INITIAL_RATE_AT_TARGET) * 1e9);

        // Utilization climbs to 100% without time delay. The rate is 4x larger than initial.
        uint256 rate4 = computeRateAtUtilization(1e18);
        assertEq(rate4, uint256(CURVE_STEEPNESS * INITIAL_RATE_AT_TARGET / 1e18) * 1e9);

        // Utilization goes down to 0% without time delay. The rate is 4x smaller than initial.
        uint256 rate5 = computeRateAtUtilization(0);
        assertEq(rate5, uint256(1e18 * INITIAL_RATE_AT_TARGET / CURVE_STEEPNESS) * 1e9);

        // Utilization goes back to 90% without time delay. The rate is back at initial.
        uint256 rate6 = computeRateAtUtilization(0.9e18);
        assertEq(rate6, uint256(INITIAL_RATE_AT_TARGET) * 1e9);

        // Utilization climbs to 100% after 1 day.
        // The rate is 4x larger than initial + the whole curve has adjusted up.
        skip(1 days);
        uint256 rate7 = computeRateAtUtilization(1e18);
        assertGt(rate7, uint256(CURVE_STEEPNESS * INITIAL_RATE_AT_TARGET / 1e18) * 1e9);
        uint256 rate8 = computeRateAtUtilization(1e18);
        // Utilization goes back to 90% without time delay. The rate is back at initial + adjustment factor.
        uint256 rate9 = computeRateAtUtilization(0.9e18);
        assertEq(rate8, uint256(CURVE_STEEPNESS) * rate9 / 1e18);
    }

    function computeRateAtUtilization(uint256 utilizationRate) internal returns (uint256) {
        if (utilizationRate == 0) return irm.computeInterestRate(VAULT, 0, 0);
        if (utilizationRate == 1e18) return irm.computeInterestRate(VAULT, 0, 1e18);

        uint256 borrows = 1e18 * utilizationRate / (1e18 - utilizationRate);
        return irm.computeInterestRate(VAULT, 1e18, borrows);
    }
}
