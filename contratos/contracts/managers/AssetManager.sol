// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AssetManager
 * @notice Gestión centralizada de tokens, stablecoins, cryptos y métodos de pago
 * @dev Hub central para configurar qué activos están disponibles en el ecosistema
 * 
 * Características principales:
 * - Whitelist de tokens ERC20 (cryptos, stablecoins)
 * - Registro de métodos de pago fiat
 * - Configuración de límites por activo
 * - Sistema de categorización
 * - Metadatos de cada activo
 * - Control de quién puede agregar activos
 * 
 * Roles y permisos:
 * - ADMIN_ROLE: Puede agregar/remover cualquier activo, cambiar límites
 * - ASSET_MANAGER_ROLE: Puede agregar tokens crypto/stable (no fiat methods)
 * - PAYMENT_MANAGER_ROLE: Puede agregar métodos de pago fiat
 * - OPERATOR_ROLE: Puede activar/desactivar temporalmente activos
 * 
 * Flujo de trabajo:
 * 1. Admin/Manager agrega token crypto → Verifica contrato → Whitelist
 * 2. Admin/Manager agrega stablecoin → Categoriza → Configura límites
 * 3. Payment Manager agrega método fiat → Define países → Configura fees
 * 4. Otros contratos consultan isTokenSupported() antes de aceptar
 * 
 * Integraciones:
 * - BalanceManager: Consulta tokens soportados
 * - P2PExchange: Consulta qué tokens se pueden tradear
 * - Bridges: Consulta métodos de pago fiat disponibles
 * - DepositManager/WithdrawManager: Valida tokens antes de procesar
 */
