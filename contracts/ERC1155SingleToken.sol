// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC1155LaunchpegBase.sol";

contract ERC1155SingleToken is ERC1155LaunchpegBase {
    uint256 public maxSupply;
    uint256 public price;

    constructor() {
        // _disableInitializers();
    }

    function initialize(
        address owner,
        address projectOwner,
        address royaltyReceiver,
        string memory uri,
        uint256 initialMaxSupply,
        uint256 initialPrice,
        string memory collectionName,
        string memory collectionSymbol
    ) external initializer {
        __ERC1155LaunchpegBase_init(
            owner,
            projectOwner,
            royaltyReceiver,
            uri,
            collectionName,
            collectionSymbol
        );

        maxSupply = initialMaxSupply;
        price = initialPrice;
    }

    function publicSaleMint(uint256 amount) external {
        _mint(msg.sender, 0, amount, "");
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
