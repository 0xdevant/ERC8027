<!-- ABOUT THE PROJECT -->

## About The Project

[ERC8027](https://ethereum-magicians.org/t/erc-8027-manual-recurring-subscription-nfts-subnfts/25482) proposes a standard implementation as an extension for NFTs - specifically ERC721 tokens to enable manual and recurring subscription service with auto expiration i.e. Subscription NFTs (hereinafter SubNFTs).

The interface includes functions to renew subscription, signal for recurring subscription by signing via Permit2, charge subscription fee automatically as service provider, and cancel the subscription by revoking Permit2 allowance.

This is **experimental software** and is provided on an "as is" and "as available" basis.
We **do not give any warranties** and **will not be liable for any loss** incurred through any use of this codebase.

<!-- Installation -->

## Installation

To install with [**Foundry**](https://github.com/gakonst/foundry):

```sh
forge install 0xdevant/ERC8027
```

To import the contract in a hardhat-like fashion, you can add the following line to your [remappings](https://book.getfoundry.sh/reference/forge/forge-remappings):

```
ERC8027/=lib/ERC8027/
```

Then you can import ERC8027 like so:

```solidity
pragma solidity ^0.8.29;

import {SubNFT} from "ERC8027/src/SubNFT.sol";

contract Contract is SubNFT {
    constructor(
        string memory name_,
        string memory symbol_,
        SubscriptionConfig memory subscriptionConfig,
        address permit2
    ) SubNFT(name_, symbol_, subscriptionConfig, permit2) {}
}
```

<!-- USAGE EXAMPLES -->

## Usage

A good starting point is the [SubNFTMock.sol](./src/mocks/SubNFTMock.sol)
which provides an example implementation of ERC8027.

### Test

```shell
$ forge test -vv
```

### Deploy

```shell
# deploy the contract, remove --broadcast to simulate deployment
$ forge script script/Deploy.s.sol --rpc-url <RPC_URL> --account <YOUR_WALLET_IN_KEYSTORE> --broadcast
```

### Generate coverage reports

```shell
$ forge coverage
```

<!-- ROADMAP -->

## Roadmap

- [x] Maintain high test coverage
- [ ] Add npm support
- [ ] Add fuzz/invariant test

See the [open issues](https://github.com/0xdevant/ERC8027/issues) for a full list of proposed features (and known issues).

<!-- CONTRIBUTING -->

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".

Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<!-- LICENSE -->

## License

Distributed under the MIT License. See [LICENSE](./LICENSE) for more details.

## Acknowledgements

The implementation is inspired by the foundation and direction of the [Subscription NFTs EIP](https://ethereum-magicians.org/t/eip-5643-subscription-nfts/10802) proposed by @cygaar previously. Unfortunately he isn’t actively working on that EIP now thus I have added cygaar as the co-author for this SubNFT standard instead - I hope ERC8027 can offer a better implementation on real-world on-chain recurring subscription w/o relying on external dependencies from Account Abstraction.
