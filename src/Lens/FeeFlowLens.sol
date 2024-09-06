// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;


import { FeeFlowController } from  "fee-flow/FeeFlowController.sol";
import { IPerspective } from "../Perspectives/implementation/interfaces/IPerspective.sol";
import { IEVC } from "evc/interfaces/IEthereumVaultConnector.sol";
import { IEVault, IERC20, IGovernance } from "evk/EVault/IEVault.sol";

contract FeeFlowLens {
    FeeFlowController public immutable feeFlowController;
    IPerspective public immutable perspective;
    IEVC public immutable evc;

    struct ResultAsset {
        address vault;
        string symbol;
        string name;
        uint256 amount;
        address underlyingAsset;
        string underlyingSymbol;
        string underlyingName;
        uint256 underlyingAmount;
        uint8 underlyingDecimals;
    }

    struct Result {
        address paymentToken;
        string paymentTokenName;
        string paymentTokenSymbol;
        address paymentReceiver;
        uint256 epochPeriod;
        uint256 priceMultiplier;
        uint256 minInitPrice;
        uint256 epochId;
        uint256 initPrice;
        uint256 startTime;
        ResultAsset[] assets;
    }

    constructor(address _feeFlowController, address _perspective, address _evc) {
        feeFlowController = FeeFlowController(_feeFlowController);
        perspective = IPerspective(_perspective);
        evc = IEVC(_evc);
    }

    function getData() external returns (Result memory) {
        FeeFlowController.Slot0 memory slot0 = feeFlowController.getSlot0();

        Result memory result;
        result.paymentToken = address(feeFlowController.paymentToken());
        result.paymentTokenName = IERC20(result.paymentToken).name();
        result.paymentTokenSymbol = IERC20(result.paymentToken).symbol();
        result.paymentReceiver = feeFlowController.paymentReceiver();
        result.epochPeriod = feeFlowController.epochPeriod();
        result.priceMultiplier = feeFlowController.priceMultiplier();
        result.minInitPrice = feeFlowController.minInitPrice();
        result.epochId = slot0.epochId;
        result.initPrice = slot0.initPrice;
        result.startTime = slot0.startTime;

        address[] memory vaults = perspective.verifiedArray();

        // generate evc batch items to claim fees + fetch balances
        IEVC.BatchItem[] memory batchItems = new IEVC.BatchItem[](vaults.length);
        uint256 batchItemIndex = 0;
        for(uint256 i = 0; i < vaults.length; i ++) {
            batchItems[batchItemIndex] = IEVC.BatchItem({
                targetContract: vaults[i],
                onBehalfOfAccount: address(this),
                value: 0,
                data: abi.encodeWithSelector(IGovernance.convertFees.selector)
            });

            batchItemIndex++;

            batchItems[batchItemIndex] = IEVC.BatchItem({
                targetContract: vaults[i],
                onBehalfOfAccount: address(this),
                value: 0,
                data: abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
            });

            batchItemIndex++;
        }

        // simulate evc claim fees + fetch balances
        (IEVC.BatchItemResult[] memory results, ,) = evc.batchSimulation(batchItems);

        // loop over every 2nd item to get vault share balance after claiming fees
        uint256 vaultIndex = 0;
        ResultAsset[] memory resultAsset = new ResultAsset[](vaults.length);
        for(uint256 i = 1; i < results.length; i += 2) {
            IEVault vault = IEVault(vaults[vaultIndex]);

            uint256 sharesBalance = abi.decode(results[i].result, (uint256));

            resultAsset[vaultIndex] = ResultAsset({
                vault: address(vault),
                symbol: vault.symbol(),
                name: vault.name(),
                amount: sharesBalance,
                underlyingAsset: vault.asset(),
                underlyingSymbol: IERC20(vault.asset()).symbol(),
                underlyingName: IERC20(vault.asset()).name(),
                underlyingAmount: vault.convertToAssets(sharesBalance),
                underlyingDecimals: IERC20(vault.asset()).decimals()
            });

            vaultIndex ++;
        }

        return result;
    }
}