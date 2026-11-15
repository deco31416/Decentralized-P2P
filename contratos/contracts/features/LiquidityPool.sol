// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title LiquidityPool
 * @notice Pool de liquidez AMM (Automated Market Maker) estilo Uniswap V2
 * @dev Implementa pools de liquidez con las siguientes características:
 * 
 * CARACTERÍSTICAS:
 * - AMM con fórmula constant product: x * y = k
 * - Múltiples pares de trading (token0/token1)
 * - LP tokens: Recibos de liquidez proporcionados
 * - Fees de trading: 0.3% por swap (0.25% a LPs, 0.05% a protocolo)
 * - Slippage protection: Min amount out
 * - Price impact calculation
 * 
 * FÓRMULA CONSTANT PRODUCT:
 * - reserve0 * reserve1 = k (constante)
 * - Cuando haces swap: k debe mantenerse constante
 * - Price = reserve1 / reserve0
 * 
 * AGREGAR LIQUIDEZ:
 * 1. Usuario deposita token0 y token1 en proporción actual
 * 2. Sistema calcula LP tokens a emitir
 * 3. LP tokens = sqrt(amount0 * amount1) (primera vez)
 * 4. LP tokens = min(amount0/reserve0, amount1/reserve1) * totalSupply (después)
 * 
 * REMOVER LIQUIDEZ:
 * 1. Usuario quema LP tokens
 * 2. Sistema calcula tokens a devolver
 * 3. amount0 = (lpTokens / totalSupply) * reserve0
 * 4. amount1 = (lpTokens / totalSupply) * reserve1
 * 
 * SWAP:
 * 1. Usuario envía tokenIn
 * 2. Sistema calcula tokenOut basado en reserves
 * 3. amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
 * 4. Actualiza reserves
 * 
 * EJEMPLO SWAP:
 * - Pool: 1,000 USDT / 100 CAMBIO (ratio 10:1)
 * - Swap: 100 USDT → ? CAMBIO
 * - k = 1000 * 100 = 100,000
 * - Después del swap: 1100 USDT * x CAMBIO = 100,000
 * - x = 90.90 CAMBIO
 * - Output: 100 - 90.90 = 9.09 CAMBIO (menos fees)
 * - Con 0.3% fee: 9.09 * 0.997 = 9.06 CAMBIO
 */
