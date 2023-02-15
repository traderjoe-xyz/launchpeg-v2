// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./LaunchpegErrors.sol";
import {ERC1155LaunchpegBase} from "./ERC1155LaunchpegBase.sol";

contract ERC1155SingleBundle is ERC1155LaunchpegBase {
    struct PreMintData {
        address sender;
        uint96 quantity;
    }

    struct PreMintDataSet {
        PreMintData[] preMintDataArr;
        mapping(address => uint256) indexes;
    }

    uint256 public maxSupply;
    uint256 public maxPerAddressDuringMint;

    uint256 public preMintPrice;
    uint256 public publicSalePrice;

    uint256 public preMintStartTime;
    uint256 public publicSaleStartTime;
    uint256 public publicSaleEndTime;

    uint256 public amountForDevs;
    uint256 public amountForPreMint;

    uint256 public amountMintedByDevs;
    uint256 public amountMintedDuringPreMint;
    uint256 public amountClaimedDuringPreMint;
    uint256 public amountMintedDuringPublicSale;

    mapping(address => uint256) public allowlist;

    uint256[] private _tokenSet;
    PreMintDataSet private _pendingPreMints;

    event AllowlistSeeded();
    event PreMintStartTimeSet(uint256 preMintStartTime);
    event PublicSaleStartTimeSet(uint256 publicSaleStartTime);
    event PublicSaleEndTimeSet(uint256 publicSaleEndTime);
    event AmountForDevsSet(uint256 amountForDevs);
    event AmountForPreMintSet(uint256 amountForPreMint);
    event PreMintPriceSet(uint256 preMintPrice);
    event PublicSalePriceSet(uint256 publicSalePrice);
    event MaxPerAddressDuringMintSet(uint256 maxPerAddressDuringMint);
    event MaxSupplySet(uint256 maxSupply);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        InitData calldata initData,
        uint256 initialMaxSupply,
        uint256 initialAmountForDevs,
        uint256 initialAmountForPreMint,
        uint256 initialMaxPerAddressDuringMint,
        uint256[] calldata initialTokenSet
    ) external initializer {
        __ERC1155LaunchpegBase_init(initData);

        maxSupply = initialMaxSupply;
        maxPerAddressDuringMint = initialMaxPerAddressDuringMint;

        amountForDevs = initialAmountForDevs;
        amountForPreMint = initialAmountForPreMint;
        _tokenSet = initialTokenSet;
    }

    function initializePhases(
        uint256 initialPreMintStartTime,
        uint256 initialPublicSaleStartTime,
        uint256 initialPublicSaleEndTime,
        uint256 initialPreMintPrice,
        uint256 initialPublicSalePrice
    ) external onlyOwner atPhase(Phase.NotStarted) {
        if (
            initialPreMintStartTime < block.timestamp ||
            initialPublicSaleStartTime < initialPreMintStartTime ||
            initialPublicSaleEndTime < initialPublicSaleStartTime
        ) {
            revert Launchpeg__InvalidPhases();
        }

        if (initialPreMintPrice > initialPublicSalePrice) {
            revert Launchpeg__InvalidAllowlistPrice();
        }

        preMintPrice = initialPreMintPrice;
        publicSalePrice = initialPublicSalePrice;
        preMintStartTime = initialPreMintStartTime;

        publicSaleStartTime = initialPublicSaleStartTime;
        publicSaleEndTime = initialPublicSaleEndTime;

        withdrawAVAXStartTime = initialPublicSaleStartTime + 3 days;
    }

    function tokenSet() external view returns (uint256[] memory) {
        return _tokenSet;
    }

    function currentPhase() public view override returns (Phase) {
        if (
            preMintStartTime == 0 ||
            publicSaleStartTime == 0 ||
            publicSaleEndTime == 0 ||
            block.timestamp < preMintStartTime
        ) {
            return Phase.NotStarted;
        } else if (
            amountMintedDuringPreMint + amountMintedDuringPublicSale >=
            maxSupply
        ) {
            return Phase.Ended;
        } else if (
            block.timestamp >= preMintStartTime &&
            block.timestamp < publicSaleStartTime
        ) {
            return Phase.PreMint;
        } else if (
            block.timestamp >= publicSaleStartTime &&
            block.timestamp < publicSaleEndTime
        ) {
            return Phase.PublicSale;
        }
        return Phase.Ended;
    }

    function amountOfUsersWaitingForPremint() external view returns (uint256) {
        return _pendingPreMints.preMintDataArr.length;
    }

    function userPendingPreMints(address user) external view returns (uint256) {
        uint256 userIndex = _pendingPreMints.indexes[user];

        if (userIndex == 0) {
            return 0;
        }
        return _pendingPreMints.preMintDataArr[userIndex - 1].quantity;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function devMint(
        uint256 amount
    ) external onlyOwnerOrRole(PROJECT_OWNER_ROLE) nonReentrant {
        uint256 amountAlreadyMinted = amountMintedByDevs;

        if (amountAlreadyMinted + amount > amountForDevs)
            revert Launchpeg__MaxSupplyForDevReached();

        amountMintedByDevs = amountAlreadyMinted + amount;

        _mint(msg.sender, amount);
    }

    function preMint(
        uint96 amount
    ) external payable atPhase(Phase.PreMint) nonReentrant {
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

    function claimPremint() external nonReentrant {
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
                    lastIndex
                ];
                pmDataSet.preMintDataArr[userIndex - 1] = lastPreMintData;
                pmDataSet.indexes[lastPreMintData.sender] = userIndex;
            }
            pmDataSet.preMintDataArr.pop();
            delete pmDataSet.indexes[msg.sender];
        } else {
            revert("no pre-minted tokens");
        }

        _mint(msg.sender, preMintQuantity);
        amountClaimedDuringPreMint += preMintQuantity;
    }

    function batchClaimPreMint(uint256 numberOfClaims) external nonReentrant {
        uint256 initialRemainingPreMints = _pendingPreMints
            .preMintDataArr
            .length;

        uint256 remainingPreMints = initialRemainingPreMints;
        uint256 tokenPreMinted = 0;

        while (remainingPreMints > 0 && numberOfClaims > 0) {
            PreMintData memory preMintData = _pendingPreMints.preMintDataArr[
                remainingPreMints - 1
            ];

            delete _pendingPreMints.indexes[preMintData.sender];
            tokenPreMinted += preMintData.quantity;

            _mint(preMintData.sender, preMintData.quantity);

            remainingPreMints--;
            numberOfClaims--;
        }

        uint256 amountPreMinted = initialRemainingPreMints - remainingPreMints;
        amountClaimedDuringPreMint += tokenPreMinted;

        PreMintData[] storage preMintDataArr = _pendingPreMints.preMintDataArr;

        // Removing the pre-minted tokens from the array all at once
        assembly {
            sstore(
                preMintDataArr.slot,
                sub(initialRemainingPreMints, amountPreMinted)
            )
        }
    }

    function publicSaleMint(
        uint256 amount
    ) external payable atPhase(Phase.PublicSale) nonReentrant {
        amountMintedDuringPublicSale += amount;
        _mint(msg.sender, amount);
        _refundIfOver(publicSalePrice * amount);
    }

    function updateTokenSet(
        uint256[] calldata newTokenSet
    ) external onlyOwner atPhase(Phase.NotStarted) {
        _tokenSet = newTokenSet;
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

    function setAmountForDevs(uint256 newAmountForDevs) external onlyOwner {
        amountForDevs = newAmountForDevs;
        emit AmountForDevsSet(newAmountForDevs);
    }

    function setAmountForPreMint(
        uint256 newAmountForPreMint
    ) external onlyOwner {
        amountForPreMint = newAmountForPreMint;
        emit AmountForPreMintSet(newAmountForPreMint);
    }

    function setPreMintPrice(uint256 newPreMintPrice) external onlyOwner {
        preMintPrice = newPreMintPrice;
        emit PreMintPriceSet(newPreMintPrice);
    }

    function setPublicSalePrice(uint256 newPublicSalePrice) external onlyOwner {
        publicSalePrice = newPublicSalePrice;
        emit PublicSalePriceSet(newPublicSalePrice);
    }

    function setMaxSupply(uint256 newMaxSupply) external onlyOwner {
        maxSupply = newMaxSupply;
        emit MaxSupplySet(newMaxSupply);
    }

    function setMaxPerAddressDuringMint(
        uint256 newMaxAmountPerUser
    ) external onlyOwner {
        maxPerAddressDuringMint = newMaxAmountPerUser;
        emit MaxPerAddressDuringMintSet(newMaxAmountPerUser);
    }

    function _availableSupply() internal view returns (uint256) {
        return
            maxSupply -
            amountMintedDuringPreMint -
            amountMintedDuringPublicSale -
            amountForDevs;
    }

    function _mint(address to, uint256 amount) internal {
        uint256 tokenAmount = _tokenSet.length;

        for (uint i = 0; i < tokenAmount; i++) {
            _mint(to, _tokenSet[i], amount, "");
        }
    }
}
