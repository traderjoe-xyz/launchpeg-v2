// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/IAccessControlEnumerableUpgradeable.sol";

import "./interfaces/IBaseLaunchpeg.sol";
import "./interfaces/IBaseLaunchpegV1.sol";
import "./interfaces/IBatchReveal.sol";
import "./interfaces/IFlatLaunchpeg.sol";
import "./interfaces/ILaunchpeg.sol";
import "./interfaces/ILaunchpegFactory.sol";
import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";

error LaunchpegLens__InvalidContract();

/// @title Launchpeg Lens
/// @author Trader Joe
/// @notice Helper contract to fetch launchpegs data
contract LaunchpegLens {
    struct CollectionData {
        string name;
        string symbol;
        uint256 collectionSize;
        uint256 maxPerAddressDuringMint;
        uint256 totalSupply;
        string unrevealedURI;
        string baseURI;
    }

    struct LaunchpegData {
        ILaunchpeg.Phase currentPhase;
        uint256 amountForAuction;
        uint256 amountForAllowlist;
        uint256 amountForDevs;
        uint256 auctionSaleStartTime;
        uint256 preMintStartTime;
        uint256 allowlistStartTime;
        uint256 publicSaleStartTime;
        uint256 publicSaleEndTime;
        uint256 auctionStartPrice;
        uint256 auctionEndPrice;
        uint256 auctionSaleDuration;
        uint256 auctionDropInterval;
        uint256 auctionDropPerStep;
        uint256 allowlistDiscountPercent;
        uint256 publicSaleDiscountPercent;
        uint256 auctionPrice;
        uint256 allowlistPrice;
        uint256 publicSalePrice;
        uint256 lastAuctionPrice;
        uint256 amountMintedDuringAuction;
        uint256 amountMintedDuringPreMint;
        uint256 amountMintedDuringAllowlist;
        uint256 amountMintedDuringPublicSale;
    }

    struct FlatLaunchpegData {
        ILaunchpeg.Phase currentPhase;
        uint256 amountForAllowlist;
        uint256 amountForDevs;
        uint256 preMintStartTime;
        uint256 allowlistStartTime;
        uint256 publicSaleStartTime;
        uint256 publicSaleEndTime;
        uint256 allowlistPrice;
        uint256 salePrice;
        uint256 amountMintedDuringPreMint;
        uint256 amountMintedDuringAllowlist;
        uint256 amountMintedDuringPublicSale;
    }

    struct RevealData {
        uint256 revealBatchSize;
        uint256 lastTokenRevealed;
        uint256 revealStartTime;
        uint256 revealInterval;
    }

    struct UserData {
        uint256 balanceOf;
        uint256 numberMinted;
        uint256 numberMintedWithPreMint;
        uint256 allowanceForAllowlistMint;
    }

    struct ProjectOwnerData {
        address[] projectOwners;
        uint256 amountMintedByDevs;
        uint256 withdrawAVAXStartTime;
        uint256 launchpegBalanceAVAX;
    }

    /// Global struct that is returned by getAllLaunchpegs()
    struct LensData {
        address id;
        LaunchpegType launchType;
        CollectionData collectionData;
        LaunchpegData launchpegData;
        FlatLaunchpegData flatLaunchpegData;
        RevealData revealData;
        UserData userData;
        ProjectOwnerData projectOwnerData;
    }

    enum LaunchpegType {
        Unknown,
        Launchpeg,
        FlatLaunchpeg
    }

    enum LaunchpegVersion {
        Unknown,
        V1,
        V2
    }

    /// @notice LaunchpegFactory V1 address
    address public immutable launchpegFactoryV1;

    /// @notice LaunchpegFactory V2 address
    address public immutable launchpegFactoryV2;

    /// @notice BatchReveal address
    address public immutable batchReveal;

    /// @dev LaunchpegLens constructor
    /// @param _launchpegFactoryV1 LaunchpegFactory address V1
    /// @param _launchpegFactoryV2 LaunchpegFactory address V2
    /// @param _batchReveal BatchReveal address
    constructor(
        address _launchpegFactoryV1,
        address _launchpegFactoryV2,
        address _batchReveal
    ) {
        launchpegFactoryV1 = _launchpegFactoryV1;
        launchpegFactoryV2 = _launchpegFactoryV2;
        batchReveal = _batchReveal;
    }

    /// @notice Gets the type and version of Launchpeg
    /// @param _contract Contract address to consider
    /// @return LaunchpegType Type of Launchpeg implementation (Dutch Auction / Flat / Unknown)
    function getLaunchpegType(address _contract)
        public
        view
        returns (LaunchpegType, LaunchpegVersion)
    {
        if (ILaunchpegFactory(launchpegFactoryV1).isLaunchpeg(0, _contract)) {
            return (LaunchpegType.Launchpeg, LaunchpegVersion.V1);
        } else if (
            ILaunchpegFactory(launchpegFactoryV2).isLaunchpeg(0, _contract)
        ) {
            return (LaunchpegType.Launchpeg, LaunchpegVersion.V2);
        } else if (
            ILaunchpegFactory(launchpegFactoryV1).isLaunchpeg(1, _contract)
        ) {
            return (LaunchpegType.FlatLaunchpeg, LaunchpegVersion.V1);
        } else if (
            ILaunchpegFactory(launchpegFactoryV2).isLaunchpeg(1, _contract)
        ) {
            return (LaunchpegType.FlatLaunchpeg, LaunchpegVersion.V2);
        } else {
            return (LaunchpegType.Unknown, LaunchpegVersion.Unknown);
        }
    }

    /// @notice Fetch Launchpeg data by type and version
    /// @param _type Type of Launchpeg to consider (0 - Launchpeg, 1 - FlatLaunchpeg)
    /// @param _version Launchpeg version (1 or 2)
    /// @param _number Number of Launchpeg to fetch
    /// @param _limit Last Launchpeg index to fetch
    /// @param _user Address to consider for NFT balances and allowlist allocations
    /// @return LensDataList List of contracts datas, in descending order
    function getLaunchpegsByTypeAndVersion(
        uint8 _type,
        uint8 _version,
        uint256 _number,
        uint256 _limit,
        address _user
    ) external view returns (LensData[] memory) {
        // default to v2 unless v1 is specified
        ILaunchpegFactory factory = (_version == 1)
            ? ILaunchpegFactory(launchpegFactoryV1)
            : ILaunchpegFactory(launchpegFactoryV2);
        uint256 numLaunchpegs = factory.numLaunchpegs(_type);

        uint256 end = _limit > numLaunchpegs ? numLaunchpegs : _limit;
        uint256 start = _number > end ? 0 : end - _number;

        LensData[] memory LensDatas;
        LensDatas = new LensData[](end - start);

        for (uint256 i = 0; i < LensDatas.length; i++) {
            LensDatas[i] = getLaunchpegData(
                factory.allLaunchpegs(_type, end - 1 - i),
                _user
            );
        }

        return LensDatas;
    }

    /// @notice Fetch Launchpeg data from the provided address
    /// @param _launchpeg Contract address to consider
    /// @param _user Address to consider for NFT balances and allowlist allocations
    /// @return LensData Contract data
    function getLaunchpegData(address _launchpeg, address _user)
        public
        view
        returns (LensData memory)
    {
        (
            LaunchpegType launchType,
            LaunchpegVersion launchVersion
        ) = getLaunchpegType(_launchpeg);
        if (launchType == LaunchpegType.Unknown) {
            revert LaunchpegLens__InvalidContract();
        }

        LensData memory data;
        data.id = _launchpeg;
        data.launchType = launchType;
        data.collectionData = _getCollectionData(_launchpeg);
        data.projectOwnerData = _getProjectOwnerData(_launchpeg, launchVersion);
        data.revealData = _getBatchRevealData(_launchpeg, launchVersion);
        data.userData = _getUserData(_launchpeg, launchVersion, _user);

        if (data.launchType == LaunchpegType.Launchpeg) {
            data.launchpegData = _getLaunchpegData(_launchpeg, launchVersion);
        } else if (data.launchType == LaunchpegType.FlatLaunchpeg) {
            data.flatLaunchpegData = _getFlatLaunchpegData(
                _launchpeg,
                launchVersion
            );
        }

        return data;
    }

    /// @dev Fetches Launchpeg collection data
    /// @param _launchpeg Launchpeg address
    function _getCollectionData(address _launchpeg)
        private
        view
        returns (CollectionData memory data)
    {
        data.name = ERC721AUpgradeable(_launchpeg).name();
        data.symbol = ERC721AUpgradeable(_launchpeg).symbol();
        data.collectionSize = IBaseLaunchpeg(_launchpeg).collectionSize();
        data.maxPerAddressDuringMint = IBaseLaunchpeg(_launchpeg)
            .maxPerAddressDuringMint();
        data.totalSupply = ERC721AUpgradeable(_launchpeg).totalSupply();
        data.unrevealedURI = IBaseLaunchpeg(_launchpeg).unrevealedURI();
        data.baseURI = IBaseLaunchpeg(_launchpeg).baseURI();
    }

    /// @dev Fetches Launchpeg project owner data
    /// @param _launchpeg Launchpeg address
    /// @param launchVersion Launchpeg version
    function _getProjectOwnerData(
        address _launchpeg,
        LaunchpegVersion launchVersion
    ) private view returns (ProjectOwnerData memory data) {
        data.amountMintedByDevs = IBaseLaunchpeg(_launchpeg)
            .amountMintedByDevs();
        if (launchVersion == LaunchpegVersion.V2) {
            data.projectOwners = _getProjectOwners(_launchpeg);
            data.withdrawAVAXStartTime = IBaseLaunchpeg(_launchpeg)
                .withdrawAVAXStartTime();
            data.launchpegBalanceAVAX = _launchpeg.balance;
        }
    }

    /// @dev Fetches Launchpeg project owners. Only works for Launchpeg V2.
    /// @param _launchpeg Launchpeg address
    function _getProjectOwners(address _launchpeg)
        private
        view
        returns (address[] memory)
    {
        bytes32 role = IBaseLaunchpeg(_launchpeg).PROJECT_OWNER_ROLE();
        uint256 count = IAccessControlEnumerableUpgradeable(_launchpeg)
            .getRoleMemberCount(role);
        address[] memory projectOwners = new address[](count);
        for (uint256 i; i < count; i++) {
            projectOwners[i] = IAccessControlEnumerableUpgradeable(_launchpeg)
                .getRoleMember(role, i);
        }
        return projectOwners;
    }

    /// @dev Fetches Launchpeg data
    /// @param _launchpeg Launchpeg address
    /// @param launchVersion Launchpeg version
    function _getLaunchpegData(
        address _launchpeg,
        LaunchpegVersion launchVersion
    ) private view returns (LaunchpegData memory data) {
        ILaunchpeg lp = ILaunchpeg(_launchpeg);
        data.currentPhase = lp.currentPhase();
        data.amountForAuction = lp.amountForAuction();
        data.amountForAllowlist = lp.amountForAllowlist();
        data.amountForDevs = lp.amountForDevs();
        data.auctionSaleStartTime = lp.auctionSaleStartTime();
        data.allowlistStartTime = lp.allowlistStartTime();
        data.publicSaleStartTime = lp.publicSaleStartTime();
        data.auctionStartPrice = lp.auctionStartPrice();
        data.auctionEndPrice = lp.auctionEndPrice();
        data.auctionSaleDuration = lp.auctionSaleDuration();
        data.auctionDropInterval = lp.auctionDropInterval();
        data.auctionDropPerStep = lp.auctionDropPerStep();
        data.allowlistDiscountPercent = lp.allowlistDiscountPercent();
        data.publicSaleDiscountPercent = lp.publicSaleDiscountPercent();
        data.auctionPrice = lp.getAuctionPrice(data.auctionSaleStartTime);
        data.lastAuctionPrice = lp.lastAuctionPrice();
        data.amountMintedDuringAuction = lp.amountMintedDuringAuction();
        data.amountMintedDuringAllowlist = lp.amountMintedDuringAllowlist();
        data.amountMintedDuringPublicSale = lp.amountMintedDuringPublicSale();
        if (launchVersion == LaunchpegVersion.V1) {
            data.allowlistPrice = IBaseLaunchpegV1(_launchpeg)
                .getAllowlistPrice();
            data.publicSalePrice = IBaseLaunchpegV1(_launchpeg)
                .getPublicSalePrice();
        } else if (launchVersion == LaunchpegVersion.V2) {
            data.allowlistPrice = lp.allowlistPrice();
            data.publicSalePrice = lp.salePrice();
            data.preMintStartTime = lp.preMintStartTime();
            data.publicSaleEndTime = lp.publicSaleEndTime();
            data.amountMintedDuringPreMint = lp.amountMintedDuringPreMint();
        }
    }

    /// @dev Fetches FlatLaunchpeg data
    /// @param _launchpeg Launchpeg address
    /// @param launchVersion Launchpeg version
    function _getFlatLaunchpegData(
        address _launchpeg,
        LaunchpegVersion launchVersion
    ) private view returns (FlatLaunchpegData memory data) {
        IFlatLaunchpeg lp = IFlatLaunchpeg(_launchpeg);
        data.currentPhase = lp.currentPhase();
        data.amountForAllowlist = lp.amountForAllowlist();
        data.amountForDevs = lp.amountForDevs();
        data.allowlistStartTime = lp.allowlistStartTime();
        data.publicSaleStartTime = lp.publicSaleStartTime();
        data.allowlistPrice = lp.allowlistPrice();
        data.salePrice = lp.salePrice();
        data.amountMintedDuringAllowlist = lp.amountMintedDuringAllowlist();
        data.amountMintedDuringPublicSale = lp.amountMintedDuringPublicSale();
        if (launchVersion == LaunchpegVersion.V2) {
            data.preMintStartTime = lp.preMintStartTime();
            data.publicSaleEndTime = lp.publicSaleEndTime();
            data.amountMintedDuringPreMint = lp.amountMintedDuringPreMint();
        }
    }

    /// @dev Fetches batch reveal data
    /// @param _launchpeg Launchpeg address
    /// @param launchVersion Launchpeg version
    function _getBatchRevealData(
        address _launchpeg,
        LaunchpegVersion launchVersion
    ) private view returns (RevealData memory data) {
        if (launchVersion == LaunchpegVersion.V1) {
            IBaseLaunchpegV1 br = IBaseLaunchpegV1(_launchpeg);
            data.revealBatchSize = br.revealBatchSize();
            data.revealStartTime = br.revealStartTime();
            data.revealInterval = br.revealInterval();
            data.lastTokenRevealed = br.lastTokenRevealed();
        } else if (launchVersion == LaunchpegVersion.V2) {
            (
                ,
                ,
                uint256 revealBatchSize,
                uint256 revealStartTime,
                uint256 revealInterval
            ) = IBatchReveal(batchReveal).launchpegToConfig(_launchpeg);
            data.revealBatchSize = revealBatchSize;
            data.revealStartTime = revealStartTime;
            data.revealInterval = revealInterval;
            data.lastTokenRevealed = IBatchReveal(batchReveal)
                .launchpegToLastTokenReveal(_launchpeg);
        }
    }

    /// @dev Fetches Launchpeg user data
    /// @param _launchpeg Launchpeg address
    /// @param launchVersion Launchpeg version
    function _getUserData(
        address _launchpeg,
        LaunchpegVersion launchVersion,
        address _user
    ) private view returns (UserData memory data) {
        if (_user != address(0)) {
            data.balanceOf = ERC721AUpgradeable(_launchpeg).balanceOf(_user);
            data.numberMinted = IBaseLaunchpeg(_launchpeg).numberMinted(_user);
            data.allowanceForAllowlistMint = IBaseLaunchpeg(_launchpeg)
                .allowlist(_user);
            if (launchVersion == LaunchpegVersion.V2) {
                data.numberMintedWithPreMint = IBaseLaunchpeg(_launchpeg)
                    .numberMintedWithPreMint(_user);
            }
        }
    }
}
