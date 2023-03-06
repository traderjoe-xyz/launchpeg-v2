// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./LaunchpegErrors.sol";
import {ERC1155LaunchpegBase} from "./ERC1155LaunchpegBase.sol";
import {IERC1155LaunchpegSingleBundle} from "./interfaces/IERC1155LaunchpegSingleBundle.sol";

contract ERC1155SingleBundle is
    IERC1155LaunchpegSingleBundle,
    ERC1155LaunchpegBase
{
    struct PreMintData {
        address sender;
        uint96 quantity;
    }

    struct PreMintDataSet {
        PreMintData[] preMintDataArr;
        mapping(address => uint256) indexes;
    }

    uint256 public collectionSize;
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
    mapping(address => uint256) public numberMinted;

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
    event CollectionSizeSet(uint256 collectionSize);
    event PhaseInitialized(
        uint256 preMintStartTime,
        uint256 publicSaleStartTime,
        uint256 publicSaleEndTime,
        uint256 preMintPrice,
        uint256 salePrice,
        uint256 withdrawAVAXStartTime
    );
    event DevMint(address indexed sender, uint256 quantity);
    event PreMint(address indexed sender, uint256 quantity, uint256 price);
    event TokenSetUpdated(uint256[] tokenSet);

    modifier isEOA() {
        if (tx.origin != msg.sender) {
            revert Launchpeg__Unauthorized();
        }
        _;
    }

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

        if (amountForDevs + amountForPreMint > collectionSize) {
            revert Launchpeg__LargerCollectionSizeNeeded();
        }

        collectionSize = initialMaxSupply;
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

        emit PhaseInitialized(
            preMintStartTime,
            publicSaleStartTime,
            publicSaleEndTime,
            initialPreMintPrice,
            initialPublicSalePrice,
            initialPublicSaleStartTime + 3 days
        );
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
            amountMintedDuringPreMint + amountMintedDuringPublicSale ==
            collectionSize
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

    function amountOfUsersWaitingForPremintClaim()
        external
        view
        returns (uint256)
    {
        return _pendingPreMints.preMintDataArr.length;
    }

    function userPendingPreMints(address user) public view returns (uint256) {
        uint256 userIndex = _pendingPreMints.indexes[user];

        if (userIndex == 0) {
            return 0;
        }

        return _pendingPreMints.preMintDataArr[userIndex - 1].quantity;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IERC1155LaunchpegSingleBundle).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function devMint(
        uint256 amount
    ) external whenNotPaused onlyOwnerOrRole(PROJECT_OWNER_ROLE) nonReentrant {
        uint256 amountAlreadyMinted = amountMintedByDevs;

        if (amountAlreadyMinted + amount > amountForDevs)
            revert Launchpeg__MaxSupplyForDevReached();

        amountMintedByDevs = amountAlreadyMinted + amount;

        _mint(msg.sender, amount);

        emit DevMint(msg.sender, amount);
    }

    function preMint(
        uint96 amount
    ) external payable whenNotPaused atPhase(Phase.PreMint) nonReentrant {
        if (amount == 0) {
            revert Launchpeg__InvalidQuantity();
        }

        uint256 userAllowlistAmount = allowlist[msg.sender];
        if (amount > userAllowlistAmount) {
            revert Launchpeg__NotEligibleForAllowlistMint();
        }

        uint256 amountAlreadyPreMinted = amountMintedDuringPreMint;
        if (amountAlreadyPreMinted + amount > amountForPreMint) {
            revert Launchpeg__MaxSupplyReached();
        }

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

        amountMintedDuringPreMint = amountAlreadyPreMinted + amount;
        allowlist[msg.sender] = userAllowlistAmount - amount;

        uint256 totalPrice = preMintPrice * amount;
        _refundIfOver(totalPrice);

        emit PreMint(msg.sender, amount, totalPrice);
    }

    function claimPremint() external whenNotPaused nonReentrant {
        if (block.timestamp < publicSaleStartTime) {
            revert Launchpeg__WrongPhase();
        }

        PreMintDataSet storage pmDataSet = _pendingPreMints;

        uint96 preMintQuantity;
        uint256 userIndex = pmDataSet.indexes[msg.sender];

        if (userIndex != 0)
            preMintQuantity = pmDataSet.preMintDataArr[userIndex - 1].quantity;

        if (preMintQuantity != 0) {
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
            revert Launchpeg__InvalidClaim();
        }

        amountClaimedDuringPreMint += preMintQuantity;

        _mint(msg.sender, preMintQuantity);
    }

    function batchClaimPreMint(
        uint256 numberOfClaims
    ) external whenNotPaused nonReentrant {
        if (block.timestamp < publicSaleStartTime) {
            revert Launchpeg__WrongPhase();
        }

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
            remainingPreMints--;
            numberOfClaims--;

            _mint(preMintData.sender, preMintData.quantity);
        }

        amountClaimedDuringPreMint += tokenPreMinted;

        // Removing the pre-minted tokens from the array all at once
        PreMintData[] storage preMintDataArr = _pendingPreMints.preMintDataArr;
        assembly {
            sstore(preMintDataArr.slot, remainingPreMints)
        }
    }

    function publicSaleMint(
        uint256 amount
    )
        external
        payable
        whenNotPaused
        atPhase(Phase.PublicSale)
        nonReentrant
        isEOA
    {
        if (
            numberMinted[msg.sender] +
                userPendingPreMints(msg.sender) +
                amount >
            maxPerAddressDuringMint
        ) {
            revert Launchpeg__CanNotMintThisMany();
        }

        if (amount > _availableSupply()) {
            revert Launchpeg__MaxSupplyReached();
        }

        amountMintedDuringPublicSale += amount;

        _mint(msg.sender, amount);
        _refundIfOver(publicSalePrice * amount);
    }

    function updateTokenSet(uint256[] calldata newTokenSet) external onlyOwner {
        _tokenSet = newTokenSet;
        emit TokenSetUpdated(newTokenSet);
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
    ) external onlyOwner contractNotLocked {
        if (newPreMintStartTime > publicSaleStartTime)
            revert Launchpeg__InvalidPhases();

        preMintStartTime = newPreMintStartTime;
        emit PreMintStartTimeSet(newPreMintStartTime);
    }

    function setPublicSaleStartTime(
        uint256 newPublicSaleStartTime
    ) external onlyOwner contractNotLocked {
        if (newPublicSaleStartTime > publicSaleEndTime)
            revert Launchpeg__InvalidPhases();

        publicSaleStartTime = newPublicSaleStartTime;
        emit PublicSaleStartTimeSet(newPublicSaleStartTime);
    }

    function setPublicSaleEndTime(
        uint256 newPublicSaleEndTime
    ) external onlyOwner contractNotLocked {
        if (newPublicSaleEndTime < publicSaleStartTime)
            revert Launchpeg__InvalidPhases();

        publicSaleEndTime = newPublicSaleEndTime;
        emit PublicSaleEndTimeSet(newPublicSaleEndTime);
    }

    function setAmountForDevs(
        uint256 newAmountForDevs
    ) external onlyOwner contractNotLocked {
        if (amountMintedByDevs > newAmountForDevs) {
            revert Launchpeg__MaxSupplyForDevReached();
        }

        amountForDevs = newAmountForDevs;
        emit AmountForDevsSet(newAmountForDevs);
    }

    function setAmountForPreMint(
        uint256 newAmountForPreMint
    ) external onlyOwner contractNotLocked {
        if (amountMintedDuringPreMint > newAmountForPreMint) {
            revert Launchpeg__MaxSupplyReached();
        }

        amountForPreMint = newAmountForPreMint;
        emit AmountForPreMintSet(newAmountForPreMint);
    }

    function setPreMintPrice(
        uint256 newPreMintPrice
    ) external onlyOwner contractNotLocked {
        if (newPreMintPrice > publicSalePrice)
            revert Launchpeg__InvalidAllowlistPrice();

        preMintPrice = newPreMintPrice;
        emit PreMintPriceSet(newPreMintPrice);
    }

    function setPublicSalePrice(
        uint256 newPublicSalePrice
    ) external onlyOwner contractNotLocked {
        if (newPublicSalePrice < preMintPrice)
            revert Launchpeg__InvalidAllowlistPrice();

        publicSalePrice = newPublicSalePrice;
        emit PublicSalePriceSet(newPublicSalePrice);
    }

    function setCollectionSize(
        uint256 newCollectionSize
    ) external onlyOwner contractNotLocked {
        if (
            newCollectionSize < amountForDevs + amountForPreMint ||
            newCollectionSize <
            amountMintedDuringPreMint +
                amountMintedDuringPublicSale +
                amountForDevs
        ) revert Launchpeg__LargerCollectionSizeNeeded();

        collectionSize = newCollectionSize;
        emit CollectionSizeSet(newCollectionSize);
    }

    function setMaxPerAddressDuringMint(
        uint256 newMaxAmountPerUser
    ) external onlyOwner contractNotLocked {
        maxPerAddressDuringMint = newMaxAmountPerUser;
        emit MaxPerAddressDuringMintSet(newMaxAmountPerUser);
    }

    function _availableSupply() internal view returns (uint256) {
        return
            collectionSize -
            amountMintedDuringPreMint -
            amountMintedDuringPublicSale -
            amountForDevs;
    }

    function _mint(address to, uint256 amount) internal {
        numberMinted[to] += amount;

        uint256 tokenAmount = _tokenSet.length;
        uint256[] memory amounts = new uint256[](tokenAmount);
        for (uint i = 0; i < tokenAmount; i++) {
            amounts[i] = amount;
        }

        _mintBatch(to, _tokenSet, amounts, "");
    }
}