contract LiquidityPool is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========================================
    // ROLES
    // ========================================
    
    bytes32 public constant POOL_ADMIN_ROLE = keccak256("POOL_ADMIN_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

    // ========================================
    // ESTRUCTURAS
    // ========================================

    /**
     * @dev Información de un pool
     */
    struct Pool {
        uint256 poolId;              // ID único del pool
        address token0;              // Primer token del par
        address token1;              // Segundo token del par
        uint256 reserve0;            // Reserva de token0
        uint256 reserve1;            // Reserva de token1
        uint256 totalLiquidity;      // Total de LP tokens emitidos
        uint256 feePercent;          // Fee en basis points (30 = 0.3%)
        uint256 protocolFeePercent;  // % del fee que va a protocolo (basis points)
        uint256 totalVolume0;        // Volumen total de token0
        uint256 totalVolume1;        // Volumen total de token1
        uint256 totalFees0;          // Fees acumulados de token0
        uint256 totalFees1;          // Fees acumulados de token1
        bool active;                 // Pool activo
        uint256 createdAt;           // Timestamp de creación
    }

    /**
     * @dev Posición de liquidez de un usuario
     */
    struct LiquidityPosition {
        uint256 poolId;              // ID del pool
        address provider;            // Proveedor de liquidez
        uint256 lpTokens;            // Cantidad de LP tokens
        uint256 token0Deposited;     // Token0 depositado originalmente
        uint256 token1Deposited;     // Token1 depositado originalmente
        uint256 addedAt;             // Timestamp cuando agregó liquidez
        uint256 feesEarned0;         // Fees ganados en token0
        uint256 feesEarned1;         // Fees ganados en token1
    }

    /**
     * @dev Información de swap
     */
    struct SwapInfo {
        uint256 amountIn;            // Cantidad de entrada
        uint256 amountOut;           // Cantidad de salida
        uint256 fee;                 // Fee cobrado
        uint256 priceImpact;         // Impacto en precio (basis points)
        uint256 newPrice;            // Nuevo precio después del swap
    }

    // ========================================
    // CONSTANTES
    // ========================================

    uint256 private constant MINIMUM_LIQUIDITY = 1000;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant FEE_DENOMINATOR = 1000;

    // ========================================
    // VARIABLES DE ESTADO
    // ========================================

    /// @notice Contador de pools
    uint256 public poolCounter;

    /// @notice Pools por ID
    mapping(uint256 => Pool) public pools;

    /// @notice Pool ID por par de tokens
    mapping(address => mapping(address => uint256)) public getPoolId;

    /// @notice LP tokens por usuario y pool
    mapping(address => mapping(uint256 => LiquidityPosition)) public liquidityPositions;

    /// @notice IDs de pools donde usuario tiene liquidez
    mapping(address => uint256[]) public userPoolIds;

    /// @notice Fees del protocolo acumulados
    mapping(address => uint256) public protocolFees;

    /// @notice Treasury que recibe protocol fees
    address public treasury;

    /// @notice Fee por defecto (30 basis points = 0.3%)
    uint256 public defaultFeePercent = 30;

    /// @notice Protocol fee por defecto (5 basis points del total = 0.05%)
    uint256 public defaultProtocolFeePercent = 5;

    /// @notice Total de pools creados
    uint256 public totalPoolsCreated;

    /// @notice Total de liquidez agregada (en USD, si oracle disponible)
    uint256 public totalLiquidityUSD;

    // ========================================
    // EVENTOS
    // ========================================

    event PoolCreated(
        uint256 indexed poolId,
        address indexed token0,
        address indexed token1,
        uint256 feePercent
    );

    event LiquidityAdded(
        uint256 indexed poolId,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 lpTokens
    );

    event LiquidityRemoved(
        uint256 indexed poolId,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 lpTokens
    );

    event Swap(
        uint256 indexed poolId,
        address indexed trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );

    event FeesCollected(
        uint256 indexed poolId,
        address indexed collector,
        uint256 amount0,
        uint256 amount1
    );

    event ProtocolFeesCollected(
        address indexed token,
        uint256 amount
    );

    event PoolStatusChanged(
        uint256 indexed poolId,
        bool active
    );

    // ========================================
    // ERRORES
    // ========================================

    error InvalidAddress();
    error InvalidAmount();
    error PoolNotFound();
    error PoolAlreadyExists();
    error PoolInactive();
    error InsufficientLiquidity();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InvalidTokenPair();
    error SlippageTooHigh();
    error IdenticalAddresses();
    error InsufficientLPTokens();
    error NoFeesToCollect();

    // ========================================
    // CONSTRUCTOR
    // ========================================

    /**
     * @notice Constructor del contrato
     * @param _treasury Treasury para protocol fees
     * @param admin Admin principal
     */
    constructor(address _treasury, address admin) {
        if (_treasury == address(0) || admin == address(0)) revert InvalidAddress();

        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POOL_ADMIN_ROLE, admin);
        _grantRole(FEE_COLLECTOR_ROLE, admin);
    }

    // ========================================
    // FUNCIONES PRINCIPALES - CREAR POOL
    // ========================================

    /**
     * @notice Crea un nuevo pool de liquidez
     * @param token0 Primer token del par
     * @param token1 Segundo token del par
     * @return poolId ID del pool creado
     */
    function createPool(address token0, address token1)
        external
        onlyRole(POOL_ADMIN_ROLE)
        returns (uint256 poolId)
    {
        if (token0 == address(0) || token1 == address(0)) revert InvalidAddress();
        if (token0 == token1) revert IdenticalAddresses();

        // Ordenar tokens (token0 < token1)
        (address tokenA, address tokenB) = token0 < token1 ? (token0, token1) : (token1, token0);

        // Verificar que no exista el pool
        if (getPoolId[tokenA][tokenB] != 0) revert PoolAlreadyExists();

        poolId = ++poolCounter;

        pools[poolId] = Pool({
            poolId: poolId,
            token0: tokenA,
            token1: tokenB,
            reserve0: 0,
            reserve1: 0,
            totalLiquidity: 0,
            feePercent: defaultFeePercent,
            protocolFeePercent: defaultProtocolFeePercent,
            totalVolume0: 0,
            totalVolume1: 0,
            totalFees0: 0,
            totalFees1: 0,
            active: true,
            createdAt: block.timestamp
        });

        // Mapear tokens a poolId (ambas direcciones)
        getPoolId[tokenA][tokenB] = poolId;
        getPoolId[tokenB][tokenA] = poolId;

        totalPoolsCreated++;

        emit PoolCreated(poolId, tokenA, tokenB, defaultFeePercent);
    }

    // ========================================
    // FUNCIONES PRINCIPALES - LIQUIDEZ
    // ========================================

    /**
     * @notice Agrega liquidez a un pool
     * @param poolId ID del pool
     * @param amount0Desired Cantidad deseada de token0
     * @param amount1Desired Cantidad deseada de token1
     * @param amount0Min Cantidad mínima de token0 (slippage protection)
     * @param amount1Min Cantidad mínima de token1 (slippage protection)
     * @return amount0 Cantidad real de token0 agregada
     * @return amount1 Cantidad real de token1 agregada
     * @return lpTokens LP tokens recibidos
     * 
     * CÁLCULO DE LP TOKENS:
     * - Primera liquidez: lpTokens = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
     * - Liquidez subsecuente: lpTokens = min(amount0 * totalLiquidity / reserve0, amount1 * totalLiquidity / reserve1)
     */
    function addLiquidity(
        uint256 poolId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amount0, uint256 amount1, uint256 lpTokens)
    {
        Pool storage pool = pools[poolId];
        if (pool.poolId == 0) revert PoolNotFound();
        if (!pool.active) revert PoolInactive();
        if (amount0Desired == 0 || amount1Desired == 0) revert InvalidAmount();

        // Calcular cantidades óptimas
        if (pool.totalLiquidity == 0) {
            // Primera liquidez: usar cantidades deseadas
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            // Liquidez subsecuente: mantener ratio
            uint256 amount1Optimal = _quote(amount0Desired, pool.reserve0, pool.reserve1);
            
            if (amount1Optimal <= amount1Desired) {
                if (amount1Optimal < amount1Min) revert InsufficientInputAmount();
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = _quote(amount1Desired, pool.reserve1, pool.reserve0);
                if (amount0Optimal > amount0Desired || amount0Optimal < amount0Min) {
                    revert InsufficientInputAmount();
                }
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        // Calcular LP tokens a emitir
        if (pool.totalLiquidity == 0) {
            // Primera liquidez: sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
            lpTokens = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            pool.totalLiquidity = MINIMUM_LIQUIDITY; // Lock permanente
        } else {
            // Liquidez subsecuente: min ratio
            lpTokens = _min(
                (amount0 * pool.totalLiquidity) / pool.reserve0,
                (amount1 * pool.totalLiquidity) / pool.reserve1
            );
        }

        if (lpTokens == 0) revert InsufficientLiquidity();

        // Actualizar reserves
        pool.reserve0 += amount0;
        pool.reserve1 += amount1;
        pool.totalLiquidity += lpTokens;

        // Actualizar posición de usuario
        LiquidityPosition storage position = liquidityPositions[msg.sender][poolId];
        if (position.lpTokens == 0) {
            // Nueva posición
            position.poolId = poolId;
            position.provider = msg.sender;
            position.addedAt = block.timestamp;
            userPoolIds[msg.sender].push(poolId);
        }
        
        position.lpTokens += lpTokens;
        position.token0Deposited += amount0;
        position.token1Deposited += amount1;

        // Transferir tokens al pool
        IERC20(pool.token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(pool.token1).safeTransferFrom(msg.sender, address(this), amount1);

        emit LiquidityAdded(poolId, msg.sender, amount0, amount1, lpTokens);
    }

    /**
     * @notice Remueve liquidez de un pool
     * @param poolId ID del pool
     * @param lpTokens Cantidad de LP tokens a quemar
     * @param amount0Min Cantidad mínima de token0 a recibir
     * @param amount1Min Cantidad mínima de token1 a recibir
     * @return amount0 Cantidad de token0 recibida
     * @return amount1 Cantidad de token1 recibida
     * 
     * CÁLCULO:
     * - amount0 = (lpTokens / totalLiquidity) * reserve0
     * - amount1 = (lpTokens / totalLiquidity) * reserve1
     */
    function removeLiquidity(
        uint256 poolId,
        uint256 lpTokens,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amount0, uint256 amount1)
    {
        Pool storage pool = pools[poolId];
        if (pool.poolId == 0) revert PoolNotFound();
        if (lpTokens == 0) revert InvalidAmount();

        LiquidityPosition storage position = liquidityPositions[msg.sender][poolId];
        if (position.lpTokens < lpTokens) revert InsufficientLPTokens();

        // Calcular cantidades a devolver
        amount0 = (lpTokens * pool.reserve0) / pool.totalLiquidity;
        amount1 = (lpTokens * pool.reserve1) / pool.totalLiquidity;

        if (amount0 < amount0Min || amount1 < amount1Min) revert InsufficientOutputAmount();

        // Actualizar reserves
        pool.reserve0 -= amount0;
        pool.reserve1 -= amount1;
        pool.totalLiquidity -= lpTokens;

        // Actualizar posición
        position.lpTokens -= lpTokens;
        
        // Calcular fees ganados antes de actualizar
        uint256 feesEarned0 = (position.lpTokens > 0) 
            ? (pool.totalFees0 * position.lpTokens) / pool.totalLiquidity 
            : 0;
        uint256 feesEarned1 = (position.lpTokens > 0)
            ? (pool.totalFees1 * position.lpTokens) / pool.totalLiquidity
            : 0;

        position.feesEarned0 = feesEarned0;
        position.feesEarned1 = feesEarned1;

        // Transferir tokens al usuario
        IERC20(pool.token0).safeTransfer(msg.sender, amount0);
        IERC20(pool.token1).safeTransfer(msg.sender, amount1);

        emit LiquidityRemoved(poolId, msg.sender, amount0, amount1, lpTokens);
    }

    // ========================================
    // FUNCIONES PRINCIPALES - SWAP
    // ========================================

    /**
     * @notice Ejecuta un swap en el pool
     * @param poolId ID del pool
     * @param tokenIn Token de entrada
     * @param amountIn Cantidad de entrada
     * @param minAmountOut Cantidad mínima de salida (slippage protection)
     * @return amountOut Cantidad de salida
     * 
     * FÓRMULA SWAP (con fee 0.3%):
     * - amountInWithFee = amountIn * 997
     * - amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee)
     * 
     * EJEMPLO:
     * - Pool: 1000 USDT / 100 CAMBIO
     * - Swap: 100 USDT → ? CAMBIO
     * - amountInWithFee = 100 * 997 = 99,700
     * - amountOut = (99,700 * 100) / (1000 * 1000 + 99,700) = 9.06 CAMBIO
     */
    function swap(
        uint256 poolId,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        Pool storage pool = pools[poolId];
        if (pool.poolId == 0) revert PoolNotFound();
        if (!pool.active) revert PoolInactive();
        if (amountIn == 0) revert InvalidAmount();

        // Determinar dirección del swap
        bool isToken0 = tokenIn == pool.token0;
        if (!isToken0 && tokenIn != pool.token1) revert InvalidTokenPair();

        (uint256 reserveIn, uint256 reserveOut) = isToken0
            ? (pool.reserve0, pool.reserve1)
            : (pool.reserve1, pool.reserve0);

        // Calcular amount out
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut, pool.feePercent);
        
        if (amountOut < minAmountOut) revert SlippageTooHigh();
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        // Calcular fees
        uint256 fee = (amountIn * pool.feePercent) / BASIS_POINTS;
        uint256 protocolFee = (fee * pool.protocolFeePercent) / BASIS_POINTS;
        uint256 lpFee = fee - protocolFee;

        // Actualizar reserves
        if (isToken0) {
            pool.reserve0 += amountIn;
            pool.reserve1 -= amountOut;
            pool.totalVolume0 += amountIn;
            pool.totalFees0 += lpFee;
            protocolFees[pool.token0] += protocolFee;
        } else {
            pool.reserve1 += amountIn;
            pool.reserve0 -= amountOut;
            pool.totalVolume1 += amountIn;
            pool.totalFees1 += lpFee;
            protocolFees[pool.token1] += protocolFee;
        }

        // Transferencias
        address tokenOut = isToken0 ? pool.token1 : pool.token0;
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit Swap(poolId, msg.sender, tokenIn, tokenOut, amountIn, amountOut, fee);
    }

    /**
     * @notice Obtiene quote de swap sin ejecutar
     * @param poolId ID del pool
     * @param tokenIn Token de entrada
     * @param amountIn Cantidad de entrada
     * @return amountOut Cantidad estimada de salida
     * @return fee Fee total
     * @return priceImpact Impacto en precio (basis points)
     */
    function getSwapQuote(uint256 poolId, address tokenIn, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, uint256 fee, uint256 priceImpact)
    {
        Pool storage pool = pools[poolId];
        if (pool.poolId == 0) revert PoolNotFound();

        bool isToken0 = tokenIn == pool.token0;
        if (!isToken0 && tokenIn != pool.token1) revert InvalidTokenPair();

        (uint256 reserveIn, uint256 reserveOut) = isToken0
            ? (pool.reserve0, pool.reserve1)
            : (pool.reserve1, pool.reserve0);

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut, pool.feePercent);
        fee = (amountIn * pool.feePercent) / BASIS_POINTS;
        
        // Calcular price impact
        uint256 oldPrice = (reserveOut * BASIS_POINTS) / reserveIn;
        uint256 newReserveIn = reserveIn + amountIn;
        uint256 newReserveOut = reserveOut - amountOut;
        uint256 newPrice = (newReserveOut * BASIS_POINTS) / newReserveIn;
        
        priceImpact = oldPrice > newPrice
            ? ((oldPrice - newPrice) * BASIS_POINTS) / oldPrice
            : ((newPrice - oldPrice) * BASIS_POINTS) / newPrice;
    }

    // ========================================
    // FUNCIONES INTERNAS - CÁLCULOS
    // ========================================

    /**
     * @dev Calcula cantidad de salida para un swap
     */
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feePercent
    )
        internal
        pure
        returns (uint256)
    {
        if (amountIn == 0) revert InvalidAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 feeFactor = BASIS_POINTS - feePercent; // 10000 - 30 = 9970
        uint256 amountInWithFee = amountIn * feeFactor;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * BASIS_POINTS) + amountInWithFee;

        return numerator / denominator;
    }

    /**
     * @dev Calcula quote para liquidez
     */
    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        internal
        pure
        returns (uint256)
    {
        if (amountA == 0) revert InvalidAmount();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        
        return (amountA * reserveB) / reserveA;
    }

    /**
     * @dev Calcula raíz cuadrada (Babylonian method)
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @dev Retorna el mínimo de dos números
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // ========================================
    // FUNCIONES DE CONSULTA
    // ========================================

    /**
     * @notice Obtiene información de un pool
     */
    function getPoolInfo(uint256 poolId)
        external
        view
        returns (
            address token0,
            address token1,
            uint256 reserve0,
            uint256 reserve1,
            uint256 totalLiquidity,
            uint256 price,
            bool active
        )
    {
        Pool storage pool = pools[poolId];
        
        price = pool.reserve0 > 0 
            ? (pool.reserve1 * BASIS_POINTS) / pool.reserve0 
            : 0;

        return (
            pool.token0,
            pool.token1,
            pool.reserve0,
            pool.reserve1,
            pool.totalLiquidity,
            price,
            pool.active
        );
    }

    /**
     * @notice Obtiene posición de liquidez de un usuario
     */
    function getUserPosition(address user, uint256 poolId)
        external
        view
        returns (
            uint256 lpTokens,
            uint256 token0Amount,
            uint256 token1Amount,
            uint256 sharePercent
        )
    {
        LiquidityPosition storage position = liquidityPositions[user][poolId];
        Pool storage pool = pools[poolId];

        lpTokens = position.lpTokens;
        
        if (pool.totalLiquidity > 0) {
            token0Amount = (lpTokens * pool.reserve0) / pool.totalLiquidity;
            token1Amount = (lpTokens * pool.reserve1) / pool.totalLiquidity;
            sharePercent = (lpTokens * BASIS_POINTS) / pool.totalLiquidity;
        }
    }

    /**
     * @notice Obtiene pools donde usuario tiene liquidez
     */
    function getUserPools(address user) external view returns (uint256[] memory) {
        return userPoolIds[user];
    }

    /**
     * @notice Obtiene precio actual de un pool
     */
    function getPoolPrice(uint256 poolId) external view returns (uint256) {
        Pool storage pool = pools[poolId];
        return pool.reserve0 > 0
            ? (pool.reserve1 * BASIS_POINTS) / pool.reserve0
            : 0;
    }

    // ========================================
    // FUNCIONES ADMIN
    // ========================================

    /**
     * @notice Actualiza fees de un pool
     */
    function updatePoolFees(
        uint256 poolId,
        uint256 newFeePercent,
        uint256 newProtocolFeePercent
    )
        external
        onlyRole(POOL_ADMIN_ROLE)
    {
        Pool storage pool = pools[poolId];
        if (pool.poolId == 0) revert PoolNotFound();
        if (newFeePercent > 100) revert InvalidAmount(); // Max 1%
        if (newProtocolFeePercent > 50) revert InvalidAmount(); // Max 50% del fee

        pool.feePercent = newFeePercent;
        pool.protocolFeePercent = newProtocolFeePercent;
    }

    /**
     * @notice Activa/desactiva un pool
     */
    function setPoolStatus(uint256 poolId, bool active)
        external
        onlyRole(POOL_ADMIN_ROLE)
    {
        Pool storage pool = pools[poolId];
        if (pool.poolId == 0) revert PoolNotFound();

        pool.active = active;
        emit PoolStatusChanged(poolId, active);
    }

    /**
     * @notice Cobra protocol fees acumulados
     */
    function collectProtocolFees(address token)
        external
        onlyRole(FEE_COLLECTOR_ROLE)
        nonReentrant
    {
        uint256 fees = protocolFees[token];
        if (fees == 0) revert NoFeesToCollect();

        protocolFees[token] = 0;
        IERC20(token).safeTransfer(treasury, fees);

        emit ProtocolFeesCollected(token, fees);
    }

    /**
     * @notice Actualiza treasury
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert InvalidAddress();
        treasury = newTreasury;
    }

    /**
     * @notice Pausa el contrato
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Despausa el contrato
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
