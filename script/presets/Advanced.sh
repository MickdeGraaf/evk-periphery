#!/bin/bash

if [[ ! -d "$(pwd)/script" ]]; then
    echo "Error: script directory does not exist in the current directory."
    echo "Please ensure this script is run from the top project directory."
    exit 1
fi

if [[ -f .env ]]; then
    source .env
    echo ".env file loaded successfully."
else
    echo "Error: .env file does not exist. Please create it and try again."
    exit 1
fi

echo ""
echo "Welcome to the Advanced Deployment script!"
echo "This script will deploy the advanced preset of smart contracts."

# Check if DEPLOYMENT_RPC_URL environment variable is set
if [ -z "$DEPLOYMENT_RPC_URL" ]; then
    echo "Error: DEPLOYMENT_RPC_URL environment variable is not set. Please set it and try again."
    exit 1
else
    echo "DEPLOYMENT_RPC_URL is set to: $DEPLOYMENT_RPC_URL"
fi

read -p "Do you want to verify the deployed contracts? (y/n) (default: n): " verify_contracts
verify_contracts=${verify_contracts:-n}

if [[ $verify_contracts == "y" ]]; then
    if [ -z "$VERIFIER_URL" ]; then
        echo "Error: VERIFIER_URL environment variable is not set. Please set it and try again."
        exit 1
    fi

    if [ -z "$VERIFIER_API_KEY" ]; then
        echo "Error: VERIFIER_API_KEY environment variable is not set. Please set it and try again."
        exit 1
    fi
fi

# Deal tokens to the provided account
account=$(cast wallet address --private-key "$DEPLOYER_KEY")
./script/_tenderlyDeal.sh $account "[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,0x6B175474E89094C44Da98b954EedeAC495271d0F,0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0]"

# Deploy the advanced preset
forge script script/presets/Advanced.s.sol --rpc-url "$DEPLOYMENT_RPC_URL" --broadcast --slow

if [[ $verify_contracts != "y" ]]; then
    exit 1
fi

# Verify the deployed smart contracts
transactions=$(jq -c '.transactions[]' ./broadcast/Advanced.s.sol/1/run-latest.json)

# Iterate over each transaction and verify it
for tx in $transactions; do
    transactionType=$(echo $tx | grep -o '"transactionType":"[^"]*' | grep -o '[^"]*$')
    contractName=$(echo $tx | grep -o '"contractName":"[^"]*' | grep -o '[^"]*$')
    contractAddress=$(echo $tx | grep -o '"contractAddress":"[^"]*' | grep -o '[^"]*$')    

    if [[ $transactionType != "CREATE" || $contractName == "" || $contractAddress == "" ]]; then
        if [[ $transactionType == "CREATE" && ( $contractName != "" || $contractAddress != "" ) ]]; then
            echo "Skipping $contractName: $contractAddress"
        fi
        continue
    fi
    
    verify_command="forge verify-contract $contractAddress $contractName --rpc-url \"$DEPLOYMENT_RPC_URL\" --verifier-url \"$VERIFIER_URL\" --etherscan-api-key \"$VERIFIER_API_KEY\" --skip-is-verified-check --watch"
    
    echo "Verifying $contractName: $contractAddress"
    result=$(eval $verify_command --flatten --force 2>&1)

    if [[ "$result" == *"Contract successfully verified"* ]]; then
        echo "Success"
    else
        result=$(eval $verify_command 2>&1)

        if [[ "$result" == *"Contract successfully verified"* ]]; then
            echo "Success"
        else
            echo "Failure"
        fi
    fi
done