contract AssetManager is AccessControl, Pausable {

    /// @notice Rol de administrador general
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol para gestionar assets crypto/stable
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    
    /// @notice Rol para gestionar métodos de pago fiat
    bytes32 public constant PAYMENT_MANAGER_ROLE = keccak256("PAYMENT_MANAGER_ROLE");
    
    /// @notice Rol de operador (activar/desactivar)
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Categorías de tokens
    enum TokenCategory {
        Cryptocurrency,     // Bitcoin, Ethereum, BNB, etc
        Stablecoin,        // USDT, USDC, DAI, etc
        Utility,           // Token CAMBIO, governance
        Synthetic,         // Tokens sintéticos
        NFT,               // Para futuro soporte NFT
        Other              // Otros
    }

    /// @notice Tipos de métodos de pago fiat
    enum FiatPaymentType {
        BankTransfer,      // Transferencia bancaria
        Cash,              // Efectivo en persona
        MobilePayment,     // Pago móvil
        OnlineWallet,      // Wallets digitales (PayPal, Zelle, etc)
        Cryptocurrency,    // Stablecoins (USDT, USDC como fiat)
        Other              // Otros
    }

    /// @notice Información completa de un token
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
        string logoURI;            // URL del logo
        string website;            // Website oficial
        bool verified;             // Verificado por el equipo
    }

    /// @notice Información de método de pago fiat
    struct FiatPaymentMethod {
        uint256 methodId;
        string name;               // "Zelle", "Banco de Venezuela", etc
        string code;               // "ZELLE", "BOV", etc
        FiatPaymentType paymentType;
        string[] supportedCurrencies; // ["USD", "EUR", "VES"]
        string[] supportedCountries;  // ["US", "VE", "MX"]
        bool isActive;
        bool requiresKYC;
        uint256 minAmount;         // Mínimo en USD equivalente
        uint256 maxAmount;         // Máximo en USD equivalente
        uint256 processingTime;    // Tiempo estimado en segundos
        uint256 feePercentage;     // Fee en basis points (100 = 1%)
        uint256 addedAt;
        address addedBy;
        string logoURI;
        string instructions;       // Instrucciones de uso
    }

    /// @notice Mapeo de token address → información
    mapping(address => TokenInfo) public tokens;
    
    /// @notice Lista de tokens soportados
    address[] public supportedTokens;
    
    /// @notice Índice de token en el array
    mapping(address => uint256) public tokenIndex;
    
    /// @notice Verificar si token está soportado
    mapping(address => bool) public isTokenSupported;

    /// @notice Mapeo de methodId → información
    mapping(uint256 => FiatPaymentMethod) public fiatMethods;
    
    /// @notice Lista de métodos de pago
    uint256[] public supportedFiatMethods;
    
    /// @notice Contador de métodos de pago
    uint256 public fiatMethodCount;

    /// @notice Métodos de pago por país
    mapping(string => uint256[]) public methodsByCountry;
    
    /// @notice Métodos de pago por moneda
    mapping(string => uint256[]) public methodsByCurrency;
    
    /// @notice Métodos de pago por tipo
    mapping(FiatPaymentType => uint256[]) public methodsByType;

    /// @notice Tokens por categoría
    mapping(TokenCategory => address[]) public tokensByCategory;

    // ============================================
    // EVENTOS
    // ============================================

    event TokenAdded(
        address indexed token,
        string symbol,
        TokenCategory category,
        address indexed addedBy
    );

    event TokenUpdated(
        address indexed token,
        string symbol,
        bool isActive
    );

    event TokenRemoved(
        address indexed token,
        string symbol,
        address indexed removedBy
    );

    event TokenActivated(address indexed token, address indexed by);
    event TokenDeactivated(address indexed token, address indexed by);

    event FiatMethodAdded(
        uint256 indexed methodId,
        string name,
        FiatPaymentType paymentType,
        address indexed addedBy
    );

    event FiatMethodUpdated(
        uint256 indexed methodId,
        string name,
        bool isActive
    );

    event FiatMethodRemoved(
        uint256 indexed methodId,
        address indexed removedBy
    );

    event LimitsUpdated(
        address indexed token,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 minWithdraw,
        uint256 maxWithdraw
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(address admin) {
        require(admin != address(0), "Invalid admin");
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ASSET_MANAGER_ROLE, admin);
        _grantRole(PAYMENT_MANAGER_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    // ============================================
    // TOKEN MANAGEMENT (CRYPTO & STABLECOINS)
    // ============================================

    /**
     * @notice Agrega un nuevo token al sistema
     * @param tokenAddress Dirección del contrato ERC20
     * @param symbol Símbolo del token (BTC, ETH, USDT, etc)
     * @param name Nombre completo
     * @param decimals Decimales del token
     * @param category Categoría del token
     * @param logoURI URL del logo
     * @param website Website oficial
     * 
     * Requiere: ADMIN_ROLE o ASSET_MANAGER_ROLE
     */
    function addToken(
        address tokenAddress,
        string memory symbol,
        string memory name,
        uint8 decimals,
        TokenCategory category,
        string memory logoURI,
        string memory website
    ) 
        external 
        whenNotPaused
    {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || hasRole(ASSET_MANAGER_ROLE, msg.sender),
            "Unauthorized: Need ADMIN or ASSET_MANAGER role"
        );
        require(tokenAddress != address(0), "Invalid token address");
        require(!isTokenSupported[tokenAddress], "Token already added");
        require(bytes(symbol).length > 0, "Symbol required");
        require(decimals > 0 && decimals <= 18, "Invalid decimals");

        // Crear info del token
        tokens[tokenAddress] = TokenInfo({
            tokenAddress: tokenAddress,
            symbol: symbol,
            name: name,
            decimals: decimals,
            category: category,
            isActive: true,
            canDeposit: true,
            canWithdraw: true,
            canTrade: true,
            canStake: false, // Por defecto false, admin activa después
            minDepositAmount: 0,
            maxDepositAmount: type(uint256).max,
            minWithdrawAmount: 0,
            maxWithdrawAmount: type(uint256).max,
            dailyDepositLimit: 0, // 0 = sin límite
            dailyWithdrawLimit: 0, // 0 = sin límite
            addedAt: block.timestamp,
            addedBy: msg.sender,
            logoURI: logoURI,
            website: website,
            verified: false // Admin marca como verified después
        });

        // Agregar a listas
        tokenIndex[tokenAddress] = supportedTokens.length;
        supportedTokens.push(tokenAddress);
        isTokenSupported[tokenAddress] = true;
        tokensByCategory[category].push(tokenAddress);

        emit TokenAdded(tokenAddress, symbol, category, msg.sender);
    }

    /**
     * @notice Actualiza información de un token
     * @param tokenAddress Dirección del token
     * @param canDeposit Permitir depósitos
     * @param canWithdraw Permitir retiros
     * @param canTrade Permitir trading
     * @param canStake Permitir staking
     * 
     * Requiere: ADMIN_ROLE
     */
    function updateTokenPermissions(
        address tokenAddress,
        bool canDeposit,
        bool canWithdraw,
        bool canTrade,
        bool canStake
    ) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        require(isTokenSupported[tokenAddress], "Token not supported");

        TokenInfo storage token = tokens[tokenAddress];
        token.canDeposit = canDeposit;
        token.canWithdraw = canWithdraw;
        token.canTrade = canTrade;
        token.canStake = canStake;

        emit TokenUpdated(tokenAddress, token.symbol, token.isActive);
    }

    /**
     * @notice Configura límites de un token
     * @param tokenAddress Dirección del token
     * @param minDeposit Mínimo depósito
     * @param maxDeposit Máximo depósito
     * @param minWithdraw Mínimo retiro
     * @param maxWithdraw Máximo retiro
     * @param dailyDepositLimit Límite diario de depósitos
     * @param dailyWithdrawLimit Límite diario de retiros
     * 
     * Requiere: ADMIN_ROLE
     */
    function setTokenLimits(
        address tokenAddress,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 minWithdraw,
        uint256 maxWithdraw,
        uint256 dailyDepositLimit,
        uint256 dailyWithdrawLimit
    ) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        require(isTokenSupported[tokenAddress], "Token not supported");
        require(minDeposit <= maxDeposit, "Invalid deposit limits");
        require(minWithdraw <= maxWithdraw, "Invalid withdraw limits");

        TokenInfo storage token = tokens[tokenAddress];
        token.minDepositAmount = minDeposit;
        token.maxDepositAmount = maxDeposit;
        token.minWithdrawAmount = minWithdraw;
        token.maxWithdrawAmount = maxWithdraw;
        token.dailyDepositLimit = dailyDepositLimit;
        token.dailyWithdrawLimit = dailyWithdrawLimit;

        emit LimitsUpdated(
            tokenAddress,
            minDeposit,
            maxDeposit,
            minWithdraw,
            maxWithdraw
        );
    }

    /**
     * @notice Marca un token como verificado
     * @param tokenAddress Dirección del token
     * 
     * Requiere: ADMIN_ROLE
     */
    function verifyToken(address tokenAddress) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        require(isTokenSupported[tokenAddress], "Token not supported");
        tokens[tokenAddress].verified = true;
        emit TokenUpdated(tokenAddress, tokens[tokenAddress].symbol, true);
    }

    /**
     * @notice Activa un token temporalmente desactivado
     * @param tokenAddress Dirección del token
     * 
     * Requiere: ADMIN_ROLE o OPERATOR_ROLE
     */
    function activateToken(address tokenAddress) 
        external 
    {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || hasRole(OPERATOR_ROLE, msg.sender),
            "Unauthorized"
        );
        require(isTokenSupported[tokenAddress], "Token not supported");

        tokens[tokenAddress].isActive = true;
        emit TokenActivated(tokenAddress, msg.sender);
    }

    /**
     * @notice Desactiva un token temporalmente
     * @param tokenAddress Dirección del token
     * 
     * Requiere: ADMIN_ROLE o OPERATOR_ROLE
     */
    function deactivateToken(address tokenAddress) 
        external 
    {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || hasRole(OPERATOR_ROLE, msg.sender),
            "Unauthorized"
        );
        require(isTokenSupported[tokenAddress], "Token not supported");

        tokens[tokenAddress].isActive = false;
        emit TokenDeactivated(tokenAddress, msg.sender);
    }

    /**
     * @notice Remueve completamente un token del sistema
     * @param tokenAddress Dirección del token
     * 
     * Requiere: ADMIN_ROLE
     * Precaución: Solo usar si el token está obsoleto o es scam
     */
    function removeToken(address tokenAddress) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        require(isTokenSupported[tokenAddress], "Token not supported");

        // Obtener info antes de borrar
        string memory symbol = tokens[tokenAddress].symbol;

        // Remover de array usando swap & pop
        uint256 index = tokenIndex[tokenAddress];
        uint256 lastIndex = supportedTokens.length - 1;

        if (index != lastIndex) {
            address lastToken = supportedTokens[lastIndex];
            supportedTokens[index] = lastToken;
            tokenIndex[lastToken] = index;
        }

        supportedTokens.pop();
        delete tokenIndex[tokenAddress];
        delete tokens[tokenAddress];
        isTokenSupported[tokenAddress] = false;

        emit TokenRemoved(tokenAddress, symbol, msg.sender);
    }

    // ============================================
    // FIAT PAYMENT METHODS MANAGEMENT
    // ============================================

    /**
     * @notice Agrega un nuevo método de pago fiat
     * @param name Nombre del método (ej: "Zelle", "Banco Mercantil")
     * @param code Código único (ej: "ZELLE", "MERC_VE")
     * @param paymentType Tipo de método de pago
     * @param supportedCurrencies Array de monedas soportadas ["USD", "EUR"]
     * @param supportedCountries Array de países soportados ["US", "VE"]
     * @param minAmount Mínimo en USD equivalente
     * @param maxAmount Máximo en USD equivalente
     * @param processingTime Tiempo estimado en segundos
     * @param feePercentage Fee en basis points (100 = 1%)
     * @param logoURI URL del logo
     * @param instructions Instrucciones de uso
     * 
     * Requiere: ADMIN_ROLE o PAYMENT_MANAGER_ROLE
     */
    function addFiatMethod(
        string memory name,
        string memory code,
        FiatPaymentType paymentType,
        string[] memory supportedCurrencies,
        string[] memory supportedCountries,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 processingTime,
        uint256 feePercentage,
        bool requiresKYC,
        string memory logoURI,
        string memory instructions
    ) 
        external 
        whenNotPaused
        returns (uint256 methodId)
    {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || hasRole(PAYMENT_MANAGER_ROLE, msg.sender),
            "Unauthorized: Need ADMIN or PAYMENT_MANAGER role"
        );
        require(bytes(name).length > 0, "Name required");
        require(bytes(code).length > 0, "Code required");
        require(supportedCurrencies.length > 0, "At least one currency required");
        require(minAmount <= maxAmount, "Invalid amount limits");

        methodId = fiatMethodCount;
        fiatMethodCount++;

        fiatMethods[methodId] = FiatPaymentMethod({
            methodId: methodId,
            name: name,
            code: code,
            paymentType: paymentType,
            supportedCurrencies: supportedCurrencies,
            supportedCountries: supportedCountries,
            isActive: true,
            requiresKYC: requiresKYC,
            minAmount: minAmount,
            maxAmount: maxAmount,
            processingTime: processingTime,
            feePercentage: feePercentage,
            addedAt: block.timestamp,
            addedBy: msg.sender,
            logoURI: logoURI,
            instructions: instructions
        });

        supportedFiatMethods.push(methodId);

        // Indexar por país
        for (uint i = 0; i < supportedCountries.length; i++) {
            methodsByCountry[supportedCountries[i]].push(methodId);
        }

        // Indexar por moneda
        for (uint i = 0; i < supportedCurrencies.length; i++) {
            methodsByCurrency[supportedCurrencies[i]].push(methodId);
        }

        // Indexar por tipo
        methodsByType[paymentType].push(methodId);

        emit FiatMethodAdded(methodId, name, paymentType, msg.sender);
    }

    /**
     * @notice Actualiza un método de pago fiat
     * @param methodId ID del método
     * @param isActive Si está activo
     * @param minAmount Mínimo
     * @param maxAmount Máximo
     * @param feePercentage Fee
     * 
     * Requiere: ADMIN_ROLE
     */
    function updateFiatMethod(
        uint256 methodId,
        bool isActive,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 feePercentage
    ) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        require(methodId < fiatMethodCount, "Invalid method ID");

        FiatPaymentMethod storage method = fiatMethods[methodId];
        method.isActive = isActive;
        method.minAmount = minAmount;
        method.maxAmount = maxAmount;
        method.feePercentage = feePercentage;

        emit FiatMethodUpdated(methodId, method.name, isActive);
    }

    /**
     * @notice Remueve un método de pago fiat
     * @param methodId ID del método
     * 
     * Requiere: ADMIN_ROLE
     */
    function removeFiatMethod(uint256 methodId) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        require(methodId < fiatMethodCount, "Invalid method ID");

        delete fiatMethods[methodId];
        emit FiatMethodRemoved(methodId, msg.sender);
    }

    // ============================================
    // VIEW FUNCTIONS - TOKENS
    // ============================================

    /**
     * @notice Obtiene información completa de un token
     */
    function getTokenInfo(address tokenAddress) 
        external 
        view 
        returns (TokenInfo memory) 
    {
        require(isTokenSupported[tokenAddress], "Token not supported");
        return tokens[tokenAddress];
    }

    /**
     * @notice Obtiene todos los tokens soportados
     */
    function getAllTokens() 
        external 
        view 
        returns (address[] memory) 
    {
        return supportedTokens;
    }

    /**
     * @notice Obtiene tokens por categoría
     */
    function getTokensByCategory(TokenCategory category) 
        external 
        view 
        returns (address[] memory) 
    {
        return tokensByCategory[category];
    }

    /**
     * @notice Obtiene solo tokens activos
     */
    function getActiveTokens() 
        external 
        view 
        returns (address[] memory) 
    {
        uint256 activeCount = 0;
        
        // Contar activos
        for (uint i = 0; i < supportedTokens.length; i++) {
            if (tokens[supportedTokens[i]].isActive) {
                activeCount++;
            }
        }

        // Crear array
        address[] memory activeTokens = new address[](activeCount);
        uint256 index = 0;
        
        for (uint i = 0; i < supportedTokens.length; i++) {
            if (tokens[supportedTokens[i]].isActive) {
                activeTokens[index] = supportedTokens[i];
                index++;
            }
        }

        return activeTokens;
    }

    /**
     * @notice Verifica si un token puede ser depositado
     */
    function canTokenBeDeposited(address tokenAddress) 
        external 
        view 
        returns (bool) 
    {
        return isTokenSupported[tokenAddress] && 
               tokens[tokenAddress].isActive && 
               tokens[tokenAddress].canDeposit;
    }

    /**
     * @notice Verifica si un token puede ser retirado
     */
    function canTokenBeWithdrawn(address tokenAddress) 
        external 
        view 
        returns (bool) 
    {
        return isTokenSupported[tokenAddress] && 
               tokens[tokenAddress].isActive && 
               tokens[tokenAddress].canWithdraw;
    }

    /**
     * @notice Verifica si un token puede ser tradeado
     */
    function canTokenBeTraded(address tokenAddress) 
        external 
        view 
        returns (bool) 
    {
        return isTokenSupported[tokenAddress] && 
               tokens[tokenAddress].isActive && 
               tokens[tokenAddress].canTrade;
    }

    // ============================================
    // VIEW FUNCTIONS - FIAT METHODS
    // ============================================

    /**
     * @notice Obtiene información de un método de pago
     */
    function getFiatMethodInfo(uint256 methodId) 
        external 
        view 
        returns (FiatPaymentMethod memory) 
    {
        require(methodId < fiatMethodCount, "Invalid method ID");
        return fiatMethods[methodId];
    }

    /**
     * @notice Obtiene todos los métodos de pago activos
     */
    function getActiveFiatMethods() 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256 activeCount = 0;
        
        // Contar activos
        for (uint i = 0; i < supportedFiatMethods.length; i++) {
            uint256 methodId = supportedFiatMethods[i];
            if (fiatMethods[methodId].isActive) {
                activeCount++;
            }
        }

        // Crear array
        uint256[] memory activeMethods = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint i = 0; i < supportedFiatMethods.length; i++) {
            uint256 methodId = supportedFiatMethods[i];
            if (fiatMethods[methodId].isActive) {
                activeMethods[index] = methodId;
                index++;
            }
        }

        return activeMethods;
    }

    /**
     * @notice Obtiene métodos de pago por país
     */
    function getMethodsByCountry(string memory countryCode) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return methodsByCountry[countryCode];
    }

    /**
     * @notice Obtiene métodos de pago por moneda
     */
    function getMethodsByCurrency(string memory currency) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return methodsByCurrency[currency];
    }

    /**
     * @notice Obtiene métodos de pago por tipo
     */
    function getMethodsByType(FiatPaymentType paymentType) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return methodsByType[paymentType];
    }

    // ============================================
    // UTILITY FUNCTIONS
    // ============================================

    /**
     * @notice Pausa el contrato
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Despausa el contrato
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
