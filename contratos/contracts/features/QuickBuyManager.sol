// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IBalanceManager.sol";

/**
 * @title QuickBuyManager
 * @notice Sistema de compra rápida donde la plataforma actúa como market maker
 * @dev Implementa liquidez de la plataforma para usuarios preferenciales
 * 
 * Características principales:
 * - Whitelist de usuarios preferenciales
 * - Ofertas de liquidez de la plataforma (USD→USDT, EUR→BTC, etc.)
 * - Swaps instantáneos sin intermediarios
 * - Rating y reputación de la plataforma como vendedor
 * - Límites por usuario (daily/weekly)
 * - Precios dinámicos con spreads configurables
 * 
 * Flujo de uso:
 * 1. Admin: addPreferredUser(0x123) → Usuario agregado a whitelist
 * 2. Admin: createPlatformOffer(USDT, EUR, rate, min, max) → Oferta de liquidez
 * 3. Usuario Preferencial: quickSwap(EUR, USDT, 1000) → Swap instantáneo
 * 4. Usuario: ratePlatform(5, "Fast service") → Califica la plataforma
 * 
 * Esquema:
 * Usuario Preferencial ↔ Plataforma (liquidez garantizada)
 */
contract QuickBuyManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============================================
    // ROLES
    // ============================================
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant LIQUIDITY_MANAGER_ROLE = keccak256("LIQUIDITY_MANAGER_ROLE");

    // ============================================
    // ESTRUCTURAS
    // ============================================

    /// @notice Oferta de liquidez de la plataforma
    struct PlatformOffer {
        uint256 offerId;
        address tokenSell;          // Token que vende la plataforma
        address tokenBuy;           // Token que compra la plataforma
        uint256 rate;               // Tasa de cambio (1e18 = 1:1)
        uint256 spreadBps;          // Spread en basis points (100 = 1%)
        uint256 minAmount;          // Mínimo por swap
        uint256 maxAmount;          // Máximo por swap
        uint256 dailyLimit;         // Límite diario total
        uint256 dailyUsed;          // Usado hoy
        uint256 lastResetDay;       // Día del último reset
        bool isActive;              // Estado de la oferta
        uint256 totalVolume;        // Volumen histórico
        uint256 totalSwaps;         // Total de swaps realizados
        uint256 createdAt;
        uint256 updatedAt;
    }

    /// @notice Rating de la plataforma como vendedor
    struct PlatformRating {
        uint256 totalRatings;       // Total de ratings recibidos
        uint256 sumRatings;         // Suma de ratings (1-5)
        uint256 totalVolume;        // Volumen total transado
        uint256 totalSwaps;         // Total de swaps realizados
        uint256 avgResponseTime;    // Tiempo promedio de respuesta (segundos)
        uint256 successRate;        // Tasa de éxito (basis points)
        uint256 lastUpdated;
    }

    /// @notice Información de usuario preferencial
    struct PreferredUser {
        bool isActive;              // Estado de whitelist
        uint256 tier;               // Tier del usuario (1-5)
        uint256 dailyLimit;         // Límite diario personalizado
        uint256 dailyUsed;          // Usado hoy
        uint256 weeklyLimit;        // Límite semanal
        uint256 weeklyUsed;         // Usado esta semana
        uint256 lastResetDay;       // Día del último reset diario
        uint256 lastResetWeek;      // Semana del último reset semanal
        uint256 totalSwaps;         // Total de swaps realizados
        uint256 totalVolume;        // Volumen histórico (USD)
        uint256 joinedAt;           // Timestamp de ingreso
    }

    /// @notice Historial de swap
    struct SwapRecord {
        uint256 swapId;
        address user;
        uint256 offerId;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 rate;
        uint256 spreadBps;
        uint256 timestamp;
        uint256 executionTime;      // Tiempo de ejecución (ms)
        bool success;
    }

    // ============================================
    // VARIABLES DE ESTADO
    // ============================================

    /// @notice Contador de ofertas
    uint256 public offerCount;

    /// @notice Contador de swaps
    uint256 public swapCount;

    /// @notice Mapeo de ID a oferta de plataforma
    mapping(uint256 => PlatformOffer) public platformOffers;

    /// @notice Mapeo de usuario a información preferencial
    mapping(address => PreferredUser) public preferredUsers;

    /// @notice Lista de usuarios preferenciales activos
    address[] private preferredUsersList;

    /// @notice Rating de la plataforma
    PlatformRating public platformRating;

    /// @notice Historial de swaps
    mapping(uint256 => SwapRecord) public swapRecords;

    /// @notice Swaps por usuario
    mapping(address => uint256[]) public userSwaps;

    /// @notice Balance Manager para integración
    IBalanceManager public balanceManager;

    /// @notice Wallet de la plataforma (market maker)
    address public platformWallet;

    /// @notice Límite por defecto para nuevos usuarios preferenciales
    uint256 public defaultDailyLimit = 10000e18;  // $10,000
    uint256 public defaultWeeklyLimit = 50000e18; // $50,000

    /// @notice Límites de tier
    mapping(uint256 => uint256) public tierDailyLimits;
    mapping(uint256 => uint256) public tierWeeklyLimits;

    /// @notice Modo de mantenimiento
    bool public maintenanceMode;

    // ============================================
    // EVENTOS
    // ============================================

    event PlatformOfferCreated(
        uint256 indexed offerId,
        address indexed tokenSell,
        address indexed tokenBuy,
        uint256 rate,
        uint256 spreadBps
    );

    event PlatformOfferUpdated(
        uint256 indexed offerId,
        uint256 newRate,
        uint256 newSpreadBps
    );

    event PlatformOfferToggled(uint256 indexed offerId, bool isActive);

    event PreferredUserAdded(
        address indexed user,
        uint256 tier,
        uint256 dailyLimit,
        uint256 weeklyLimit
    );

    event PreferredUserRemoved(address indexed user);

    event PreferredUserTierUpdated(address indexed user, uint256 oldTier, uint256 newTier);

    event QuickSwapExecuted(
        uint256 indexed swapId,
        address indexed user,
        uint256 indexed offerId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executionTime
    );

    event PlatformRated(
        address indexed user,
        uint256 rating,
        string comment,
        uint256 timestamp
    );

    event PlatformWalletUpdated(address indexed oldWallet, address indexed newWallet);

    event MaintenanceModeToggled(bool enabled);

    // ============================================
    // MODIFICADORES
    // ============================================

    modifier onlyPreferredUser() {
        require(preferredUsers[msg.sender].isActive, "Not a preferred user");
        _;
    }

    modifier notInMaintenance() {
        require(!maintenanceMode, "System in maintenance");
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _platformWallet,
        address _balanceManager
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_platformWallet != address(0), "Invalid platform wallet");
        require(_balanceManager != address(0), "Invalid balance manager");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(LIQUIDITY_MANAGER_ROLE, _admin);

        platformWallet = _platformWallet;
        balanceManager = IBalanceManager(_balanceManager);

        // Configurar límites por tier
        tierDailyLimits[1] = 5000e18;   // $5,000
        tierDailyLimits[2] = 10000e18;  // $10,000
        tierDailyLimits[3] = 25000e18;  // $25,000
        tierDailyLimits[4] = 50000e18;  // $50,000
        tierDailyLimits[5] = 100000e18; // $100,000

        tierWeeklyLimits[1] = 25000e18;   // $25,000
        tierWeeklyLimits[2] = 50000e18;   // $50,000
        tierWeeklyLimits[3] = 125000e18;  // $125,000
        tierWeeklyLimits[4] = 250000e18;  // $250,000
        tierWeeklyLimits[5] = 500000e18;  // $500,000
    }

    // ============================================
    // FUNCIONES DE GESTIÓN DE OFERTAS
    // ============================================

    /**
     * @notice Crea una oferta de liquidez de la plataforma
     * @param tokenSell Token que vende la plataforma
     * @param tokenBuy Token que compra la plataforma
     * @param rate Tasa de cambio (1e18 = 1:1)
     * @param spreadBps Spread en basis points (100 = 1%)
     * @param minAmount Mínimo por swap
     * @param maxAmount Máximo por swap
     * @param dailyLimit Límite diario total
     */
    function createPlatformOffer(
        address tokenSell,
        address tokenBuy,
        uint256 rate,
        uint256 spreadBps,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    ) external onlyRole(LIQUIDITY_MANAGER_ROLE) returns (uint256) {
        require(tokenSell != address(0) && tokenBuy != address(0), "Invalid tokens");
        require(tokenSell != tokenBuy, "Same token");
        require(rate > 0, "Invalid rate");
        require(spreadBps <= 1000, "Spread too high"); // Max 10%
        require(minAmount > 0 && minAmount <= maxAmount, "Invalid amounts");
        require(dailyLimit >= maxAmount, "Daily limit too low");

        offerCount++;
        uint256 offerId = offerCount;

        platformOffers[offerId] = PlatformOffer({
            offerId: offerId,
            tokenSell: tokenSell,
            tokenBuy: tokenBuy,
            rate: rate,
            spreadBps: spreadBps,
            minAmount: minAmount,
            maxAmount: maxAmount,
            dailyLimit: dailyLimit,
            dailyUsed: 0,
            lastResetDay: block.timestamp / 1 days,
            isActive: true,
            totalVolume: 0,
            totalSwaps: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        emit PlatformOfferCreated(offerId, tokenSell, tokenBuy, rate, spreadBps);

        return offerId;
    }

    /**
     * @notice Actualiza la tasa y spread de una oferta
     * @param offerId ID de la oferta
     * @param newRate Nueva tasa de cambio
     * @param newSpreadBps Nuevo spread
     */
    function updatePlatformOffer(
        uint256 offerId,
        uint256 newRate,
        uint256 newSpreadBps
    ) external onlyRole(LIQUIDITY_MANAGER_ROLE) {
        PlatformOffer storage offer = platformOffers[offerId];
        require(offer.offerId != 0, "Offer not found");
        require(newRate > 0, "Invalid rate");
        require(newSpreadBps <= 1000, "Spread too high");

        offer.rate = newRate;
        offer.spreadBps = newSpreadBps;
        offer.updatedAt = block.timestamp;

        emit PlatformOfferUpdated(offerId, newRate, newSpreadBps);
    }

    /**
     * @notice Activa/desactiva una oferta
     * @param offerId ID de la oferta
     * @param isActive Nuevo estado
     */
    function togglePlatformOffer(uint256 offerId, bool isActive) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        PlatformOffer storage offer = platformOffers[offerId];
        require(offer.offerId != 0, "Offer not found");

        offer.isActive = isActive;
        offer.updatedAt = block.timestamp;

        emit PlatformOfferToggled(offerId, isActive);
    }

    // ============================================
    // FUNCIONES DE GESTIÓN DE USUARIOS PREFERENCIALES
    // ============================================

    /**
     * @notice Agrega un usuario preferencial a la whitelist
     * @param user Dirección del usuario
     * @param tier Tier del usuario (1-5)
     */
    function addPreferredUser(address user, uint256 tier) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(user != address(0), "Invalid user");
        require(tier >= 1 && tier <= 5, "Invalid tier");
        require(!preferredUsers[user].isActive, "Already preferred");

        uint256 dailyLimit = tierDailyLimits[tier];
        uint256 weeklyLimit = tierWeeklyLimits[tier];

        preferredUsers[user] = PreferredUser({
            isActive: true,
            tier: tier,
            dailyLimit: dailyLimit,
            dailyUsed: 0,
            weeklyLimit: weeklyLimit,
            weeklyUsed: 0,
            lastResetDay: block.timestamp / 1 days,
            lastResetWeek: block.timestamp / 1 weeks,
            totalSwaps: 0,
            totalVolume: 0,
            joinedAt: block.timestamp
        });

        preferredUsersList.push(user);

        emit PreferredUserAdded(user, tier, dailyLimit, weeklyLimit);
    }

    /**
     * @notice Remueve un usuario preferencial
     * @param user Dirección del usuario
     */
    function removePreferredUser(address user) external onlyRole(ADMIN_ROLE) {
        require(preferredUsers[user].isActive, "Not preferred");

        preferredUsers[user].isActive = false;

        // Remover de la lista
        for (uint256 i = 0; i < preferredUsersList.length; i++) {
            if (preferredUsersList[i] == user) {
                preferredUsersList[i] = preferredUsersList[preferredUsersList.length - 1];
                preferredUsersList.pop();
                break;
            }
        }

        emit PreferredUserRemoved(user);
    }

    /**
     * @notice Actualiza el tier de un usuario preferencial
     * @param user Dirección del usuario
     * @param newTier Nuevo tier (1-5)
     */
    function updatePreferredUserTier(address user, uint256 newTier) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(preferredUsers[user].isActive, "Not preferred");
        require(newTier >= 1 && newTier <= 5, "Invalid tier");

        PreferredUser storage userData = preferredUsers[user];
        uint256 oldTier = userData.tier;

        userData.tier = newTier;
        userData.dailyLimit = tierDailyLimits[newTier];
        userData.weeklyLimit = tierWeeklyLimits[newTier];

        emit PreferredUserTierUpdated(user, oldTier, newTier);
    }

    // ============================================
    // FUNCIONES DE SWAP
    // ============================================

    /**
     * @notice Ejecuta un swap rápido usando liquidez de la plataforma
     * @param offerId ID de la oferta de plataforma
     * @param amountIn Cantidad de tokens a vender
     * @return amountOut Cantidad de tokens que recibe el usuario
     */
    function quickSwap(uint256 offerId, uint256 amountIn)
        external
        nonReentrant
        whenNotPaused
        notInMaintenance
        onlyPreferredUser
        returns (uint256 amountOut)
    {
        uint256 startTime = block.timestamp;

        PlatformOffer storage offer = platformOffers[offerId];
        require(offer.isActive, "Offer not active");
        require(amountIn >= offer.minAmount, "Below minimum");
        require(amountIn <= offer.maxAmount, "Above maximum");

        PreferredUser storage userData = preferredUsers[msg.sender];

        // Reset límites diarios si es necesario
        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > userData.lastResetDay) {
            userData.dailyUsed = 0;
            userData.lastResetDay = currentDay;
        }
        if (currentDay > offer.lastResetDay) {
            offer.dailyUsed = 0;
            offer.lastResetDay = currentDay;
        }

        // Reset límites semanales si es necesario
        uint256 currentWeek = block.timestamp / 1 weeks;
        if (currentWeek > userData.lastResetWeek) {
            userData.weeklyUsed = 0;
            userData.lastResetWeek = currentWeek;
        }

        // Verificar límites de usuario
        require(userData.dailyUsed + amountIn <= userData.dailyLimit, "Daily limit exceeded");
        require(userData.weeklyUsed + amountIn <= userData.weeklyLimit, "Weekly limit exceeded");

        // Verificar límites de oferta
        require(offer.dailyUsed + amountIn <= offer.dailyLimit, "Offer daily limit exceeded");

        // Calcular amountOut con spread
        amountOut = (amountIn * offer.rate * (10000 - offer.spreadBps)) / (1e18 * 10000);
        require(amountOut > 0, "Invalid output");

        // Transferir tokens del usuario a la plataforma
        IERC20(offer.tokenBuy).safeTransferFrom(msg.sender, platformWallet, amountIn);

        // Transferir tokens de la plataforma al usuario
        IERC20(offer.tokenSell).safeTransferFrom(platformWallet, msg.sender, amountOut);

        // Actualizar límites
        userData.dailyUsed += amountIn;
        userData.weeklyUsed += amountIn;
        userData.totalSwaps++;
        userData.totalVolume += amountIn;

        offer.dailyUsed += amountIn;
        offer.totalVolume += amountIn;
        offer.totalSwaps++;

        // Actualizar rating de plataforma
        platformRating.totalSwaps++;
        platformRating.totalVolume += amountIn;

        // Registrar swap
        swapCount++;
        uint256 executionTime = block.timestamp - startTime;

        swapRecords[swapCount] = SwapRecord({
            swapId: swapCount,
            user: msg.sender,
            offerId: offerId,
            tokenIn: offer.tokenBuy,
            tokenOut: offer.tokenSell,
            amountIn: amountIn,
            amountOut: amountOut,
            rate: offer.rate,
            spreadBps: offer.spreadBps,
            timestamp: block.timestamp,
            executionTime: executionTime,
            success: true
        });

        userSwaps[msg.sender].push(swapCount);

        emit QuickSwapExecuted(
            swapCount,
            msg.sender,
            offerId,
            offer.tokenBuy,
            offer.tokenSell,
            amountIn,
            amountOut,
            executionTime
        );

        return amountOut;
    }

    // ============================================
    // FUNCIONES DE RATING
    // ============================================

    /**
     * @notice Califica la plataforma como vendedor
     * @param rating Rating de 1 a 5 estrellas
     * @param comment Comentario opcional
     */
    function ratePlatform(uint256 rating, string calldata comment) 
        external 
        onlyPreferredUser 
    {
        require(rating >= 1 && rating <= 5, "Invalid rating");
        require(userSwaps[msg.sender].length > 0, "No swaps yet");

        platformRating.totalRatings++;
        platformRating.sumRatings += rating;
        platformRating.lastUpdated = block.timestamp;

        emit PlatformRated(msg.sender, rating, comment, block.timestamp);
    }

    // ============================================
    // FUNCIONES DE LECTURA
    // ============================================

    /**
     * @notice Obtiene el rating promedio de la plataforma
     * @return avgRating Rating promedio (1-5) multiplicado por 100
     */
    function getAveragePlatformRating() external view returns (uint256 avgRating) {
        if (platformRating.totalRatings == 0) return 0;
        return (platformRating.sumRatings * 100) / platformRating.totalRatings;
    }

    /**
     * @notice Verifica si un usuario es preferencial
     * @param user Dirección del usuario
     * @return isPreferred True si el usuario está en la whitelist
     */
    function isPreferredUser(address user) external view returns (bool) {
        return preferredUsers[user].isActive;
    }

    /**
     * @notice Obtiene el límite disponible de un usuario
     * @param user Dirección del usuario
     * @return dailyAvailable Límite diario disponible
     * @return weeklyAvailable Límite semanal disponible
     */
    function getUserAvailableLimit(address user) 
        external 
        view 
        returns (uint256 dailyAvailable, uint256 weeklyAvailable) 
    {
        PreferredUser storage userData = preferredUsers[user];
        if (!userData.isActive) return (0, 0);

        // Calcular límites disponibles (considerar reset)
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentWeek = block.timestamp / 1 weeks;

        uint256 dailyUsed = (currentDay > userData.lastResetDay) ? 0 : userData.dailyUsed;
        uint256 weeklyUsed = (currentWeek > userData.lastResetWeek) ? 0 : userData.weeklyUsed;

        dailyAvailable = userData.dailyLimit > dailyUsed ? userData.dailyLimit - dailyUsed : 0;
        weeklyAvailable = userData.weeklyLimit > weeklyUsed ? userData.weeklyLimit - weeklyUsed : 0;
    }

    /**
     * @notice Obtiene todas las ofertas activas
     * @return offers Array de IDs de ofertas activas
     */
    function getActiveOffers() external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        
        // Contar ofertas activas
        for (uint256 i = 1; i <= offerCount; i++) {
            if (platformOffers[i].isActive) {
                activeCount++;
            }
        }

        // Construir array
        uint256[] memory activeOffers = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= offerCount; i++) {
            if (platformOffers[i].isActive) {
                activeOffers[index] = i;
                index++;
            }
        }

        return activeOffers;
    }

    /**
     * @notice Obtiene los swaps de un usuario
     * @param user Dirección del usuario
     * @return swaps Array de IDs de swaps
     */
    function getUserSwapHistory(address user) external view returns (uint256[] memory) {
        return userSwaps[user];
    }

    /**
     * @notice Obtiene todos los usuarios preferenciales activos
     * @return users Array de direcciones
     */
    function getAllPreferredUsers() external view returns (address[] memory) {
        return preferredUsersList;
    }

    // ============================================
    // FUNCIONES ADMINISTRATIVAS
    // ============================================

    /**
     * @notice Actualiza la wallet de la plataforma
     * @param newPlatformWallet Nueva dirección
     */
    function setPlatformWallet(address newPlatformWallet) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(newPlatformWallet != address(0), "Invalid wallet");
        address oldWallet = platformWallet;
        platformWallet = newPlatformWallet;
        emit PlatformWalletUpdated(oldWallet, newPlatformWallet);
    }

    /**
     * @notice Activa/desactiva modo de mantenimiento
     * @param enabled True para activar, False para desactivar
     */
    function setMaintenanceMode(bool enabled) external onlyRole(ADMIN_ROLE) {
        maintenanceMode = enabled;
        emit MaintenanceModeToggled(enabled);
    }

    /**
     * @notice Pausa el contrato
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Despausa el contrato
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Retira tokens atrapados en el contrato
     * @param token Dirección del token
     * @param to Dirección destino
     * @param amount Cantidad a retirar
     */
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }
}
