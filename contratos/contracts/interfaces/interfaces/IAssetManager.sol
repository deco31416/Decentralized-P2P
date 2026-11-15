// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAssetManager
 * @notice Interface para el AssetManager
 */
interface IAssetManager {
    
    enum TokenCategory {
        Cryptocurrency,
        Stablecoin,
        Utility,
        Synthetic,
        NFT,
        Other
    }

    enum FiatPaymentType {
        BankTransfer,
        Cash,
        MobilePayment,
        OnlineWallet,
        Cryptocurrency,
        Other
    }

    struct TokenInfo {
        address tokenAddress;
        string symbol;
        string name;
        uint8 decimals;
        TokenCategory category;
        bool isActive;
        bool canDeposit;
        bool canWithdraw;
        bool canTrade;
        bool canStake;
        uint256 minDepositAmount;
        uint256 maxDepositAmount;
        uint256 minWithdrawAmount;
        uint256 maxWithdrawAmount;
        uint256 dailyDepositLimit;
        uint256 dailyWithdrawLimit;
        uint256 addedAt;
        address addedBy;
        string logoURI;
        string website;
        bool verified;
    }

    struct FiatPaymentMethod {
        uint256 methodId;
        string name;
        string code;
        FiatPaymentType paymentType;
        string[] supportedCurrencies;
        string[] supportedCountries;
        bool isActive;
        bool requiresKYC;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 processingTime;
        uint256 feePercentage;
        uint256 addedAt;
        address addedBy;
        string logoURI;
        string instructions;
    }

    // View functions
    function isTokenSupported(address token) external view returns (bool);
    function getTokenInfo(address token) external view returns (TokenInfo memory);
    function canTokenBeDeposited(address token) external view returns (bool);
    function canTokenBeWithdrawn(address token) external view returns (bool);
    function canTokenBeTraded(address token) external view returns (bool);
    function getFiatMethodInfo(uint256 methodId) external view returns (FiatPaymentMethod memory);
    function getActiveFiatMethods() external view returns (uint256[] memory);
    function getMethodsByCountry(string memory countryCode) external view returns (uint256[] memory);
}
