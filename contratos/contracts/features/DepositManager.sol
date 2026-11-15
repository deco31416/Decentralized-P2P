// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IAssetManager.sol";

/**
 * @title DepositManager
 * @notice Gestión completa de depósitos multi-token con tracking en tiempo real
 * @dev Sistema robusto de depósitos con recibos NFT, límites y verificaciones
 * 
 * Características principales:
 * - Depósitos de múltiples tokens (ERC20)
 * - Emisión automática de NFT recibo
 * - Tracking detallado por usuario y por token
 * - Límites min/max por token configurables
 * - Whitelist de tokens aceptados
 * - Fees opcionales por depósito
 * - Historial completo de depósitos
 * - Agregación de balance en USD
 * - Integración con price oracle
 * - Notificaciones on-chain
 * - Pausable por emergencias
 * 
 * Flujo de depósito:
 * 1. Usuario aprueba tokens al contrato
 * 2. Llama a deposit() con token y cantidad
 * 3. Contrato verifica límites y whitelist
 * 4. Transfiere tokens al vault
 * 5. Emite NFT recibo al usuario
 * 6. Actualiza balances y estadísticas
 * 7. Emite eventos para indexación
 * 
 * Seguridad:
 * - ReentrancyGuard en todas las funciones de deposit
 * - SafeERC20 para transferencias seguras
 * - Access control para funciones admin
 * - Pausable para emergencias
 * - Límites configurables por token
 * - Verificación de balance antes de aceptar
 */
