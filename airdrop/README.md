## QuickStart
```
git clone https://github.com/weaving0x7E/Decentra
cd Decentra/airdrop
make # or forge install && forge build if you don't have make 
```

## Usage
### Pre-deploy: Generate merkle proofs
We are going to generate merkle proofs for an array of addresses to airdrop funds to. If you'd like to work with the default addresses and proofs already created in this repo, skip to deploy

If you'd like to work with a different array of addresses (the whitelist list in GenerateInput.s.sol), you will need to follow the following:

First, the array of addresses to airdrop to needs to be updated in `GenerateInput.s.sol. To generate the input file and then the merkle root and proofs, run the following:

Using make:
```make merkle```

## Deploy
```
# Run a local anvil node
make anvil
# Then, in a second terminal
make deploy
```

## Interacting - Local anvil network
Copy the Bagel Token and Airdrop contract addresses and paste them into the AIRDROP_ADDRESS and TOKEN_ADDRESS variables in the MakeFile

The following steps allow the second default anvil address (0x70997970C51812dc3A010C7d01b50e0d17dc79C8) to call claim and pay for the gas on behalf of the first default anvil address (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) which will recieve the airdrop.


### Sign your airdrop claim
```
# in another terminal
make sign
```
Retrieve the signature bytes outputted to the terminal and add them to Interact.s.sol making sure to remove the 0x prefix.

Additionally, if you have modified the claiming addresses in the merkle tree, you will need to update the proofs in this file too (which you can get from output.json)

### Claim your airdrop
Then run the following command:
```make claim```

### Check claim amount
Then, check the claiming address balance has increased by running
```make balance```

## Testing
```forge test```