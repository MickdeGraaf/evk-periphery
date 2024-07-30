// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import "evk/EVault/shared/Constants.sol";

import {BasePerspective} from "../implementation/BasePerspective.sol";

/// @title EscrowPerspective
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice A contract that verifies whether a vault has properties of an escrow vault.
contract EscrowPerspective is BasePerspective {
    /// @notice Creates a new EscrowPerspective instance.
    /// @param vaultFactory_ The address of the GenericFactory contract.
    constructor(address vaultFactory_) BasePerspective(vaultFactory_) {}

    /// @inheritdoc BasePerspective
    function name() public pure virtual override returns (string memory) {
        return "Escrow Perspective";
    }

    /// @inheritdoc BasePerspective
    function perspectiveVerifyInternal(address vault) internal override {
        // the vault must be deployed by recognized factory
        testProperty(vaultFactory.isProxy(vault), ERROR__FACTORY);

        // escrow vaults must not be nested
        testProperty(!vaultFactory.isProxy(IEVault(vault).asset()), ERROR__NESTING);

        // escrow vaults must not have an oracle or unit of account
        testProperty(IEVault(vault).oracle() == address(0), ERROR__ORACLE_INVALID_ROUTER);
        testProperty(IEVault(vault).unitOfAccount() == address(0), ERROR__UNIT_OF_ACCOUNT);

        // verify vault configuration at the governance level.
        // escrow vaults must not have a governor admin, fee receiver, or interest rate model
        testProperty(IEVault(vault).governorAdmin() == address(0), ERROR__GOVERNOR);
        testProperty(IEVault(vault).feeReceiver() == address(0), ERROR__FEE_RECEIVER);
        testProperty(IEVault(vault).interestRateModel() == address(0), ERROR__INTEREST_RATE_MODEL);

        // escrow vaults must not have a hook target nor any operations disabled
        (address hookTarget, uint32 hookedOps) = IEVault(vault).hookConfig();
        testProperty(hookTarget == address(0), ERROR__HOOK_TARGET);
        testProperty(hookedOps == 0, ERROR__HOOKED_OPS);

        // escrow vaults must not have any config flags set
        testProperty(IEVault(vault).configFlags() == 0, ERROR__CONFIG_FLAGS);

        // escrow vaults must neither have liquidation discount nor liquidation cool off time
        testProperty(IEVault(vault).maxLiquidationDiscount() == 0, ERROR__LIQUIDATION_DISCOUNT);
        testProperty(IEVault(vault).liquidationCoolOffTime() == 0, ERROR__LIQUIDATION_COOL_OFF_TIME);

        // escrow vaults must not have any collateral set up
        testProperty(IEVault(vault).LTVList().length == 0, ERROR__LTV_COLLATERAL_CONFIG_LENGTH);
    }
}
