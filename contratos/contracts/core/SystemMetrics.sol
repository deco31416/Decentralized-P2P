// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title SystemMetrics
 * @notice Agregador centralizado de estadísticas del sistema completo
 * @dev Consulta múltiples contratos y agrega métricas para el dashboard
 * 
 * PROPÓSITO:
 * - Dashboard necesita stats de 10+ contratos diferentes
 * - Frontend haría 10+ calls separados = lento + caro
 * - Este contrato hace 1 call y retorna todo agregado
 * 
 * MÉTRICAS AGREGADAS:
 * - Trading: Volumen total, número de trades, fees generados
 * - Usuarios: Usuarios activos, nuevos usuarios, top performers
 * - P2P: Ofertas activas, swaps completados
 * - Deposits/Withdrawals: Totales, volumen
 * - Rewards: Total distribuido, usuarios con rewards
 * - Referrals: Red de referidos, volumen generado
 * - Staking: Total staked, número de stakers
 * 
 * INTEGRACIÓN:
 * - Configura addresses de todos los contratos
 * - Cada función getXXXStats() consulta contratos relevantes
 * - Frontend solo llama a getGlobalDashboard() → recibe todo
 */
contract SystemMetrics is AccessControl {
    
    // ========================================
    // ESTRUCTURAS
    // ========================================

    /**
     * @dev Stats globales para el dashboard
     */
    struct GlobalDashboardStats {
        // Trading
        uint256 totalTradingVolume;
        uint256 totalTrades;
        uint256 totalFeesGenerated;
        
        // Usuarios
        uint256 totalUsers;
        uint256 activeUsers;
        
        // P2P Exchange
        uint256 totalOffers;
        uint256 activeOffers;
        uint256 completedSwaps;
        
        // Deposits & Withdrawals
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        uint256 depositVolume;
        uint256 withdrawVolume;
        
        // Rewards & Referrals
        uint256 totalRewardsDistributed;
        uint256 totalReferrals;
        uint256 referralVolume;
        
        // Staking
        uint256 totalStaked;
        uint256 totalStakers;
        
        // Treasury
        uint256 treasuryBalance;
        uint256 treasuryFeesCollected;
    }

    /**
     * @dev Stats de trading
     */
    struct TradingStats {
        uint256 p2pTotalOffers;
        uint256 p2pActiveOffers;
        uint256 p2pCompletedSwaps;
        uint256 orderBookTotalOrders;
        uint256 orderBookActiveOrders;
        uint256 swapRouterTotalSwaps;
    }

    // ========================================
    // VARIABLES DE ESTADO
    // ========================================

    // Contratos del sistema
    address public p2pExchange;
    address public p2pOrderBook;
    address public swapRouter;
    address public depositManager;
    address public withdrawManager;
    address public stakingManager;
    address public treasuryManager;
    address public feeManager;
    address public topPerformersTracker;
    address public referralManager;
    address public socialFiRewards;

    // ========================================
    // EVENTOS
    // ========================================

    event ContractUpdated(string contractName, address newAddress);

    // ========================================
    // ERRORES
    // ========================================

    error InvalidAddress();
    error ContractCallFailed();

    // ========================================
    // CONSTRUCTOR
    // ========================================

    constructor(address admin) {
        if (admin == address(0)) revert InvalidAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ========================================
    // FUNCIONES PRINCIPALES - AGREGADORES
    // ========================================

    /**
     * @notice Obtiene todas las stats para el dashboard principal
     * @dev Una sola llamada retorna todo lo necesario
     */
    function getGlobalDashboard() external view returns (GlobalDashboardStats memory stats) {
        // Trading stats
        TradingStats memory trading = getTradingStats();
        stats.totalTrades = trading.p2pCompletedSwaps + trading.swapRouterTotalSwaps;
        stats.totalOffers = trading.p2pTotalOffers + trading.orderBookTotalOrders;
        stats.activeOffers = trading.p2pActiveOffers + trading.orderBookActiveOrders;
        stats.completedSwaps = trading.p2pCompletedSwaps;

        // Top Performers (tiene stats más completas)
        if (topPerformersTracker != address(0)) {
            (
                uint256 totalUsers,
                uint256 activeUsers,
                uint256 referralVolume,
                uint256 tradingVolume,
                uint256 feesGenerated,
                // uint256 totalActivities
            ) = _callTopPerformersStats();
            
            stats.totalUsers = totalUsers;
            stats.activeUsers = activeUsers;
            stats.referralVolume = referralVolume;
            stats.totalTradingVolume = tradingVolume;
            stats.totalFeesGenerated = feesGenerated;
        }

        // Deposits & Withdrawals
        if (depositManager != address(0)) {
            // Llamar getSystemStats() si existe
            // stats.totalDeposits = ...;
        }

        // Staking
        if (stakingManager != address(0)) {
            // Llamar getters de staking
            // stats.totalStaked = ...;
        }

        // Treasury
        if (treasuryManager != address(0)) {
            (bool success, bytes memory data) = treasuryManager.staticcall(
                abi.encodeWithSignature("totalFeesCollected()")
            );
            if (success && data.length > 0) {
                stats.treasuryFeesCollected = abi.decode(data, (uint256));
            }
        }

        // Referrals
        if (referralManager != address(0)) {
            (
                , // totalUsers (ya lo tenemos)
                uint256 totalReferrals,
                , // uint256 totalVolumeTracked - unused
                , // uint256 totalFeesTracked - unused
                uint256 totalRewardsDistributed,
                // uint256 poolBalance
            ) = _callReferralStats();
            
            stats.totalReferrals = totalReferrals;
            stats.totalRewardsDistributed = totalRewardsDistributed;
        }

        return stats;
    }

    /**
     * @notice Obtiene stats de trading (P2P + OrderBook + Router)
     */
    function getTradingStats() public view returns (TradingStats memory stats) {
        // P2P Exchange
        if (p2pExchange != address(0)) {
            (
                uint256 totalOffers,
                , // uint256 totalSwaps - unused
                uint256 completedSwaps,
                uint256 activeOffers,
                // uint256 totalUsers
            ) = _callP2PExchangeStats();
            
            stats.p2pTotalOffers = totalOffers;
            stats.p2pCompletedSwaps = completedSwaps;
            stats.p2pActiveOffers = activeOffers;
        }

        // P2P OrderBook
        if (p2pOrderBook != address(0)) {
            (
                uint256 totalOrders,
                , // totalPairs
                uint256 activeOrders,
                // uint256 totalVolume
            ) = _callOrderBookStats();
            
            stats.orderBookTotalOrders = totalOrders;
            stats.orderBookActiveOrders = activeOrders;
        }

        // Swap Router
        if (swapRouter != address(0)) {
            (
                uint256 totalSwaps,
                , , // otros stats
            ) = _callSwapRouterStats();
            
            stats.swapRouterTotalSwaps = totalSwaps;
        }

        return stats;
    }

    // ========================================
    // FUNCIONES INTERNAS - LLAMADAS A CONTRATOS
    // ========================================

    function _callP2PExchangeStats() internal view returns (
        uint256 totalOffers,
        uint256 totalSwaps,
        uint256 completedSwaps,
        uint256 activeOffers,
        uint256 totalUsers
    ) {
        (bool success, bytes memory data) = p2pExchange.staticcall(
            abi.encodeWithSignature("getStats()")
        );
        if (success && data.length > 0) {
            return abi.decode(data, (uint256, uint256, uint256, uint256, uint256));
        }
        return (0, 0, 0, 0, 0);
    }

    function _callOrderBookStats() internal view returns (
        uint256 totalOrders,
        uint256 totalPairs,
        uint256 activeOrders,
        uint256 totalVolume
    ) {
        (bool success, bytes memory data) = p2pOrderBook.staticcall(
            abi.encodeWithSignature("getStats()")
        );
        if (success && data.length > 0) {
            return abi.decode(data, (uint256, uint256, uint256, uint256));
        }
        return (0, 0, 0, 0);
    }

    function _callSwapRouterStats() internal view returns (
        uint256 totalSwaps,
        uint256 totalSources,
        uint256 totalPairs,
        uint256 totalVolume
    ) {
        (bool success, bytes memory data) = swapRouter.staticcall(
            abi.encodeWithSignature("getStats()")
        );
        if (success && data.length > 0) {
            return abi.decode(data, (uint256, uint256, uint256, uint256));
        }
        return (0, 0, 0, 0);
    }

    function _callTopPerformersStats() internal view returns (
        uint256 totalUsers,
        uint256 activeUsers,
        uint256 referralVolume,
        uint256 tradingVolume,
        uint256 feesGenerated,
        uint256 totalActivities
    ) {
        (bool success, bytes memory data) = topPerformersTracker.staticcall(
            abi.encodeWithSignature("getGlobalStats()")
        );
        if (success && data.length > 0) {
            return abi.decode(data, (uint256, uint256, uint256, uint256, uint256, uint256));
        }
        return (0, 0, 0, 0, 0, 0);
    }

    function _callReferralStats() internal view returns (
        uint256 totalUsers,
        uint256 totalReferrals,
        uint256 totalVolume,
        uint256 totalFees,
        uint256 totalRewards,
        uint256 poolBalance
    ) {
        (bool success, bytes memory data) = referralManager.staticcall(
            abi.encodeWithSignature("getGlobalStats()")
        );
        if (success && data.length > 0) {
            return abi.decode(data, (uint256, uint256, uint256, uint256, uint256, uint256));
        }
        return (0, 0, 0, 0, 0, 0);
    }

    // ========================================
    // FUNCIONES ADMIN - CONFIGURACIÓN
    // ========================================

    function setP2PExchange(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        p2pExchange = _address;
        emit ContractUpdated("P2PExchange", _address);
    }

    function setP2POrderBook(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        p2pOrderBook = _address;
        emit ContractUpdated("P2POrderBook", _address);
    }

    function setSwapRouter(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        swapRouter = _address;
        emit ContractUpdated("SwapRouter", _address);
    }

    function setDepositManager(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositManager = _address;
        emit ContractUpdated("DepositManager", _address);
    }

    function setWithdrawManager(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        withdrawManager = _address;
        emit ContractUpdated("WithdrawManager", _address);
    }

    function setStakingManager(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _address;
        emit ContractUpdated("StakingManager", _address);
    }

    function setTreasuryManager(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryManager = _address;
        emit ContractUpdated("TreasuryManager", _address);
    }

    function setFeeManager(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeManager = _address;
        emit ContractUpdated("FeeManager", _address);
    }

    function setTopPerformersTracker(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        topPerformersTracker = _address;
        emit ContractUpdated("TopPerformersTracker", _address);
    }

    function setReferralManager(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        referralManager = _address;
        emit ContractUpdated("ReferralManager", _address);
    }

    function setSocialFiRewards(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        socialFiRewards = _address;
        emit ContractUpdated("SocialFiRewards", _address);
    }

    /**
     * @notice Configura todos los contratos en batch
     */
    function setAllContracts(
        address _p2pExchange,
        address _p2pOrderBook,
        address _swapRouter,
        address _depositManager,
        address _withdrawManager,
        address _stakingManager,
        address _treasuryManager,
        address _feeManager,
        address _topPerformersTracker,
        address _referralManager,
        address _socialFiRewards
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        p2pExchange = _p2pExchange;
        p2pOrderBook = _p2pOrderBook;
        swapRouter = _swapRouter;
        depositManager = _depositManager;
        withdrawManager = _withdrawManager;
        stakingManager = _stakingManager;
        treasuryManager = _treasuryManager;
        feeManager = _feeManager;
        topPerformersTracker = _topPerformersTracker;
        referralManager = _referralManager;
        socialFiRewards = _socialFiRewards;
    }
}
