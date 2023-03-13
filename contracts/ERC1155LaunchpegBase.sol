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
    bytes32 public constant PROJECT_OWNER_ROLE =
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
    IOperatorFilterRegistry public operatorFilterRegistry;

    /// @notice The fees collected by Joepegs on the sale benefits
    /// @dev In basis points e.g 100 for 1%
    uint256 public joeFeePercent;

    /// @notice The address to which the fees on the sale will be sent
    address public joeFeeCollector;

    /// @notice Start time when funds can be withdrawn
    uint256 public withdrawAVAXStartTime;

    /// @notice This boolean can be turned on to prevent any changes on the sale parameters.
    /// @dev Once set to true, it shouldn't be possible to turn it back to false.
    bool public locked;

    string public name;

    string public symbol;

    struct InitData {
        address owner;
        address royaltyReceiver;
        uint256 joeFeePercent;
        string collectionName;
        string collectionSymbol;
    }

    enum Phase {
        NotStarted,
        DutchAuction,
        PreMint,
        Allowlist,
        PublicSale,
        Ended
    }

    /// @dev Emitted on updateOperatorFilterRegistryAddress()
    /// @param operatorFilterRegistry New operator filter registry
    event OperatorFilterRegistryUpdated(address operatorFilterRegistry);

    /// @dev Emitted on _setDefaultRoyalty()
    /// @param receiver Royalty fee collector
    /// @param feePercent Royalty fee percent in basis point
    event DefaultRoyaltySet(address indexed receiver, uint256 feePercent);

    /// @dev Emitted on setWithdrawAVAXStartTime()
    /// @param withdrawAVAXStartTime New withdraw AVAX start time
    event WithdrawAVAXStartTimeSet(uint256 withdrawAVAXStartTime);

    /// @dev Emitted on initializeJoeFee()
    /// @param feePercent The fees collected by Joepegs on the sale benefits
    /// @param feeCollector The address to which the fees on the sale will be sent
    event JoeFeeInitialized(uint256 feePercent, address feeCollector);

    /// @dev Emitted on withdrawAVAX()
    /// @param sender The address that withdrew the tokens
    /// @param amount Amount of AVAX transfered to `sender`
    /// @param fee Amount of AVAX paid to the fee collector
    event AvaxWithdraw(address indexed sender, uint256 amount, uint256 fee);

    /// @dev Emitted on setURI()
    /// @param uri The new base URI
    event URISet(string uri);

    event SaleParametersLocked();

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

    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(super.uri(tokenId), tokenId.toString()));
    }

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
    function setURI(string calldata newURI) external onlyOwner {
        _setURI(newURI);
        emit URISet(newURI);
    }

    /// @notice Set the withdraw AVAX start time.
    /// @param newWithdrawAVAXStartTime New public sale end time
    function setWithdrawAVAXStartTime(
        uint256 newWithdrawAVAXStartTime
    ) external onlyOwner {
        withdrawAVAXStartTime = newWithdrawAVAXStartTime;
        emit WithdrawAVAXStartTimeSet(newWithdrawAVAXStartTime);
    }

    function setRoyaltyInfo(
        address receiver,
        uint96 feePercent
    ) external onlyOwner {
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
    ) external onlyOwner {
        _updateOperatorFilterRegistryAddress(
            IOperatorFilterRegistry(newOperatorFilterRegistry)
        );
    }

    function lockSaleParameters() external onlyOwner contractNotLocked {
        locked = true;

        emit SaleParametersLocked();
    }

    /// @notice Withdraw AVAX to the given recipient
    /// @param to Recipient of the earned AVAX
    function withdrawAVAX(
        address to
    ) external onlyOwnerOrRole(PROJECT_OWNER_ROLE) nonReentrant {
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

    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, id, amount, data);
    }

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
