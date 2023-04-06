// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IOperatorFilterRegistry} from "operator-filter-registry/src/IOperatorFilterRegistry.sol";

interface IERC1155LaunchpegBase {
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

    function PROJECT_OWNER_ROLE() external view returns (bytes32);

    function operatorFilterRegistry()
        external
        view
        returns (IOperatorFilterRegistry);

    function joeFeePercent() external view returns (uint256);

    function joeFeeCollector() external view returns (address);

    function withdrawAVAXStartTime() external view returns (uint256);

    function locked() external view returns (bool);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function currentPhase() external view returns (Phase);

    function setURI(string memory newURI) external;

    function setWithdrawAVAXStartTime(uint256 withdrawAVAXStartTime) external;

    function setRoyaltyInfo(address receiver, uint96 feePercent) external;

    function setOperatorFilterRegistryAddress(
        address operatorFilterRegistry
    ) external;

    function lockSaleParameters() external;

    function withdrawAVAX(address to) external;
}
