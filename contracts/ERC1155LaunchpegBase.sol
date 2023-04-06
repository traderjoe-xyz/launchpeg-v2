// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {IOperatorFilterRegistry} from "operator-filter-registry/src/IOperatorFilterRegistry.sol";

import "./LaunchpegErrors.sol";
import {SafePausableUpgradeable} from "./utils/SafePausableUpgradeable.sol";

import {IERC1155LaunchpegBase} from "./interfaces/IERC1155LaunchpegBase.sol";

abstract contract ERC1155LaunchpegBase is
    IERC1155LaunchpegBase,
    ERC1155Upgradeable,
    ERC2981Upgradeable,
    ReentrancyGuardUpgradeable,
    SafePausableUpgradeable
{
    using StringsUpgradeable for uint256;

    /// @notice Percentage base point
    uint256 private constant BASIS_POINT_PRECISION = 10_000;

    /// @notice Role granted to project owners
    bytes32 public constant override PROJECT_OWNER_ROLE =
        keccak256("PROJECT_OWNER_ROLE");

    /**
     * @dev OpenSea's filter registry and subscription address
     */
    address private constant OPENSEA_FILTER_REGISTRY =
        0x000000000000AAeB6D7670E522A718067333cd4E;
    address private constant OPENSEA_SUBSCRIPTION =
        0x3cc6CddA760b79bAfa08dF41ECFA224f810dCeB6;

    /// @notice Contract filtering allowed operators, preventing unauthorized contract to transfer NFTs
    /// By default, Launchpeg contracts are subscribed to OpenSea's Curated Subscription Address at 0x3cc6CddA760b79bAfa08dF41ECFA224f810dCeB6
    IOperatorFilterRegistry public override operatorFilterRegistry;

    /// @notice The fees collected by Joepegs on the sale benefits
    /// @dev In basis points e.g 100 for 1%
    uint256 public override joeFeePercent;

    /// @notice The address to which the fees on the sale will be sent
    address public override joeFeeCollector;

    /// @notice Start time when funds can be withdrawn
    uint256 public override withdrawAVAXStartTime;

    /// @notice This boolean can be turned on to prevent any changes on the sale parameters.
    /// @dev Once set to true, it shouldn't be possible to turn it back to false.
    bool public override locked;

    /// @notice The name of the collection
    string public override name;

    /// @notice The symbol of the collection
    string public override symbol;

    /// @notice Allow spending tokens from addresses with balance
    /// Note that this still allows listings and marketplaces with escrow to transfer tokens if transferred
    /// from an EOA.
    modifier onlyAllowedOperator(address from) virtual {
        if (from != msg.sender) {
            _checkFilterOperator(msg.sender);
        }
        _;
    }

    /// @notice Allow approving tokens transfers
    modifier onlyAllowedOperatorApproval(address operator) virtual {
        _checkFilterOperator(operator);
        _;
    }

    /// @notice The function updating sale parameters can only be called when the contract is not locked
    modifier contractNotLocked() {
        if (locked) {
            revert Launchpeg__SaleParametersLocked();
        }
        _;
    }

    /// @notice Checks if the current phase matches the required phase
    modifier atPhase(Phase phase) {
        if (currentPhase() != phase) {
            revert Launchpeg__WrongPhase();
        }
        _;
    }

    /// @dev Initialize the contract
    /// @param initData The data to initialize the contract
    function __ERC1155LaunchpegBase_init(
        InitData calldata initData
    ) internal onlyInitializing {
        __ERC1155_init("");
        __ERC2981_init();
        __ReentrancyGuard_init();
        __SafeAccessControlEnumerable_init();

        // Default royalty is 5%
        _setDefaultRoyalty(initData.royaltyReceiver, 500);

        // Initialize the operator filter registry and subscribe to OpenSea's list
        IOperatorFilterRegistry _operatorFilterRegistry = IOperatorFilterRegistry(
                OPENSEA_FILTER_REGISTRY
            );

        if (address(_operatorFilterRegistry).code.length > 0) {
            _operatorFilterRegistry.registerAndSubscribe(
                address(this),
                OPENSEA_SUBSCRIPTION
            );
        }

        _updateOperatorFilterRegistryAddress(_operatorFilterRegistry);

        name = initData.collectionName;
        symbol = initData.collectionSymbol;

        _initializeJoeFee(initData.joeFeePercent, initData.owner);

        grantRole(PROJECT_OWNER_ROLE, initData.royaltyReceiver);
        _transferOwnership(initData.owner);
    }

    /// @notice Returns the current phase
    /// @return phase Current phase
    function currentPhase() public view virtual returns (Phase);

    /// @notice Returns the token URI
    /// @param tokenId The token ID
    /// @return uri The token URI
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(super.uri(tokenId), tokenId.toString()));
    }

    /// @notice Returns true if the interface is supported
    /// @param interfaceId The interface ID
    /// @return isSupported True if the interface is supported
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(
            SafePausableUpgradeable,
            ERC1155Upgradeable,
            ERC2981Upgradeable
        )
        returns (bool)
    {
        return
            interfaceId == type(IERC1155LaunchpegBase).interfaceId ||
            ERC1155Upgradeable.supportsInterface(interfaceId) ||
            ERC2981Upgradeable.supportsInterface(interfaceId) ||
            AccessControlEnumerableUpgradeable.supportsInterface(interfaceId);
    }

    /// @notice Set the base URI
    /// @dev This sets the URI for revealed tokens
    /// Only callable by project owner
    /// @param newURI Base URI to be set
    function setURI(string calldata newURI) external override onlyOwner {
        _setURI(newURI);
        emit URISet(newURI);
    }

    /// @notice Set the withdraw AVAX start time.
    /// @param newWithdrawAVAXStartTime New public sale end time
    function setWithdrawAVAXStartTime(
        uint256 newWithdrawAVAXStartTime
    ) external override onlyOwner {
        withdrawAVAXStartTime = newWithdrawAVAXStartTime;
        emit WithdrawAVAXStartTimeSet(newWithdrawAVAXStartTime);
    }

    /// @notice Set the Royalty info
    /// @param receiver The address to which the royalties will be sent
    /// @param feePercent The royalty fee in basis points
    function setRoyaltyInfo(
        address receiver,
        uint96 feePercent
    ) external override onlyOwner {
        // Royalty fees are limited to 25%
        if (feePercent > 2_500) {
            revert Launchpeg__InvalidRoyaltyInfo();
        }
        _setDefaultRoyalty(receiver, feePercent);
        emit DefaultRoyaltySet(receiver, feePercent);
    }

    /// @notice Set the operator filter registry address
    /// @param newOperatorFilterRegistry New operator filter registry
    function setOperatorFilterRegistryAddress(
        address newOperatorFilterRegistry
    ) external override onlyOwner {
        _updateOperatorFilterRegistryAddress(
            IOperatorFilterRegistry(newOperatorFilterRegistry)
        );
    }

    /// @notice Updates on the sale parameters can be locked to prevent any changes
    /// @dev Once locked, it won't be possible to turn it back to false.
    function lockSaleParameters()
        external
        override
        onlyOwner
        contractNotLocked
    {
        locked = true;

        emit SaleParametersLocked();
    }

    /// @notice Withdraw AVAX to the given recipient
    /// @param to Recipient of the earned AVAX
    function withdrawAVAX(
        address to
    ) external override onlyOwnerOrRole(PROJECT_OWNER_ROLE) nonReentrant {
        if (
            block.timestamp < withdrawAVAXStartTime ||
            withdrawAVAXStartTime == 0
        ) {
            revert Launchpeg__WithdrawAVAXNotAvailable();
        }

        uint256 amount = address(this).balance;
        uint256 fee;
        uint256 feePercent = joeFeePercent;

        if (feePercent > 0) {
            fee = (amount * feePercent) / BASIS_POINT_PRECISION;
            amount = amount - fee;

            _send(joeFeeCollector, fee);
        }

        _send(to, amount);

        emit AvaxWithdraw(to, amount, fee);
    }

    /// @dev `setApprovalForAll` wrapper to prevent the sender to approve a non-allowed operator
    /// @param operator Address being approved
    /// @param approved Whether the operator is approved or not
    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    /// @dev `safeTransferFrom` wrapper to prevent a non-allowed operator to transfer the NFT
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param id TokenID to transfer
    /// @param amount Amount to transfer
    /// @param data Data to be used in the transfer callback
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /// @dev `safeBatchTransferFrom` wrapper to prevent a non-allowed operator to transfer the NFT
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param ids TokenIDs to transfer
    /// @param amounts Amounts to transfer
    /// @param data Data to be used in the transfer callback
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override onlyAllowedOperator(from) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /// @notice Initialize the sales fee percent taken by Joepegs and address that collects the fees
    /// @param newJoeFeePercent The fees collected by Joepegs on the sale benefits
    /// @param newJoeFeeCollector The address to which the fees on the sale will be sent
    function _initializeJoeFee(
        uint256 newJoeFeePercent,
        address newJoeFeeCollector
    ) internal {
        if (newJoeFeePercent > BASIS_POINT_PRECISION) {
            revert Launchpeg__InvalidPercent();
        }
        if (newJoeFeeCollector == address(0)) {
            revert Launchpeg__InvalidJoeFeeCollector();
        }
        joeFeePercent = newJoeFeePercent;
        joeFeeCollector = newJoeFeeCollector;
        emit JoeFeeInitialized(newJoeFeePercent, newJoeFeeCollector);
    }

    /**
     * @dev Update the address that the contract will make OperatorFilter checks against. When set to the zero
     * address, checks will be bypassed.
     * @param newRegistry The address of the new OperatorFilterRegistry
     */
    function _updateOperatorFilterRegistryAddress(
        IOperatorFilterRegistry newRegistry
    ) private {
        operatorFilterRegistry = newRegistry;
        emit OperatorFilterRegistryUpdated(address(newRegistry));
    }

    /// @dev Checks if the address (the operator) trying to transfer the NFT is allowed
    /// @param operator Address of the operator
    function _checkFilterOperator(address operator) internal view virtual {
        IOperatorFilterRegistry registry = operatorFilterRegistry;
        // Check registry code length to facilitate testing in environments without a deployed registry.
        if (address(registry).code.length > 0) {
            if (!registry.isOperatorAllowed(address(this), operator)) {
                revert OperatorNotAllowed(operator);
            }
        }
    }

    /**
     * @dev Sends AVAX to the given address
     * @param to Address to send AVAX to
     * @param amount Amount of AVAX to send
     */
    function _send(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert Launchpeg__TransferFailed();
        }
    }

    /// @dev Verifies that enough AVAX has been sent by the sender and refunds the extra tokens if any
    /// @param price The price paid by the sender for minting NFTs
    function _refundIfOver(uint256 price) internal {
        if (msg.value < price) {
            revert Launchpeg__NotEnoughAVAX(msg.value);
        }
        if (msg.value > price) {
            (bool success, ) = msg.sender.call{value: msg.value - price}("");
            if (!success) {
                revert Launchpeg__TransferFailed();
            }
        }
    }
}
