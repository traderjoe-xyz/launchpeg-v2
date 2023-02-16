// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "./LaunchpegErrors.sol";
import {IBatchReveal} from "./interfaces/IBatchReveal.sol";
import {IBaseLaunchpeg} from "./interfaces/IBaseLaunchpeg.sol";
import {IFlatLaunchpeg} from "./interfaces/IFlatLaunchpeg.sol";
import {ILaunchpeg} from "./interfaces/ILaunchpeg.sol";
import {ERC1155LaunchpegBase} from "./ERC1155LaunchpegBase.sol";
import {ERC1155SingleBundle} from "./ERC1155SingleBundle.sol";
import {ILaunchpegFactory} from "./interfaces/ILaunchpegFactory.sol";
import {IPendingOwnableUpgradeable} from "./interfaces/IPendingOwnableUpgradeable.sol";
import {ISafePausableUpgradeable} from "./interfaces/ISafePausableUpgradeable.sol";
import {SafeAccessControlEnumerableUpgradeable} from "./utils/SafeAccessControlEnumerableUpgradeable.sol";

/// @title Launchpeg Factory
/// @author Trader Joe
/// @notice Factory that creates Launchpeg contracts
contract LaunchpegFactory is
    ILaunchpegFactory,
    Initializable,
    SafeAccessControlEnumerableUpgradeable
{
    event LaunchpegCreated(
        address indexed launchpeg,
        string name,
        string symbol,
        address indexed projectOwner,
        address indexed royaltyReceiver,
        uint256 maxPerAddressDuringMint,
        uint256 collectionSize,
        uint256 amountForAuction,
        uint256 amountForAllowlist,
        uint256 amountForDevs
    );

    event FlatLaunchpegCreated(
        address indexed flatLaunchpeg,
        string name,
        string symbol,
        address indexed projectOwner,
        address indexed royaltyReceiver,
        uint256 maxPerAddressDuringMint,
        uint256 collectionSize,
        uint256 amountForDevs,
        uint256 amountForAllowlist
    );

    event ERC1155SingleBundleCreated(address indexed erc1155SingleBundle);
    event ProxyAdminFor1155Created(address indexed proxyAdmin);

    event SetLaunchpegImplementation(address indexed launchpegImplementation);
    event SetFlatLaunchpegImplementation(
        address indexed flatLaunchpegImplementation
    );
    event Set1155SingleBundleImplementation(
        address indexed erc1155SingleBundleImplementation
    );
    event SetBatchReveal(address indexed batchReveal);
    event SetDefaultJoeFeePercent(uint256 joeFeePercent);
    event SetDefaultJoeFeeCollector(address indexed joeFeeCollector);

    bytes32 public constant override LAUNCHPEG_PAUSER_ROLE =
        keccak256("LAUNCHPEG_PAUSER_ROLE");

    /// @notice Launchpeg contract to be cloned
    address public override launchpegImplementation;
    /// @notice FlatLaunchpeg contract to be cloned
    address public override flatLaunchpegImplementation;

    /// @notice Default fee percentage
    /// @dev In basis points e.g 100 for 1%
    uint256 public override joeFeePercent;
    /// @notice Default fee collector
    address public override joeFeeCollector;

    /// @notice Checks if an address is stored as a Launchpeg, by type of Launchpeg
    mapping(uint256 => mapping(address => bool)) public override isLaunchpeg;
    /// @notice Launchpegs address list by type of Launchpeg
    mapping(uint256 => address[]) public override allLaunchpegs;

    /// @notice Batch reveal address
    address public override batchReveal;

    address public erc1155SingleBundleImplementation;

    /// @notice Initializes the Launchpeg factory
    /// @dev Uses clone factory pattern to save space
    /// @param _launchpegImplementation Launchpeg contract to be cloned
    /// @param _flatLaunchpegImplementation FlatLaunchpeg contract to be cloned
    /// @param _erc1155SingleBundleImplementation ERC1155SingleBundle contract to be cloned
    /// @param _batchReveal Batch reveal address
    /// @param _joeFeePercent Default fee percentage
    /// @param _joeFeeCollector Default fee collector
    function initialize(
        address _launchpegImplementation,
        address _flatLaunchpegImplementation,
        address _erc1155SingleBundleImplementation,
        address _batchReveal,
        uint256 _joeFeePercent,
        address _joeFeeCollector
    ) public initializer {
        __SafeAccessControlEnumerable_init();

        if (_launchpegImplementation == address(0)) {
            revert LaunchpegFactory__InvalidImplementation();
        }
        if (_flatLaunchpegImplementation == address(0)) {
            revert LaunchpegFactory__InvalidImplementation();
        }
        if (_erc1155SingleBundleImplementation == address(0)) {
            revert LaunchpegFactory__InvalidImplementation();
        }
        if (_batchReveal == address(0)) {
            revert LaunchpegFactory__InvalidBatchReveal();
        }
        if (_joeFeePercent > 10_000) {
            revert Launchpeg__InvalidPercent();
        }
        if (_joeFeeCollector == address(0)) {
            revert Launchpeg__InvalidJoeFeeCollector();
        }

        launchpegImplementation = _launchpegImplementation;
        flatLaunchpegImplementation = _flatLaunchpegImplementation;
        erc1155SingleBundleImplementation = _erc1155SingleBundleImplementation;
        batchReveal = _batchReveal;
        joeFeePercent = _joeFeePercent;
        joeFeeCollector = _joeFeeCollector;
    }

    /// @notice Returns the number of Launchpegs
    /// @param _launchpegType Type of Launchpeg to consider
    /// @return LaunchpegNumber The number of Launchpegs ever created
    function numLaunchpegs(
        uint256 _launchpegType
    ) external view override returns (uint256) {
        return allLaunchpegs[_launchpegType].length;
    }

    /// @notice Launchpeg creation
    /// @param _name ERC721 name
    /// @param _symbol ERC721 symbol
    /// @param _projectOwner The project owner
    /// @param _royaltyReceiver Royalty fee collector
    /// @param _maxPerAddressDuringMint Max amount of NFTs an address can mint in public phases
    /// @param _collectionSize The collection size (e.g 10000)
    /// @param _amountForAuction Amount of NFTs available for the auction (e.g 8000)
    /// @param _amountForAllowlist Amount of NFTs available for the allowlist mint (e.g 1000)
    /// @param _amountForDevs Amount of NFTs reserved for `projectOwner` (e.g 200)
    /// @param _enableBatchReveal Flag to enable batch reveal for the collection
    /// @return launchpeg New Launchpeg address
    function createLaunchpeg(
        string memory _name,
        string memory _symbol,
        address _projectOwner,
        address _royaltyReceiver,
        uint256 _maxPerAddressDuringMint,
        uint256 _collectionSize,
        uint256 _amountForAuction,
        uint256 _amountForAllowlist,
        uint256 _amountForDevs,
        bool _enableBatchReveal
    ) external override onlyOwner returns (address) {
        address launchpeg = Clones.clone(launchpegImplementation);

        isLaunchpeg[0][launchpeg] = true;
        allLaunchpegs[0].push(launchpeg);

        {
            IBaseLaunchpeg.CollectionData memory collectionData = IBaseLaunchpeg
                .CollectionData({
                    name: _name,
                    symbol: _symbol,
                    batchReveal: _enableBatchReveal ? batchReveal : address(0),
                    maxPerAddressDuringMint: _maxPerAddressDuringMint,
                    collectionSize: _collectionSize,
                    amountForDevs: _amountForDevs,
                    amountForAuction: _amountForAuction,
                    amountForAllowlist: _amountForAllowlist
                });
            IBaseLaunchpeg.CollectionOwnerData memory ownerData = IBaseLaunchpeg
                .CollectionOwnerData({
                    owner: msg.sender,
                    projectOwner: _projectOwner,
                    royaltyReceiver: _royaltyReceiver,
                    joeFeeCollector: joeFeeCollector,
                    joeFeePercent: joeFeePercent
                });
            ILaunchpeg(launchpeg).initialize(collectionData, ownerData);
        }

        emit LaunchpegCreated(
            launchpeg,
            _name,
            _symbol,
            _projectOwner,
            _royaltyReceiver,
            _maxPerAddressDuringMint,
            _collectionSize,
            _amountForAuction,
            _amountForAllowlist,
            _amountForDevs
        );

        return launchpeg;
    }

    /// @notice FlatLaunchpeg creation
    /// @param _name ERC721 name
    /// @param _symbol ERC721 symbol
    /// @param _projectOwner The project owner
    /// @param _royaltyReceiver Royalty fee collector
    /// @param _maxPerAddressDuringMint Max amount of NFTs an address can mint in public phases
    /// @param _collectionSize The collection size (e.g 10000)
    /// @param _amountForDevs Amount of NFTs reserved for `projectOwner` (e.g 200)
    /// @param _amountForAllowlist Amount of NFTs available for the allowlist mint (e.g 1000)
    /// @param _enableBatchReveal Flag to enable batch reveal for the collection
    /// @return flatLaunchpeg New FlatLaunchpeg address
    function createFlatLaunchpeg(
        string memory _name,
        string memory _symbol,
        address _projectOwner,
        address _royaltyReceiver,
        uint256 _maxPerAddressDuringMint,
        uint256 _collectionSize,
        uint256 _amountForDevs,
        uint256 _amountForAllowlist,
        bool _enableBatchReveal
    ) external override onlyOwner returns (address) {
        address flatLaunchpeg = Clones.clone(flatLaunchpegImplementation);

        isLaunchpeg[1][flatLaunchpeg] = true;
        allLaunchpegs[1].push(flatLaunchpeg);

        {
            IBaseLaunchpeg.CollectionData memory collectionData = IBaseLaunchpeg
                .CollectionData({
                    name: _name,
                    symbol: _symbol,
                    batchReveal: _enableBatchReveal ? batchReveal : address(0),
                    maxPerAddressDuringMint: _maxPerAddressDuringMint,
                    collectionSize: _collectionSize,
                    amountForDevs: _amountForDevs,
                    // set 0 auction amount for FlatLaunchpeg
                    amountForAuction: 0,
                    amountForAllowlist: _amountForAllowlist
                });
            IBaseLaunchpeg.CollectionOwnerData memory ownerData = IBaseLaunchpeg
                .CollectionOwnerData({
                    owner: msg.sender,
                    projectOwner: _projectOwner,
                    royaltyReceiver: _royaltyReceiver,
                    joeFeeCollector: joeFeeCollector,
                    joeFeePercent: joeFeePercent
                });
            IFlatLaunchpeg(flatLaunchpeg).initialize(collectionData, ownerData);
        }

        emit FlatLaunchpegCreated(
            flatLaunchpeg,
            _name,
            _symbol,
            _projectOwner,
            _royaltyReceiver,
            _maxPerAddressDuringMint,
            _collectionSize,
            _amountForDevs,
            _amountForAllowlist
        );

        return flatLaunchpeg;
    }

    function create1155SingleToken(
        string calldata name,
        string calldata symbol,
        address royaltyReceiver,
        uint256 maxPerAddressDuringMint,
        uint256 collectionSize,
        uint256 amountForDevs,
        uint256 amountForPreMint,
        uint256[] calldata tokenSet,
        bool isUpgradeable
    ) external onlyOwner returns (address) {
        // Packing data to avoid stack too deep error
        ERC1155LaunchpegBase.InitData memory initData = ERC1155LaunchpegBase
            .InitData({
                owner: msg.sender,
                collectionName: name,
                collectionSymbol: symbol,
                royaltyReceiver: royaltyReceiver,
                joeFeePercent: joeFeePercent
            });

        address launchpeg;
        if (isUpgradeable) {
            bytes memory data = abi.encodeWithSelector(
                ERC1155SingleBundle.initialize.selector,
                initData,
                collectionSize,
                amountForDevs,
                amountForPreMint,
                maxPerAddressDuringMint,
                tokenSet
            );

            ProxyAdmin proxyAdmin = new ProxyAdmin();

            TransparentUpgradeableProxy launchpegProxy = new TransparentUpgradeableProxy(
                    erc1155SingleBundleImplementation,
                    address(proxyAdmin),
                    data
                );

            proxyAdmin.transferOwnership(msg.sender);

            launchpeg = address(launchpegProxy);

            emit ProxyAdminFor1155Created(address(proxyAdmin));
        } else {
            launchpeg = Clones.clone(erc1155SingleBundleImplementation);
            ERC1155SingleBundle(launchpeg).initialize(
                initData,
                collectionSize,
                amountForDevs,
                amountForPreMint,
                maxPerAddressDuringMint,
                tokenSet
            );
        }

        isLaunchpeg[2][launchpeg] = true;
        allLaunchpegs[2].push(launchpeg);

        emit ERC1155SingleBundleCreated(launchpeg);

        return launchpeg;
    }

    /// @notice Set address for launchpegImplementation
    /// @param _launchpegImplementation New launchpegImplementation
    function setLaunchpegImplementation(
        address _launchpegImplementation
    ) external override onlyOwner {
        if (_launchpegImplementation == address(0)) {
            revert LaunchpegFactory__InvalidImplementation();
        }

        launchpegImplementation = _launchpegImplementation;
        emit SetLaunchpegImplementation(_launchpegImplementation);
    }

    /// @notice Set address for flatLaunchpegImplementation
    /// @param _flatLaunchpegImplementation New flatLaunchpegImplementation
    function setFlatLaunchpegImplementation(
        address _flatLaunchpegImplementation
    ) external override onlyOwner {
        if (_flatLaunchpegImplementation == address(0)) {
            revert LaunchpegFactory__InvalidImplementation();
        }

        flatLaunchpegImplementation = _flatLaunchpegImplementation;
        emit SetFlatLaunchpegImplementation(_flatLaunchpegImplementation);
    }

    function setERC1155SingleBundle(
        address _erc1155SingleBundleImplementation
    ) external onlyOwner {
        if (_erc1155SingleBundleImplementation == address(0)) {
            revert LaunchpegFactory__InvalidImplementation();
        }

        erc1155SingleBundleImplementation = _erc1155SingleBundleImplementation;
        emit Set1155SingleBundleImplementation(
            _erc1155SingleBundleImplementation
        );
    }

    /// @notice Set batch reveal address
    /// @param _batchReveal New batch reveal
    function setBatchReveal(address _batchReveal) external override onlyOwner {
        if (_batchReveal == address(0)) {
            revert LaunchpegFactory__InvalidBatchReveal();
        }

        batchReveal = _batchReveal;
        emit SetBatchReveal(_batchReveal);
    }

    /// @notice Set percentage of protocol fees
    /// @param _joeFeePercent New joeFeePercent
    function setDefaultJoeFeePercent(
        uint256 _joeFeePercent
    ) external override onlyOwner {
        if (_joeFeePercent > 10_000) {
            revert Launchpeg__InvalidPercent();
        }

        joeFeePercent = _joeFeePercent;
        emit SetDefaultJoeFeePercent(_joeFeePercent);
    }

    /// @notice Set default address to collect protocol fees
    /// @param _joeFeeCollector New collector address
    function setDefaultJoeFeeCollector(
        address _joeFeeCollector
    ) external override onlyOwner {
        if (_joeFeeCollector == address(0)) {
            revert Launchpeg__InvalidJoeFeeCollector();
        }

        joeFeeCollector = _joeFeeCollector;
        emit SetDefaultJoeFeeCollector(_joeFeeCollector);
    }

    /// @notice Grants LAUNCHPEG_PAUSER_ROLE to an address. The
    /// address will be able to pause any Launchpeg collection
    /// @param _pauser Pauser address
    function addLaunchpegPauser(address _pauser) external override {
        grantRole(LAUNCHPEG_PAUSER_ROLE, _pauser);
    }

    /// @notice Revokes LAUNCHPEG_PAUSER_ROLE from an address. The
    /// address will not be able to pause any Launchpeg collection
    /// @param _pauser Pauser address
    function removeLaunchpegPauser(address _pauser) external override {
        revokeRole(LAUNCHPEG_PAUSER_ROLE, _pauser);
    }

    /// @notice Pause specified Launchpeg
    /// @param _launchpeg Launchpeg address
    function pauseLaunchpeg(
        address _launchpeg
    ) external override onlyOwnerOrRole(LAUNCHPEG_PAUSER_ROLE) {
        ISafePausableUpgradeable(_launchpeg).pause();
    }
}
