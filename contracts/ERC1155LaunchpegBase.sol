// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {IOperatorFilterRegistry} from "operator-filter-registry/src/IOperatorFilterRegistry.sol";

import {SafeAccessControlEnumerableUpgradeable, AccessControlEnumerableUpgradeable} from "./utils/SafeAccessControlEnumerableUpgradeable.sol";
import "./LaunchpegErrors.sol";

abstract contract ERC1155LaunchpegBase is
    ERC1155Upgradeable,
    ERC2981Upgradeable,
    ReentrancyGuardUpgradeable,
    SafeAccessControlEnumerableUpgradeable
{
    using StringsUpgradeable for uint256;

    /// @notice Percentage base point
    uint256 private constant BASIS_POINT_PRECISION = 10_000;

    /// @notice Role granted to project owners
    bytes32 private constant PROJECT_OWNER_ROLE =
        keccak256("PROJECT_OWNER_ROLE");

    /**
     * @notice Contract filtering allowed operators, preventing unauthorized contract to transfer NFTs
     * By default, Launchpeg contracts are subscribed to OpenSea's Curated Subscription Address at 0x3cc6CddA760b79bAfa08dF41ECFA224f810dCeB6
     */
    IOperatorFilterRegistry public operatorFilterRegistry;

    /// @notice The fees collected by Joepegs on the sale benefits
    /// @dev In basis points e.g 100 for 1%
    uint256 public joeFeePercent;

    /// @notice The address to which the fees on the sale will be sent
    address public joeFeeCollector;

    /// @notice Start time when funds can be withdrawn
    uint256 public withdrawAVAXStartTime;

    string public name;

    string public symbol;

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

    function __ERC1155LaunchpegBase_init(
        address owner,
        address projectOwner,
        address royaltyReceiver,
        string memory initialUri,
        string memory collectionName,
        string memory collectionSymbol
    ) internal onlyInitializing {
        __ERC1155_init(initialUri);
        __ERC2981_init();
        __ReentrancyGuard_init();
        __SafeAccessControlEnumerable_init();

        // Default royalty is 5%
        _setDefaultRoyalty(royaltyReceiver, 500);

        // Initialize the operator filter registry and subscribe to OpenSea's list
        IOperatorFilterRegistry _operatorFilterRegistry = IOperatorFilterRegistry(
                0x000000000000AAeB6D7670E522A718067333cd4E
            );

        if (address(_operatorFilterRegistry).code.length > 0) {
            _operatorFilterRegistry.registerAndSubscribe(
                address(this),
                0x3cc6CddA760b79bAfa08dF41ECFA224f810dCeB6
            );
        }

        _updateOperatorFilterRegistryAddress(_operatorFilterRegistry);

        withdrawAVAXStartTime = block.timestamp + 7 days;

        name = collectionName;
        symbol = collectionSymbol;

        grantRole(PROJECT_OWNER_ROLE, projectOwner);
        _transferOwnership(owner);
    }

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
            SafeAccessControlEnumerableUpgradeable,
            ERC1155Upgradeable,
            ERC2981Upgradeable
        )
        returns (bool)
    {
        return
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

    /// @notice Set the royalty fee
    /// @param _receiver Royalty fee collector
    /// @param _feePercent Royalty fee percent in basis point
    function setRoyaltyInfo(
        address _receiver,
        uint96 _feePercent
    ) external onlyOwner {
        // Royalty fees are limited to 25%
        if (_feePercent > 2_500) {
            revert Launchpeg__InvalidRoyaltyInfo();
        }
        _setDefaultRoyalty(_receiver, _feePercent);
        emit DefaultRoyaltySet(_receiver, _feePercent);
    }

    /// @notice Set the withdraw AVAX start time.
    /// @param newWithdrawAVAXStartTime New public sale end time
    function setWithdrawAVAXStartTime(
        uint256 newWithdrawAVAXStartTime
    ) external onlyOwner {
        withdrawAVAXStartTime = newWithdrawAVAXStartTime;
        emit WithdrawAVAXStartTimeSet(newWithdrawAVAXStartTime);
    }

    /// @notice Withdraw AVAX to the given recipient
    /// @param to Recipient of the earned AVAX
    function withdrawAVAX(
        address to
    ) external onlyOwnerOrRole(PROJECT_OWNER_ROLE) nonReentrant {
        if (
            withdrawAVAXStartTime > block.timestamp ||
            withdrawAVAXStartTime == 0
        ) {
            revert Launchpeg__WithdrawAVAXNotAvailable();
        }

        uint256 amount = address(this).balance;
        uint256 fee;
        bool sent;

        if (joeFeePercent > 0) {
            fee = (amount * joeFeePercent) / BASIS_POINT_PRECISION;
            amount = amount - fee;

            (sent, ) = joeFeeCollector.call{value: fee}("");
            if (!sent) {
                revert Launchpeg__TransferFailed();
            }
        }

        (sent, ) = to.call{value: amount}("");
        if (!sent) {
            revert Launchpeg__TransferFailed();
        }

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
