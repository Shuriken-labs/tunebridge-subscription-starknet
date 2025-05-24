#!/usr/bin/env bash
set -euo pipefail

#####################################
# CONFIGURATION — edit these values #
#####################################
CONTRACT_NAME="TuneBridge"
NETWORK="https://api.cartridge.gg/x/starknet/sepolia"
ACCOUNT_NAME="inspiration"

# Optional constructor args (felts)
CONSTRUCTOR_ARGS=(0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D 10000000000000000000 0 20000000000000000000 0)

#####################################
# 1) DECLARE                         #
#####################################
# echo "📜 Declaring contract '$CONTRACT_NAME' on $NETWORK…"
# declare_output=$(
#   sncast --account inspiration declare \
#     --contract-name "$CONTRACT_NAME" \
#     --url "$NETWORK" \
#     --fee-token strk 
# )

# class_hash=$(echo "$declare_output" | grep -Eo 'class_hash: 0x[0-9a-fA-F]+' | awk '{print $2}')
# echo "✅ Declared with class_hash: $class_hash"

class_hash=0x00c34c32601b00f03105c4f40844a3ff8194e31243f77a90ff43ccd85a2f79f0

#####################################
# 2) DEPLOY                          #
#####################################
echo "🚀 Deploying instance to $NETWORK…"
deploy_output=$(
  sncast --account "$ACCOUNT_NAME" deploy \
    --class-hash "$class_hash" \
    --constructor-calldata "${CONSTRUCTOR_ARGS[@]}" \
    --url "$NETWORK" --unique
    
)

contract_address=$(echo "$deploy_output" | grep -Eo 'contract_address: 0x[0-9a-fA-F]+' | awk '{print $2}')
echo "✅ Deployed at contract_address: $contract_address"

#####################################
# 3) SUMMARY                         #
#####################################
echo
echo "🎉 Deployment Complete"
echo "   • Contract Name:     $CONTRACT_NAME"
echo "   • Class Hash:        $class_hash"
echo "   • Contract Address:  $contract_address"
