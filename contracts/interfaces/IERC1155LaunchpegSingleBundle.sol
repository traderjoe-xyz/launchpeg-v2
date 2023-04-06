// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IERC1155LaunchpegBase} from "./IERC1155LaunchpegBase.sol";

interface IERC1155LaunchpegSingleBundle {
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

    struct PreMintData {
        address sender;
        uint96 quantity;
    }

    struct PreMintDataSet {
        PreMintData[] preMintDataArr;
        mapping(address => uint256) indexes;
    }

    function collectionSize() external view returns (uint128);

    function maxPerAddressDuringMint() external view returns (uint128);

    function amountForDevs() external view returns (uint128);

    function amountMintedByDevs() external view returns (uint128);

    function preMintPrice() external view returns (uint128);

    function preMintStartTime() external view returns (uint128);

    function amountForPreMint() external view returns (uint128);

    function amountMintedDuringPreMint() external view returns (uint128);

    function amountClaimedDuringPreMint() external view returns (uint256);

    function publicSalePrice() external view returns (uint128);

    function publicSaleStartTime() external view returns (uint128);

    function publicSaleEndTime() external view returns (uint128);

    function amountMintedDuringPublicSale() external view returns (uint128);

    function allowlist(address account) external view returns (uint256);

    function numberMinted(address account) external view returns (uint256);

    function initialize(
        IERC1155LaunchpegBase.InitData calldata initData,
        uint256 initialMaxSupply,
        uint256 initialAmountForDevs,
        uint256 initialAmountForPreMint,
        uint256 initialMaxPerAddressDuringMint,
        uint256[] calldata initialTokenSet
    ) external;

    function initializePhases(
        uint256 initialPreMintStartTime,
        uint256 initialPublicSaleStartTime,
        uint256 initialPublicSaleEndTime,
        uint256 initialPreMintPrice,
        uint256 initialPublicSalePrice
    ) external;

    function tokenSet() external view returns (uint256[] memory);

    function amountOfUsersWaitingForPremintClaim()
        external
        view
        returns (uint256);

    function userPendingPreMints(
        address account
    ) external view returns (uint256);

    function devMint(uint256 quantity) external;

    function preMint(uint96 quantity) external payable;

    function claimPremint() external;

    function batchClaimPreMint(uint256 quantity) external;

    function publicSaleMint(uint256 quantity) external payable;

    function updateTokenSet(uint256[] calldata newTokenSet) external;

    function seedAllowlist(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external;

    function setPreMintStartTime(uint256 newPreMintStartTime) external;

    function setPublicSaleStartTime(uint256 newPublicSaleStartTime) external;

    function setPublicSaleEndTime(uint256 newPublicSaleEndTime) external;

    function setAmountForDevs(uint256 newAmountForDevs) external;

    function setAmountForPreMint(uint256 newAmountForPreMint) external;

    function setPreMintPrice(uint256 newPreMintPrice) external;

    function setPublicSalePrice(uint256 newPublicSalePrice) external;

    function setMaxPerAddressDuringMint(
        uint256 newMaxPerAddressDuringMint
    ) external;

    function setCollectionSize(uint256 newCollectionSize) external;
}
