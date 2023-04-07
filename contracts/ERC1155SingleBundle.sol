// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./LaunchpegErrors.sol";
import {ERC1155LaunchpegBase} from "./ERC1155LaunchpegBase.sol";
import {IERC1155LaunchpegSingleBundle, IERC1155LaunchpegBase} from "./interfaces/IERC1155LaunchpegSingleBundle.sol";

contract ERC1155SingleBundle is
    IERC1155LaunchpegSingleBundle,
    ERC1155LaunchpegBase
{
    using SafeCast for uint256;

    /// @notice The collection size
    uint128 public override collectionSize;
    /// @notice The maximum number of tokens that can be minted per address
    uint128 public override maxPerAddressDuringMint;

    /// @notice The number of tokens reserved for the devs
    uint128 public override amountForDevs;
    /// @notice The number of tokens minted for the devs
    uint128 public override amountMintedByDevs;

    /// @notice The price of a token during the pre-mint
    uint128 public override preMintPrice;
    /// @notice The start time of the pre-mint
    uint128 public override preMintStartTime;

    /// @notice The number of tokens reserved for the pre-mint
    uint128 public override amountForPreMint;
    /// @notice The number of tokens minted for the pre-mint
    uint128 public override amountMintedDuringPreMint;
    /// @notice The number of tokens claimed for the pre-mint
    uint256 public override amountClaimedDuringPreMint;

    /// @notice The price of a token during the public sale
    uint128 public override publicSalePrice;
    /// @notice The start time of the public sale
    uint128 public override publicSaleStartTime;
    /// @notice The end time of the public sale
    uint128 public override publicSaleEndTime;
    /// @notice The number of tokens minted during the public sale
    uint128 public override amountMintedDuringPublicSale;

    /// @notice The number of tokens allowed to be minted per address during the pre-mint
    mapping(address => uint256) public override allowlist;
    /// @notice The number of tokens minted per address
    mapping(address => uint256) public override numberMinted;

    uint256[] private _tokenSet;
    PreMintDataSet private _pendingPreMints;

    modifier isEOA() {
        if (tx.origin != msg.sender) {
            revert Launchpeg__Unauthorized();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param initData The data used to initialize the base contract
    /// @param initialMaxSupply The maximum number of tokens that can be minted
    /// @param initialAmountForDevs The number of tokens reserved for the devs
    /// @param initialAmountForPreMint The number of tokens reserved for the pre-mint
    /// @param initialMaxPerAddressDuringMint The maximum number of tokens that can be minted per address
    /// @param initialTokenSet The token set
    function initialize(
        InitData calldata initData,
        uint256 initialMaxSupply,
        uint256 initialAmountForDevs,
        uint256 initialAmountForPreMint,
        uint256 initialMaxPerAddressDuringMint,
        uint256[] calldata initialTokenSet
    ) external override initializer {
        __ERC1155LaunchpegBase_init(initData);

        if (amountForDevs + amountForPreMint > initialMaxSupply) {
            revert Launchpeg__LargerCollectionSizeNeeded();
        }

        collectionSize = initialMaxSupply.toUint128();
        maxPerAddressDuringMint = initialMaxPerAddressDuringMint.toUint128();

        amountForDevs = initialAmountForDevs.toUint128();
        amountForPreMint = initialAmountForPreMint.toUint128();
        _tokenSet = initialTokenSet;
    }

    /// @notice Initializes the phases
    /// @param initialPreMintStartTime The start time of the pre-mint
    /// @param initialPublicSaleStartTime The start time of the public sale
    /// @param initialPublicSaleEndTime The end time of the public sale
    /// @param initialPreMintPrice The price of a token during the pre-mint
    /// @param initialPublicSalePrice The price of a token during the public sale
    function initializePhases(
        uint256 initialPreMintStartTime,
        uint256 initialPublicSaleStartTime,
        uint256 initialPublicSaleEndTime,
        uint256 initialPreMintPrice,
        uint256 initialPublicSalePrice
    ) external override onlyOwner atPhase(Phase.NotStarted) {
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

        preMintPrice = initialPreMintPrice.toUint128();
        publicSalePrice = initialPublicSalePrice.toUint128();
        preMintStartTime = initialPreMintStartTime.toUint128();

        publicSaleStartTime = initialPublicSaleStartTime.toUint128();
        publicSaleEndTime = initialPublicSaleEndTime.toUint128();

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

    /// @notice Returns the current token set
    /// @return The current token set
    function tokenSet() external view override returns (uint256[] memory) {
        return _tokenSet;
    }

    /// @notice Returns the current phase
    /// @return The current phase
    function currentPhase()
        public
        view
        override(ERC1155LaunchpegBase, IERC1155LaunchpegBase)
        returns (Phase)
    {
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

    /// @notice Returns the amount of users that still need to claim their tokens
    /// @return The amount of users that still need to claim their tokens
    function amountOfUsersWaitingForPremintClaim()
        external
        view
        override
        returns (uint256)
    {
        return _pendingPreMints.preMintDataArr.length;
    }

    /// @notice Returns the amount of tokens that still need to be claimed by a user
    /// @param user The user
    /// @return The amount of tokens that still need to be claimed
    function userPendingPreMints(
        address user
    ) public view override returns (uint256) {
        uint256 userIndex = _pendingPreMints.indexes[user];

        if (userIndex == 0) {
            return 0;
        }

        return _pendingPreMints.preMintDataArr[userIndex - 1].quantity;
    }

    /// @notice Returns true if the interface is supported
    /// @param interfaceId The interface ID
    /// @return isSupported True if the interface is supported
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IERC1155LaunchpegSingleBundle).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Mints tokens for the devs
    /// @param amount The amount of tokens to mint
    function devMint(
        uint256 amount
    )
        external
        override
        whenNotPaused
        onlyOwnerOrRole(PROJECT_OWNER_ROLE)
        nonReentrant
    {
        uint256 amountAlreadyMinted = amountMintedByDevs;

        if (amountAlreadyMinted + amount > amountForDevs)
            revert Launchpeg__MaxSupplyForDevReached();

        amountMintedByDevs = (amountAlreadyMinted + amount).toUint128();

        _mint(msg.sender, amount);

        emit DevMint(msg.sender, amount);
    }

    /// @notice Buys tokens for the pre-mint
    /// @param amount The amount of tokens to mint
    function preMint(
        uint96 amount
    )
        external
        payable
        override
        whenNotPaused
        atPhase(Phase.PreMint)
        nonReentrant
    {
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

        amountMintedDuringPreMint = (amountAlreadyPreMinted + amount)
            .toUint128();
        allowlist[msg.sender] = userAllowlistAmount - amount;

        uint256 totalPrice = uint256(preMintPrice) * uint256(amount);
        _refundIfOver(totalPrice);

        emit PreMint(msg.sender, amount, totalPrice);
    }

    /// @notice Mints the tokens bought during pre-mint
    function claimPremint() external override whenNotPaused nonReentrant {
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

    /// @notice Mints the tokens bought during pre-mint
    /// @param numberOfClaims The number of claims to do
    function batchClaimPreMint(
        uint256 numberOfClaims
    ) external override whenNotPaused nonReentrant {
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

    /// @notice Buys tokens during public sale
    /// @param amount The amount of tokens to mint
    function publicSaleMint(
        uint256 amount
    )
        external
        payable
        override
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

        amountMintedDuringPublicSale += amount.toUint128();

        _mint(msg.sender, amount);
        _refundIfOver(publicSalePrice * amount);
    }

    /// @notice Updates the token set
    /// @param newTokenSet The new token set
    function updateTokenSet(
        uint256[] calldata newTokenSet
    ) external override onlyOwner {
        _tokenSet = newTokenSet;
        emit TokenSetUpdated(newTokenSet);
    }

    /// @notice Updates the allowlist
    /// @param addresses The addresses to update
    /// @param amounts The amounts to update
    function seedAllowlist(
        address[] calldata addresses,
        uint256[] calldata amounts
    ) external override onlyOwner {
        uint256 addressesLength = addresses.length;
        if (addressesLength != amounts.length) {
            revert Launchpeg__WrongAddressesAndNumSlotsLength();
        }
        for (uint256 i; i < addressesLength; i++) {
            allowlist[addresses[i]] = amounts[i];
        }

        emit AllowlistSeeded();
    }

    /// @notice Sets a new pre-mint start time
    /// @param newPreMintStartTime The new pre-mint start time
    function setPreMintStartTime(
        uint256 newPreMintStartTime
    ) external override onlyOwner contractNotLocked {
        if (newPreMintStartTime > publicSaleStartTime)
            revert Launchpeg__InvalidPhases();

        preMintStartTime = newPreMintStartTime.toUint128();
        emit PreMintStartTimeSet(newPreMintStartTime);
    }

    /// @notice Sets a new public sale start time
    /// @param newPublicSaleStartTime The new public sale start time
    function setPublicSaleStartTime(
        uint256 newPublicSaleStartTime
    ) external override onlyOwner contractNotLocked {
        if (newPublicSaleStartTime > publicSaleEndTime)
            revert Launchpeg__InvalidPhases();

        publicSaleStartTime = newPublicSaleStartTime.toUint128();
        emit PublicSaleStartTimeSet(newPublicSaleStartTime);
    }

    /// @notice Sets a new public sale end time
    /// @param newPublicSaleEndTime The new public sale end time
    function setPublicSaleEndTime(
        uint256 newPublicSaleEndTime
    ) external override onlyOwner contractNotLocked {
        if (newPublicSaleEndTime < publicSaleStartTime)
            revert Launchpeg__InvalidPhases();

        publicSaleEndTime = newPublicSaleEndTime.toUint128();
        emit PublicSaleEndTimeSet(newPublicSaleEndTime);
    }

    /// @notice Sets a new amount for devs
    /// @param newAmountForDevs The new amount for devs
    function setAmountForDevs(
        uint256 newAmountForDevs
    ) external override onlyOwner contractNotLocked {
        if (amountMintedByDevs > newAmountForDevs) {
            revert Launchpeg__MaxSupplyForDevReached();
        }

        amountForDevs = newAmountForDevs.toUint128();
        emit AmountForDevsSet(newAmountForDevs);
    }

    /// @notice Sets a new amount for pre-mint
    /// @param newAmountForPreMint The new amount for pre-mint
    function setAmountForPreMint(
        uint256 newAmountForPreMint
    ) external override onlyOwner contractNotLocked {
        if (amountMintedDuringPreMint > newAmountForPreMint) {
            revert Launchpeg__MaxSupplyReached();
        }

        amountForPreMint = newAmountForPreMint.toUint128();
        emit AmountForPreMintSet(newAmountForPreMint);
    }

    /// @notice Sets a new pre-mint price
    /// @param newPreMintPrice The new pre-mint price
    function setPreMintPrice(
        uint256 newPreMintPrice
    ) external override onlyOwner contractNotLocked {
        if (newPreMintPrice > publicSalePrice)
            revert Launchpeg__InvalidAllowlistPrice();

        preMintPrice = newPreMintPrice.toUint128();
        emit PreMintPriceSet(newPreMintPrice);
    }

    /// @notice Sets a new public sale price
    /// @param newPublicSalePrice The new public sale price
    function setPublicSalePrice(
        uint256 newPublicSalePrice
    ) external override onlyOwner contractNotLocked {
        if (newPublicSalePrice < preMintPrice)
            revert Launchpeg__InvalidAllowlistPrice();

        publicSalePrice = newPublicSalePrice.toUint128();
        emit PublicSalePriceSet(newPublicSalePrice);
    }

    /// @notice Sets a new collection size
    /// @param newCollectionSize The new collection size
    function setCollectionSize(
        uint256 newCollectionSize
    ) external override onlyOwner contractNotLocked {
        if (
            newCollectionSize < amountForDevs + amountForPreMint ||
            newCollectionSize <
            amountMintedDuringPreMint +
                amountMintedDuringPublicSale +
                amountForDevs
        ) revert Launchpeg__LargerCollectionSizeNeeded();

        collectionSize = newCollectionSize.toUint128();
        emit CollectionSizeSet(newCollectionSize);
    }

    /// @notice Sets a new max per address during mint
    /// @param newMaxAmountPerUser The new max per address during mint
    function setMaxPerAddressDuringMint(
        uint256 newMaxAmountPerUser
    ) external override onlyOwner contractNotLocked {
        maxPerAddressDuringMint = newMaxAmountPerUser.toUint128();
        emit MaxPerAddressDuringMintSet(newMaxAmountPerUser);
    }

    /// @dev Returns the available supply
    /// @return The available supply
    function _availableSupply() internal view returns (uint256) {
        return
            collectionSize -
            amountMintedDuringPreMint -
            amountMintedDuringPublicSale -
            amountForDevs;
    }

    /// @dev Mints every token in the token set
    /// @param to The address to mint to
    /// @param amount The amount of token sets to mint
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