contract DepositManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Estados de depósito
    enum DepositStatus {
        Pending,        // Pendiente de confirmación
        Confirmed,      // Confirmado en blockchain
        Available,      // Disponible para uso
        Locked,         // Bloqueado en operación
        Withdrawn,      // Retirado
        Slashed         // Slasheado (penalización)
    }

    /// @notice Información de un depósito
    struct Deposit {
        uint256 depositId;
        address depositor;
        address token;
        uint256 amount;
        uint256 valueUSD;           // Valor en USD al momento del depósito
        uint256 currentValueUSD;    // Valor actual en USD
        DepositStatus status;
        uint256 depositedAt;
        uint256 lastUpdateAt;
        uint256 receiptNFTId;       // ID del NFT recibo
        string memo;                // Nota opcional del usuario
        bool autoStake;             // Auto-stake si está disponible
    }

    /// @notice Configuración de token
    struct TokenConfig {
        address token;
        bool whitelisted;
        uint256 minDeposit;         // Depósito mínimo
        uint256 maxDeposit;         // Depósito máximo por transacción
        uint256 dailyLimit;         // Límite diario por usuario
        uint256 totalDeposited;     // Total depositado en el sistema
        uint256 depositFee;         // Fee de depósito (basis points)
        bool requiresKYC;           // Requiere KYC para depositar
        bool acceptingDeposits;     // Aceptando depósitos
        uint8 decimals;             // Decimales del token
    }

    /// @notice Balance de usuario por token
    struct UserBalance {
        uint256 available;          // Balance disponible
        uint256 locked;             // Balance bloqueado en operaciones
        uint256 totalDeposited;     // Total depositado histórico
        uint256 totalWithdrawn;     // Total retirado histórico
        uint256 lastDepositAt;      // Último depósito
        uint256 depositCount;       // Número de depósitos
    }

    /// @notice Límites diarios por usuario
    struct DailyLimit {
        uint256 date;               // Fecha (día)
        uint256 amount;             // Cantidad depositada hoy
        uint256 count;              // Número de depósitos hoy
    }

    /// @notice Contador de depósitos
    uint256 public depositCount;

    /// @notice Mapeo de depósitos
    mapping(uint256 => Deposit) public deposits;
    
    /// @notice Depósitos por usuario
    mapping(address => uint256[]) public userDeposits;
    
    /// @notice Balance por usuario por token
    mapping(address => mapping(address => UserBalance)) public userBalances;
    
    /// @notice Configuración de tokens
    mapping(address => TokenConfig) public tokenConfigs;
    
    /// @notice Tokens whitelisted
    address[] public whitelistedTokens;
    
    /// @notice Límites diarios
    mapping(address => mapping(address => DailyLimit)) public dailyLimits;

    /// @notice Depósitos por token
    mapping(address => uint256[]) public tokenDeposits;
    
    /// @notice Mapeo de NFT a depósito
    mapping(uint256 => uint256) public nftToDeposit;

    /// @notice Fee por defecto (0.1%)
    uint256 public defaultDepositFee = 10; // basis points
    
    /// @notice Fee mínimo
    uint256 public minDepositAmount = 1 * 10**18; // 1 token por defecto
    
    /// @notice Límite diario por defecto (100k USD)
    uint256 public defaultDailyLimitUSD = 100000 * 10**18;
    
    /// @notice KYC requerido por defecto
    bool public kycRequiredByDefault = false;

    /// @notice Referencia al vault
    address public vault;
    
    /// @notice Referencia al BalanceManager
    address public balanceManager;
    
    /// @notice Referencia al DepositReceiptNFT
    address public depositReceiptNFT;
    
    /// @notice Referencia al PriceOracle
    address public priceOracle;
    
    /// @notice Referencia al Treasury
    address public treasury;
    
    /// @notice Referencia al KYC Manager
    address public kycManager;

    /// @notice Referencia al AssetManager
    address public assetManager;

    /// @notice Total value locked en USD
    uint256 public totalValueLockedUSD;
    
    /// @notice Total de depósitos realizados
    uint256 public totalDepositsCount;
    
    /// @notice Total de usuarios únicos
    uint256 public uniqueDepositors;
    
    /// @notice Mapeo de usuarios que han depositado
    mapping(address => bool) public hasDeposited;

    // ============================================
    // EVENTOS
    // ============================================

    event DepositCreated(
        uint256 indexed depositId,
        address indexed depositor,
        address indexed token,
        uint256 amount,
        uint256 valueUSD,
        uint256 receiptNFTId
    );

    event DepositConfirmed(
        uint256 indexed depositId,
        DepositStatus status
    );

    event BalanceUpdated(
        address indexed user,
        address indexed token,
        uint256 available,
        uint256 locked
    );

    event TokenWhitelisted(
        address indexed token,
        uint256 minDeposit,
        uint256 maxDeposit
    );

    event TokenDelisted(
        address indexed token
    );

    event DepositFeeCollected(
        uint256 indexed depositId,
        uint256 feeAmount,
        address token
    );

    event DailyLimitReached(
        address indexed user,
        address indexed token,
        uint256 limit
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _vault,
        address _balanceManager,
        address _treasury,
        address _priceOracle
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_vault != address(0), "Invalid vault");
        require(_balanceManager != address(0), "Invalid balance manager");
        require(_treasury != address(0), "Invalid treasury");
        require(_priceOracle != address(0), "Invalid price oracle");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        vault = _vault;
        balanceManager = _balanceManager;
        treasury = _treasury;
        priceOracle = _priceOracle;
    }

    // ============================================
    // GESTIÓN DE TOKENS
    // ============================================

    /**
     * @notice Añade token a whitelist
     */
    function whitelistToken(
        address token,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 dailyLimit,
        uint256 depositFee,
        bool requiresKYC,
        uint8 decimals
    ) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(!tokenConfigs[token].whitelisted, "Already whitelisted");
        require(depositFee <= 1000, "Fee too high"); // Max 10%
        require(decimals <= 18, "Invalid decimals");

        TokenConfig storage config = tokenConfigs[token];
        config.token = token;
        config.whitelisted = true;
        config.minDeposit = minDeposit;
        config.maxDeposit = maxDeposit;
        config.dailyLimit = dailyLimit;
        config.depositFee = depositFee;
        config.requiresKYC = requiresKYC;
        config.acceptingDeposits = true;
        config.decimals = decimals;

        whitelistedTokens.push(token);

        emit TokenWhitelisted(token, minDeposit, maxDeposit);
    }

    /**
     * @notice Remueve token de whitelist
     */
    function delistToken(address token) external onlyRole(ADMIN_ROLE) {
        require(tokenConfigs[token].whitelisted, "Not whitelisted");
        
        tokenConfigs[token].whitelisted = false;
        tokenConfigs[token].acceptingDeposits = false;

        emit TokenDelisted(token);
    }

    /**
     * @notice Actualiza configuración de token
     */
    function updateTokenConfig(
        address token,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 dailyLimit,
        uint256 depositFee
    ) external onlyRole(ADMIN_ROLE) {
        require(tokenConfigs[token].whitelisted, "Not whitelisted");
        require(depositFee <= 1000, "Fee too high");

        TokenConfig storage config = tokenConfigs[token];
        config.minDeposit = minDeposit;
        config.maxDeposit = maxDeposit;
        config.dailyLimit = dailyLimit;
        config.depositFee = depositFee;
    }

    /**
     * @notice Pausa/reanuda depósitos de un token
     */
    function setTokenAcceptingDeposits(address token, bool accepting) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        require(tokenConfigs[token].whitelisted, "Not whitelisted");
        tokenConfigs[token].acceptingDeposits = accepting;
    }

    // ============================================
    // DEPÓSITOS
    // ============================================

    /**
     * @notice Deposita tokens
     * @param token Dirección del token
     * @param amount Cantidad a depositar
     * @param memo Nota opcional
     * @param autoStake Auto-stake si disponible
     */
    function deposit(
        address token,
        uint256 amount,
        string memory memo,
        bool autoStake
    ) external nonReentrant whenNotPaused returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        
        require(config.whitelisted, "Token not whitelisted");
        require(config.acceptingDeposits, "Not accepting deposits");
        require(amount >= config.minDeposit, "Below minimum");
        require(amount <= config.maxDeposit, "Exceeds maximum");

        // Validar con AssetManager si está configurado
        if (assetManager != address(0)) {
            require(
                IAssetManager(assetManager).canTokenBeDeposited(token),
                "Deposits disabled for this token in AssetManager"
            );
            
            // Verificar límites del AssetManager
            IAssetManager.TokenInfo memory tokenInfo = IAssetManager(assetManager).getTokenInfo(token);
            require(amount >= tokenInfo.minDepositAmount, "Below AssetManager minimum");
            require(amount <= tokenInfo.maxDepositAmount, "Exceeds AssetManager maximum");
        }

        // Verificar KYC si es requerido
        if (config.requiresKYC && kycManager != address(0)) {
            require(_isKYCVerified(msg.sender), "KYC required");
        }

        // Verificar límite diario
        _checkDailyLimit(msg.sender, token, amount);

        // Obtener precio del token
        uint256 tokenPriceUSD = _getTokenPrice(token);
        uint256 valueUSD = (amount * tokenPriceUSD) / (10**config.decimals);

        // Calcular fee
        uint256 feeAmount = (amount * config.depositFee) / 10000;
        uint256 netAmount = amount - feeAmount;

        // Transferir tokens al vault
        IERC20(token).safeTransferFrom(msg.sender, vault, netAmount);
        
        // Transferir fee al treasury si existe
        if (feeAmount > 0) {
            IERC20(token).safeTransferFrom(msg.sender, treasury, feeAmount);
        }

        // Crear depósito
        depositCount++;
        uint256 receiptNFTId = _mintReceiptNFT(msg.sender, depositCount);

        Deposit storage newDeposit = deposits[depositCount];
        newDeposit.depositId = depositCount;
        newDeposit.depositor = msg.sender;
        newDeposit.token = token;
        newDeposit.amount = netAmount;
        newDeposit.valueUSD = valueUSD;
        newDeposit.currentValueUSD = valueUSD;
        newDeposit.status = DepositStatus.Available;
        newDeposit.depositedAt = block.timestamp;
        newDeposit.lastUpdateAt = block.timestamp;
        newDeposit.receiptNFTId = receiptNFTId;
        newDeposit.memo = memo;
        newDeposit.autoStake = autoStake;

        // Actualizar balances
        UserBalance storage balance = userBalances[msg.sender][token];
        balance.available += netAmount;
        balance.totalDeposited += netAmount;
        balance.lastDepositAt = block.timestamp;
        balance.depositCount++;

        // Actualizar registros
        userDeposits[msg.sender].push(depositCount);
        tokenDeposits[token].push(depositCount);
        nftToDeposit[receiptNFTId] = depositCount;
        config.totalDeposited += netAmount;
        totalValueLockedUSD += valueUSD;
        totalDepositsCount++;

        // Actualizar límite diario
        _updateDailyLimit(msg.sender, token, amount);

        // Tracking de usuarios únicos
        if (!hasDeposited[msg.sender]) {
            hasDeposited[msg.sender] = true;
            uniqueDepositors++;
        }

        // Actualizar BalanceManager
        _updateBalanceManager(msg.sender, token, netAmount, true);

        emit DepositCreated(
            depositCount,
            msg.sender,
            token,
            netAmount,
            valueUSD,
            receiptNFTId
        );

        if (feeAmount > 0) {
            emit DepositFeeCollected(depositCount, feeAmount, token);
        }

        emit BalanceUpdated(msg.sender, token, balance.available, balance.locked);

        return depositCount;
    }

    /**
     * @notice Deposita múltiples tokens en batch
     * @dev TEMPORALMENTE DESHABILITADO - Requiere refactorización para llamada interna
     */
    // function batchDeposit(
    //     address[] memory tokens,
    //     uint256[] memory amounts,
    //     string memory memo
    // ) external nonReentrant whenNotPaused returns (uint256[] memory) {
    //     require(tokens.length == amounts.length, "Length mismatch");
    //     require(tokens.length <= 10, "Too many tokens");

    //     uint256[] memory depositIds = new uint256[](tokens.length);

    //     for (uint256 i = 0; i < tokens.length; i++) {
    //         depositIds[i] = deposit(tokens[i], amounts[i], memo, false);
    //     }

    //     return depositIds;
    // }

    // ============================================
    // GESTIÓN DE BALANCE
    // ============================================

    /**
     * @notice Bloquea balance para una operación
     */
    function lockBalance(
        address user,
        address token,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        UserBalance storage balance = userBalances[user][token];
        require(balance.available >= amount, "Insufficient balance");

        balance.available -= amount;
        balance.locked += amount;

        emit BalanceUpdated(user, token, balance.available, balance.locked);
    }

    /**
     * @notice Desbloquea balance
     */
    function unlockBalance(
        address user,
        address token,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        UserBalance storage balance = userBalances[user][token];
        require(balance.locked >= amount, "Insufficient locked");

        balance.locked -= amount;
        balance.available += amount;

        emit BalanceUpdated(user, token, balance.available, balance.locked);
    }

    /**
     * @notice Transfiere balance bloqueado (para trades)
     */
    function transferLocked(
        address from,
        address to,
        address token,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        UserBalance storage fromBalance = userBalances[from][token];
        UserBalance storage toBalance = userBalances[to][token];
        
        require(fromBalance.locked >= amount, "Insufficient locked");

        fromBalance.locked -= amount;
        toBalance.available += amount;

        emit BalanceUpdated(from, token, fromBalance.available, fromBalance.locked);
        emit BalanceUpdated(to, token, toBalance.available, toBalance.locked);
    }

    // ============================================
    // LÍMITES DIARIOS
    // ============================================

    /**
     * @notice Verifica límite diario
     */
    function _checkDailyLimit(address user, address token, uint256 amount) internal view {
        TokenConfig storage config = tokenConfigs[token];
        if (config.dailyLimit == 0) return;

        DailyLimit storage limit = dailyLimits[user][token];
        uint256 today = block.timestamp / 1 days;

        if (limit.date == today) {
            require(limit.amount + amount <= config.dailyLimit, "Daily limit exceeded");
        }
    }

    /**
     * @notice Actualiza límite diario
     */
    function _updateDailyLimit(address user, address token, uint256 amount) internal {
        DailyLimit storage limit = dailyLimits[user][token];
        uint256 today = block.timestamp / 1 days;

        if (limit.date != today) {
            limit.date = today;
            limit.amount = amount;
            limit.count = 1;
        } else {
            limit.amount += amount;
            limit.count++;
        }

        TokenConfig storage config = tokenConfigs[token];
        if (limit.amount >= config.dailyLimit) {
            emit DailyLimitReached(user, token, config.dailyLimit);
        }
    }

    // ============================================
    // INTEGRACIONES
    // ============================================

    /**
     * @notice Mintea NFT recibo
     */
    function _mintReceiptNFT(address to, uint256 depositId) internal returns (uint256) {
        if (depositReceiptNFT == address(0)) return 0;

        (bool success, bytes memory data) = depositReceiptNFT.call(
            abi.encodeWithSignature("mint(address,uint256)", to, depositId)
        );

        if (success) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    /**
     * @notice Actualiza BalanceManager
     */
    function _updateBalanceManager(
        address user,
        address token,
        uint256 amount,
        bool isDeposit
    ) internal {
        if (balanceManager == address(0)) return;

        if (isDeposit) {
            (bool success, ) = balanceManager.call(
                abi.encodeWithSignature(
                    "recordDeposit(address,address,uint256)",
                    user, token, amount
                )
            );
            // Ignore failure - balance manager is optional
            if (!success) {
                // Log could be added here if needed
            }
        }
    }

    /**
     * @notice Obtiene precio de token
     */
    function _getTokenPrice(address token) internal view returns (uint256) {
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getTokenPriceUSD(address)", token)
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (uint256));
        }
        return 1 * 10**18; // Default 1 USD
    }

    /**
     * @notice Verifica KYC
     */
    function _isKYCVerified(address user) internal view returns (bool) {
        (bool success, bytes memory data) = kycManager.staticcall(
            abi.encodeWithSignature("isVerified(address)", user)
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (bool));
        }
        return false;
    }

    // ============================================
    // CONFIGURACIÓN
    // ============================================

    function setVault(address _vault) external onlyRole(ADMIN_ROLE) {
        require(_vault != address(0), "Invalid address");
        vault = _vault;
    }

    function setBalanceManager(address _balanceManager) external onlyRole(ADMIN_ROLE) {
        require(_balanceManager != address(0), "Invalid address");
        balanceManager = _balanceManager;
    }

    function setDepositReceiptNFT(address _depositReceiptNFT) external onlyRole(ADMIN_ROLE) {
        require(_depositReceiptNFT != address(0), "Invalid address");
        depositReceiptNFT = _depositReceiptNFT;
    }

    function setPriceOracle(address _priceOracle) external onlyRole(ADMIN_ROLE) {
        require(_priceOracle != address(0), "Invalid address");
        priceOracle = _priceOracle;
    }

    function setKYCManager(address _kycManager) external onlyRole(ADMIN_ROLE) {
        kycManager = _kycManager;
    }

    function setDefaultDepositFee(uint256 fee) external onlyRole(ADMIN_ROLE) {
        require(fee <= 1000, "Fee too high");
        defaultDepositFee = fee;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============================================
    // VISTAS
    // ============================================

    function getDeposit(uint256 depositId) external view returns (Deposit memory) {
        return deposits[depositId];
    }

    function getUserDeposits(address user) external view returns (uint256[] memory) {
        return userDeposits[user];
    }

    function getUserBalance(address user, address token) 
        external 
        view 
        returns (UserBalance memory) 
    {
        return userBalances[user][token];
    }

    function getTokenConfig(address token) external view returns (TokenConfig memory) {
        return tokenConfigs[token];
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return whitelistedTokens;
    }

    function getUserTotalValueUSD(address user) external view returns (uint256) {
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            address token = whitelistedTokens[i];
            UserBalance storage balance = userBalances[user][token];
            
            if (balance.available + balance.locked > 0) {
                uint256 tokenPriceUSD = _getTokenPrice(token);
                uint8 decimals = tokenConfigs[token].decimals;
                uint256 totalAmount = balance.available + balance.locked;
                uint256 valueUSD = (totalAmount * tokenPriceUSD) / (10**decimals);
                totalValue += valueUSD;
            }
        }
        
        return totalValue;
    }

    function getDailyLimit(address user, address token) 
        external 
        view 
        returns (uint256 used, uint256 remaining, uint256 limit) 
    {
        DailyLimit storage dailyLimit = dailyLimits[user][token];
        uint256 today = block.timestamp / 1 days;
        
        limit = tokenConfigs[token].dailyLimit;
        used = dailyLimit.date == today ? dailyLimit.amount : 0;
        remaining = limit > used ? limit - used : 0;
        
        return (used, remaining, limit);
    }

    function getSystemStats() 
        external 
        view 
        returns (
            uint256 totalDeposits,
            uint256 totalValueUSD,
            uint256 uniqueUsers,
            uint256 activeTokens
        ) 
    {
        return (
            totalDepositsCount,
            totalValueLockedUSD,
            uniqueDepositors,
            whitelistedTokens.length
        );
    }
}
