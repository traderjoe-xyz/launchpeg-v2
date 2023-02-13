// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC1155LaunchpegBase.sol";

contract ERC1155SingleToken is ERC1155LaunchpegBase {
    uint256 public maxSupply;
    uint256 public preMintPrice;
    uint256 public price;
    uint256 public preMintStartTime;
    uint256 public publicSaleStartTime;
    uint256 public publicSaleEndTime;
    uint256 public maxPerAddressDuringMint;

    uint256 public amountMintedByDevs;
    uint256 public amountMintedDuringPreMint;
    uint256 public amountClaimedDuringPreMint;
    uint256 public amountMintedDuringAllowlist;
    uint256 public amountMintedDuringPublicSale;

    mapping(address => uint256) public allowlist;

    struct PreMintData {
        address sender;
        uint96 quantity;
    }

    struct PreMintDataSet {
        PreMintData[] preMintDataArr;
        mapping(address => uint256) indexes;
    }

    PreMintDataSet private _pendingPreMints;

    event AllowlistSeeded();
    event PreMintStartTimeSet(uint256 preMintStartTime);
    event PublicSaleStartTimeSet(uint256 publicSaleStartTime);
    event PublicSaleEndTimeSet(uint256 publicSaleEndTime);

    constructor() {
        // _disableInitializers();
    }

    function initialize(
        address owner,
        address royaltyReceiver,
        address initialJoeFeeCollector,
        uint256 initialJoeFeePercent,
        string memory uri,
        uint256 initialMaxSupply,
        uint256 initialPrice,
        uint256 initialPreMintStartTime,
        uint256 initialPublicSaleStartTime,
        uint256 initialPublicSaleEndTime,
        string memory collectionName,
        string memory collectionSymbol
    ) external initializer {
        __ERC1155LaunchpegBase_init(
            owner,
            royaltyReceiver,
            initialJoeFeeCollector,
            initialJoeFeePercent,
            uri,
            collectionName,
            collectionSymbol,
            initialPublicSaleStartTime + 3 days
        );

        maxSupply = initialMaxSupply;
        price = initialPrice;
        preMintStartTime = initialPreMintStartTime;
        publicSaleStartTime = initialPublicSaleStartTime;
        publicSaleEndTime = initialPublicSaleEndTime;
    }

    function devMint(
        uint256 amount
    ) external onlyOwnerOrRole(PROJECT_OWNER_ROLE) {
        amountMintedByDevs = amountMintedByDevs + amount;
        _mint(msg.sender, 0, amount, "");
    }

    function preMint(uint96 amount) external payable {
        require(
            block.timestamp >= preMintStartTime,
            "preMint: Premint has not started yet"
        );

        PreMintDataSet storage pmDataSet = _pendingPreMints;
        uint256 userIndex = pmDataSet.indexes[msg.sender];

        if (userIndex != 0) {
            pmDataSet.preMintDataArr[userIndex - 1].quantity += amount;
        } else {
            PreMintData memory preMintData = PreMintData({
                sender: msg.sender,
                quantity: amount
            });
            pmDataSet.preMintDataArr.push(preMintData);
            pmDataSet.indexes[msg.sender] = pmDataSet.preMintDataArr.length;
        }

        amountMintedDuringPreMint += amount;

        allowlist[msg.sender] -= amount;
        _refundIfOver(preMintPrice * amount);
    }

    function claimPremint() external {
        require(
            block.timestamp >= publicSaleStartTime,
            "preMint: Premint has not started yet"
        );

        PreMintDataSet storage pmDataSet = _pendingPreMints;

        uint256 userIndex = pmDataSet.indexes[msg.sender];
        uint96 preMintQuantity;
        if (userIndex != 0) {
            preMintQuantity = pmDataSet.preMintDataArr[userIndex - 1].quantity;

            uint256 lastIndex = pmDataSet.preMintDataArr.length - 1;
            if (lastIndex != userIndex - 1) {
                PreMintData memory lastPreMintData = pmDataSet.preMintDataArr[
                    userIndex - 1
                ];
                pmDataSet.preMintDataArr[userIndex - 1] = lastPreMintData;
                pmDataSet.indexes[lastPreMintData.sender] = userIndex;
            }
            pmDataSet.preMintDataArr.pop();
            delete pmDataSet.indexes[msg.sender];
        } else {
            revert("no pre-minted tokens");
        }

        _mint(msg.sender, 0, preMintQuantity, "");
        amountClaimedDuringPreMint += preMintQuantity;
    }

    function batchClaimPreMint(uint256 numberOfClaims) external {
        uint256 initialRemainingPreMints = _pendingPreMints
            .preMintDataArr
            .length;

        uint256 remainingPreMints = initialRemainingPreMints;

        while (remainingPreMints > 0 && numberOfClaims > 0) {
            PreMintData memory preMintData = _pendingPreMints.preMintDataArr[
                remainingPreMints - 1
            ];

            delete _pendingPreMints.indexes[preMintData.sender];

            _mint(preMintData.sender, 0, preMintData.quantity, "");

            remainingPreMints--;
            numberOfClaims--;
        }

        uint256 amountPreMinted = initialRemainingPreMints - remainingPreMints;
        PreMintData[] storage preMintDataArr = _pendingPreMints.preMintDataArr;

        // Removing the pre-minted tokens from the array all at once
        assembly {
            sstore(
                preMintDataArr.slot,
                sub(initialRemainingPreMints, amountPreMinted)
            )
        }
    }

    function publicSaleMint(uint256 amount) external payable {
        require(
            block.timestamp <= publicSaleStartTime ||
                block.timestamp >= publicSaleEndTime,
            "preMint: Premint has not started yet"
        );

        _mint(msg.sender, 0, amount, "");
        _refundIfOver(price * amount);
    }

    function seedAllowlist(
        address[] calldata addresses,
        uint256[] calldata amounts
    ) external onlyOwner {
        uint256 addressesLength = addresses.length;
        if (addressesLength != amounts.length) {
            revert Launchpeg__WrongAddressesAndNumSlotsLength();
        }
        for (uint256 i; i < addressesLength; i++) {
            allowlist[addresses[i]] = amounts[i];
        }

        emit AllowlistSeeded();
    }

    function setPreMintStartTime(
        uint256 newPreMintStartTime
    ) external onlyOwner {
        preMintStartTime = newPreMintStartTime;
        emit PreMintStartTimeSet(newPreMintStartTime);
    }

    function setPublicSaleStartTime(
        uint256 newPublicSaleStartTime
    ) external onlyOwner {
        publicSaleStartTime = newPublicSaleStartTime;
        emit PublicSaleStartTimeSet(newPublicSaleStartTime);
    }

    function setPublicSaleEndTime(
        uint256 newPublicSaleEndTime
    ) external onlyOwner {
        publicSaleEndTime = newPublicSaleEndTime;
        emit PublicSaleEndTimeSet(newPublicSaleEndTime);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
