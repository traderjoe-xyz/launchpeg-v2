// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// LaunchpegFactory
error LaunchpegFactory__InvalidImplementation();
error LaunchpegFactory__InvalidBatchReveal();

// Launchpeg
error Launchpeg__BatchRevealNotInitialized();
error Launchpeg__BatchRevealStarted();
error Launchpeg__CanNotMintThisMany();
error Launchpeg__EndPriceGreaterThanStartPrice();
error Launchpeg__HasBeenForceRevealed();
error Launchpeg__JoeFeeAlreadyInitialized();
error Launchpeg__InvalidAuctionDropInterval();
error Launchpeg__InvalidStartTime();
error Launchpeg__InvalidBatchReveal();
error Launchpeg__InvalidBatchRevealSize();
error Launchpeg__InvalidCallbackGasLimit();
error Launchpeg__InvalidCoordinator();
error Launchpeg__InvalidKeyHash();
error Launchpeg__InvalidJoeFeeCollector();
error Launchpeg__InvalidMaxBatchSize();
error Launchpeg__InvalidAllowlistPrice();
error Launchpeg__InvalidProjectOwner();
error Launchpeg__InvalidPercent();
error Launchpeg__InvalidRevealDates();
error Launchpeg__InvalidRoyaltyInfo();
error Launchpeg__IsNotInTheConsumerList();
error Launchpeg__LargerCollectionSizeNeeded();
error Launchpeg__MaxSupplyForDevReached();
error Launchpeg__MaxSupplyReached();
error Launchpeg__AllowlistBeforeAuction();
error Launchpeg__NotEligibleForAllowlistMint();
error Launchpeg__NotEnoughAVAX(uint256 avaxSent);
error Launchpeg__NotInitialized();
error Launchpeg__PublicSaleBeforeAllowlist();
error Launchpeg__PublicSaleEndBeforePublicSaleStart();
error Launchpeg__RevealNextBatchNotAvailable();
error Launchpeg__TransferFailed();
error Launchpeg__Unauthorized();
error Launchpeg__WithdrawAVAXNotAvailable();
error Launchpeg__WrongAddressesAndNumSlotsLength();
error Launchpeg__WrongPhase();

// PendingOwnableUpgradeable
error PendingOwnableUpgradeable__NotOwner();
error PendingOwnableUpgradeable__NotPendingOwner();
error PendingOwnableUpgradeable__PendingOwnerAlreadySet();
error PendingOwnableUpgradeable__NoPendingOwner();

// SafeAccessControlEnumerableUpgradeable
error SafeAccessControlEnumerableUpgradeable__SenderMissingRoleAndIsNotOwner(
    bytes32 role,
    address sender
);
error SafeAccessControlEnumerableUpgradeable__RoleIsDefaultAdmin();
