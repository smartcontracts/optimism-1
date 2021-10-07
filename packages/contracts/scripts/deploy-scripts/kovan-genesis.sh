#!/bin/bash

export L2_BLOCK_GAS_LIMIT=15000000
export L2_CHAIN_ID=69
export BLOCK_SIGNER_ADDRESS=0x27770a9694e4B4b1E130Ab91Bc327C36855f612E
export L1_STANDARD_BRIDGE_ADDRESS=
export L1_FEE_WALLET_ADDRESS=0xB79f76EF2c5F0286176833E7B2eEe103b1CC3244
export L1_CROSS_DOMAIN_MESSENGER_ADDRESS=
export WHITELIST_OWNER=0x0000000000000000000000000000000000000000
export GAS_PRICE_ORACLE_OWNER=
yarn build:dump
