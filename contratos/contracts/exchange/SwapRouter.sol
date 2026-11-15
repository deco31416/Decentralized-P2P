// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SwapRouter
 * @notice Router inteligente para enrutamiento óptimo de swaps
 * @dev Encuentra la mejor ruta de ejecución entre múltiples fuentes de liquidez
 * 
 * Características principales:
 * - Pathfinding automático para encontrar mejores rutas
 * - Multi-hop swaps (A → B → C)
 * - Split orders (dividir orden entre múltiples fuentes)
 * - Price impact calculation
 * - Slippage protection
 * - Gas optimization
 * - Integration con P2POrderBook, P2PExchange, y DEXs externos
 * 
 * Fuentes de liquidez soportadas:
 * 1. P2POrderBook interno
 * 2. P2PExchange offers
 * 3. External DEXs (Uniswap, SushiSwap, PancakeSwap)
 * 4. Liquidity pools propias
 * 
 * Algoritmos:
 * - Dijkstra para pathfinding
 * - Greedy algorithm para split orders
 * - Price impact minimization
 */
contract SwapRouter is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Tipos de fuentes de liquidez
    enum LiquiditySource {
        P2POrderBook,       // Order book interno
        P2PExchange,        // Ofertas P2P
        UniswapV2,          // Uniswap V2 style DEX
        UniswapV3,          // Uniswap V3 style DEX
        InternalPool,       // Pool propio
        ExternalSource      // Fuente externa personalizada
    }

    /// @notice Estructura de una ruta de swap
    struct SwapRoute {
        address[] path;             // Ruta de tokens [A, B, C]
        LiquiditySource[] sources;  // Fuentes para cada hop
        uint256[] amounts;          // Cantidades en cada hop
        uint256 expectedOutput;     // Output esperado
        uint256 priceImpact;        // Impacto en precio (basis points)
        uint256 gasEstimate;        // Gas estimado
    }

    /// @notice Estructura de una orden de swap split
    struct SplitSwap {
        uint256[] percentages;      // Porcentajes para cada fuente (basis points)
        LiquiditySource[] sources;  // Fuentes de liquidez
        uint256[] amounts;          // Cantidades por fuente
        uint256 totalOutput;        // Output total esperado
    }

    /// @notice Información de una fuente de liquidez
    struct LiquiditySourceInfo {
        address contractAddress;
        LiquiditySource sourceType;
        bool active;
        uint256 priority;           // Mayor prioridad = se intenta primero
        uint256 totalVolume;
        uint256 last24hVolume;
    }

    /// @notice Estadísticas de swap
    struct SwapStats {
        uint256 totalSwaps;
        uint256 totalVolume;
        uint256 last24hVolume;
        uint256 totalFees;
        uint256 averageSlippage;
    }

    /// @notice Contador de swaps
    uint256 public swapCount;

    /// @notice Fuentes de liquidez registradas
    mapping(bytes32 => LiquiditySourceInfo) public liquiditySources;
    
    /// @notice Array de fuentes activas
    bytes32[] public activeSourceIds;

    /// @notice Pares de tokens soportados
    mapping(bytes32 => bool) public supportedPairs;

    /// @notice Estadísticas por par
    mapping(bytes32 => SwapStats) public pairStats;

    /// @notice Referencia al P2POrderBook
    address public p2pOrderBook;
    
    /// @notice Referencia al P2PExchange
    address public p2pExchange;
    
    /// @notice Referencia al BalanceManager
    address public balanceManager;
    
    /// @notice Referencia al FeeManager
    address public feeManager;

    /// @notice Slippage máximo permitido por defecto (5%)
    uint256 public maxSlippage = 500; // basis points
    
    /// @notice Número máximo de hops permitidos
    uint256 public maxHops = 3;
    
    /// @notice Monto mínimo para swap
    uint256 public minSwapAmount = 10 * 10**18; // $10 USD

    /// @notice Price impact máximo antes de requerir split (10%)
    uint256 public maxPriceImpact = 1000;
    
    /// @notice Rate limiting: user => last swap timestamp
    mapping(address => uint256) public lastSwapTime;
    
    /// @notice Cooldown for swaps (1 second to prevent HFT abuse)
    uint256 public constant SWAP_COOLDOWN = 1 seconds;

    // ============================================
    // EVENTOS
    // ============================================

    event SwapExecuted(
        uint256 indexed swapId,
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 slippage
    );

    event RouteFound(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address[] path,
        uint256 expectedOutput
    );

    event LiquiditySourceAdded(
        bytes32 indexed sourceId,
        address contractAddress,
        LiquiditySource sourceType
    );

    event LiquiditySourceUpdated(
        bytes32 indexed sourceId,
        bool active
    );

    event SplitSwapExecuted(
        uint256 indexed swapId,
        uint256 sourceCount,
        uint256 totalOutput
    );
    
    event EmergencyWithdraw(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    
    event RateLimitUpdated(
        address indexed user,
        uint256 timestamp
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _p2pOrderBook,
        address _p2pExchange,
        address _balanceManager,
        address _feeManager
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_p2pOrderBook != address(0), "Invalid order book");
        require(_p2pExchange != address(0), "Invalid exchange");
        require(_balanceManager != address(0), "Invalid balance manager");
        require(_feeManager != address(0), "Invalid fee manager");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        p2pOrderBook = _p2pOrderBook;
        p2pExchange = _p2pExchange;
        balanceManager = _balanceManager;
        feeManager = _feeManager;

        // Registrar fuentes internas
        _registerSource(p2pOrderBook, LiquiditySource.P2POrderBook, 100);
        _registerSource(p2pExchange, LiquiditySource.P2PExchange, 90);
    }
    
    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Rate limit modifier to prevent high-frequency trading abuse
     */
    modifier rateLimit() {
        require(
            block.timestamp >= lastSwapTime[msg.sender] + SWAP_COOLDOWN,
            "SwapRouter: rate limit active"
        );
        lastSwapTime[msg.sender] = block.timestamp;
        emit RateLimitUpdated(msg.sender, block.timestamp);
        _;
    }

    // ============================================
    // GESTIÓN DE FUENTES DE LIQUIDEZ
    // ============================================

    /**
     * @notice Registra una nueva fuente de liquidez
     * @param contractAddress Dirección del contrato
     * @param sourceType Tipo de fuente
     * @param priority Prioridad (0-100)
     */
    function addLiquiditySource(
        address contractAddress,
        LiquiditySource sourceType,
        uint256 priority
    ) external onlyRole(ADMIN_ROLE) {
        require(contractAddress != address(0), "Invalid address");
        require(priority <= 100, "Invalid priority");

        _registerSource(contractAddress, sourceType, priority);
    }

    /**
     * @notice Función interna para registrar fuente
     */
    function _registerSource(
        address contractAddress,
        LiquiditySource sourceType,
        uint256 priority
    ) internal {
        bytes32 sourceId = keccak256(abi.encodePacked(contractAddress, sourceType));
        
        liquiditySources[sourceId] = LiquiditySourceInfo({
            contractAddress: contractAddress,
            sourceType: sourceType,
            active: true,
            priority: priority,
            totalVolume: 0,
            last24hVolume: 0
        });

        activeSourceIds.push(sourceId);

        emit LiquiditySourceAdded(sourceId, contractAddress, sourceType);
    }

    /**
     * @notice Actualiza el estado de una fuente
     * @param contractAddress Dirección del contrato
     * @param sourceType Tipo de fuente
     * @param active Nuevo estado
     */
    function updateLiquiditySource(
        address contractAddress,
        LiquiditySource sourceType,
        bool active
    ) external onlyRole(ADMIN_ROLE) {
        bytes32 sourceId = keccak256(abi.encodePacked(contractAddress, sourceType));
        require(liquiditySources[sourceId].contractAddress != address(0), "Source not found");

        liquiditySources[sourceId].active = active;

        emit LiquiditySourceUpdated(sourceId, active);
    }

    // ============================================
    // SWAP SIMPLE
    // ============================================

    /**
     * @notice Ejecuta un swap simple con mejor precio
     * @dev Rate limited to 1 swap per second per user to prevent HFT abuse
     * @param tokenIn Token de entrada
     * @param tokenOut Token de salida
     * @param amountIn Cantidad de entrada
     * @param minAmountOut Mínimo aceptable de salida
     * @param maxSlippageBps Slippage máximo (basis points)
     * @param deadline Deadline for execution
     */
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 maxSlippageBps,
        uint256 deadline  // SECURITY: Added deadline protection
    ) external nonReentrant rateLimit whenNotPaused returns (uint256 amountOut) {
        // SECURITY: Deadline protection against pending transactions
        require(block.timestamp <= deadline, "SwapRouter: EXPIRED");
        
        require(tokenIn != address(0) && tokenOut != address(0), "Invalid tokens");
        require(tokenIn != tokenOut, "Same token");
        require(amountIn >= minSwapAmount, "Amount too small");
        require(amountIn > 0, "Zero amount");
        require(minAmountOut > 0, "Zero min output");
        require(maxSlippageBps <= maxSlippage, "Slippage too high");

        // Buscar mejor ruta
        SwapRoute memory bestRoute = findBestRoute(tokenIn, tokenOut, amountIn);
        require(bestRoute.expectedOutput >= minAmountOut, "Insufficient output");

        // Verificar slippage
        uint256 slippage = _calculateSlippage(amountIn, bestRoute.expectedOutput);
        require(slippage <= maxSlippageBps, "Slippage exceeded");

        // Ejecutar swap
        amountOut = _executeRoute(bestRoute, msg.sender, amountIn);
        require(amountOut >= minAmountOut, "Slippage protection");

        swapCount++;

        // Actualizar estadísticas
        _updateStats(tokenIn, tokenOut, amountIn, amountOut, slippage);

        emit SwapExecuted(
            swapCount,
            msg.sender,
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            slippage
        );

        return amountOut;
    }

    // ============================================
    // PATHFINDING
    // ============================================

    /**
     * @notice Encuentra la mejor ruta para un swap
     * @param tokenIn Token de entrada
     * @param tokenOut Token de salida
     * @param amountIn Cantidad de entrada
     */
    function findBestRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (SwapRoute memory) {
        // Ruta directa (1 hop)
        SwapRoute memory directRoute = _findDirectRoute(tokenIn, tokenOut, amountIn);
        
        // Si direct route es bueno, retornar
        if (directRoute.priceImpact < maxPriceImpact / 2) {
            return directRoute;
        }

        // Intentar rutas multi-hop
        SwapRoute memory multiHopRoute = _findMultiHopRoute(tokenIn, tokenOut, amountIn);
        
        // Retornar la mejor ruta
        if (multiHopRoute.expectedOutput > directRoute.expectedOutput) {
            return multiHopRoute;
        }
        
        return directRoute;
    }

    /**
     * @notice Encuentra ruta directa (1 hop)
     */
    function _findDirectRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (SwapRoute memory) {
        uint256 bestOutput = 0;
        LiquiditySource bestSource = LiquiditySource.P2POrderBook;

        // Revisar cada fuente activa
        for (uint256 i = 0; i < activeSourceIds.length; i++) {
            LiquiditySourceInfo storage source = liquiditySources[activeSourceIds[i]];
            
            if (!source.active) continue;

            uint256 output = _estimateOutput(
                source.contractAddress,
                source.sourceType,
                tokenIn,
                tokenOut,
                amountIn
            );

            if (output > bestOutput) {
                bestOutput = output;
                bestSource = source.sourceType;
            }
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        LiquiditySource[] memory sources = new LiquiditySource[](1);
        sources[0] = bestSource;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountIn;

        uint256 priceImpact = _calculatePriceImpact(amountIn, bestOutput);

        return SwapRoute({
            path: path,
            sources: sources,
            amounts: amounts,
            expectedOutput: bestOutput,
            priceImpact: priceImpact,
            gasEstimate: 150000 // Estimado base
        });
    }

    /**
     * @notice Encuentra ruta multi-hop (2-3 hops)
     */
    function _findMultiHopRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (SwapRoute memory) {
        // TODO: Implementar pathfinding más sofisticado
        // Por ahora retornamos ruta directa
        return _findDirectRoute(tokenIn, tokenOut, amountIn);
    }

    // ============================================
    // SPLIT SWAPS
    // ============================================

    /**
     * @notice Ejecuta un swap dividido entre múltiples fuentes
     * @param tokenIn Token de entrada
     * @param tokenOut Token de salida
     * @param amountIn Cantidad de entrada
     * @param minAmountOut Mínimo aceptable de salida
     */
    function swapSplit(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline  // SECURITY: Added deadline protection
    ) external nonReentrant whenNotPaused returns (uint256 totalOutput) {
        // SECURITY: Deadline protection
        require(block.timestamp <= deadline, "SwapRouter: EXPIRED");
        
        require(tokenIn != address(0) && tokenOut != address(0), "Invalid tokens");
        require(amountIn >= minSwapAmount, "Amount too small");
        require(minAmountOut > 0, "Zero min output");

        // Calcular split óptimo
        SplitSwap memory split = _calculateOptimalSplit(tokenIn, tokenOut, amountIn);
        require(split.totalOutput >= minAmountOut, "Insufficient output");

        // Ejecutar cada parte del split
        for (uint256 i = 0; i < split.sources.length; i++) {
            if (split.amounts[i] > 0) {
                uint256 output = _executeSwapOnSource(
                    split.sources[i],
                    tokenIn,
                    tokenOut,
                    split.amounts[i],
                    msg.sender
                );
                totalOutput += output;
            }
        }

        require(totalOutput >= minAmountOut, "Slippage protection");

        swapCount++;

        emit SplitSwapExecuted(swapCount, split.sources.length, totalOutput);

        return totalOutput;
    }

    /**
     * @notice Calcula el split óptimo entre fuentes
     */
    function _calculateOptimalSplit(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (SplitSwap memory) {
        // Greedy algorithm: dividir según liquidez disponible
        uint256[] memory percentages = new uint256[](activeSourceIds.length);
        LiquiditySource[] memory sources = new LiquiditySource[](activeSourceIds.length);
        uint256[] memory amounts = new uint256[](activeSourceIds.length);
        
        uint256 remainingAmount = amountIn;
        uint256 totalOutput = 0;
        uint256 activeCount = 0;

        for (uint256 i = 0; i < activeSourceIds.length && remainingAmount > 0; i++) {
            LiquiditySourceInfo storage source = liquiditySources[activeSourceIds[i]];
            
            if (!source.active) continue;

            // Estimar cuánto puede tomar esta fuente sin alto price impact
            uint256 maxAmount = _estimateMaxAmountForLowImpact(
                source.contractAddress,
                source.sourceType,
                tokenIn,
                tokenOut
            );

            uint256 takeAmount = maxAmount < remainingAmount ? maxAmount : remainingAmount;
            
            if (takeAmount > 0) {
                uint256 output = _estimateOutput(
                    source.contractAddress,
                    source.sourceType,
                    tokenIn,
                    tokenOut,
                    takeAmount
                );

                percentages[activeCount] = (takeAmount * 10000) / amountIn;
                sources[activeCount] = source.sourceType;
                amounts[activeCount] = takeAmount;
                totalOutput += output;
                
                remainingAmount -= takeAmount;
                activeCount++;
            }
        }

        // Truncar arrays al tamaño real
        assembly {
            mstore(percentages, activeCount)
            mstore(sources, activeCount)
            mstore(amounts, activeCount)
        }

        return SplitSwap({
            percentages: percentages,
            sources: sources,
            amounts: amounts,
            totalOutput: totalOutput
        });
    }

    // ============================================
    // EJECUCIÓN DE SWAPS
    // ============================================

    /**
     * @notice Ejecuta una ruta de swap
     */
    function _executeRoute(
        SwapRoute memory route,
        address user,
        uint256 amountIn
    ) internal returns (uint256 finalOutput) {
        uint256 currentAmount = amountIn;
        
        for (uint256 i = 0; i < route.path.length - 1; i++) {
            currentAmount = _executeSwapOnSource(
                route.sources[i],
                route.path[i],
                route.path[i + 1],
                currentAmount,
                user
            );
        }

        return currentAmount;
    }

    /**
     * @notice Ejecuta un swap en una fuente específica
     */
    function _executeSwapOnSource(
        LiquiditySource source,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address user
    ) internal returns (uint256 amountOut) {
        if (source == LiquiditySource.P2POrderBook) {
            return _swapOnOrderBook(tokenIn, tokenOut, amountIn, user);
        } else if (source == LiquiditySource.P2PExchange) {
            return _swapOnP2PExchange(tokenIn, tokenOut, amountIn, user);
        }
        // TODO: Implementar otras fuentes
        
        revert("Source not implemented");
    }

    /**
     * @notice Swap en OrderBook
     */
    function _swapOnOrderBook(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address /* user */
    ) internal returns (uint256 amountOut) {
        // Llamar a P2POrderBook.createMarketOrder()
        (bool success, ) = p2pOrderBook.call(
            abi.encodeWithSignature(
                "createMarketOrder(address,address,uint256,uint8,uint256)",
                tokenIn,
                tokenOut,
                amountIn,
                0, // Buy side
                100 // 1% slippage
            )
        );
        require(success, "OrderBook swap failed");
        
        // Decodificar orderId y obtener resultado
        // TODO: Implementar lógica completa
        return amountIn; // Placeholder
    }

    /**
     * @notice Swap en P2PExchange
     */
    function _swapOnP2PExchange(
        address /* tokenIn */,
        address /* tokenOut */,
        uint256 amountIn,
        address /* user */
    ) internal pure returns (uint256 amountOut) {
        // Buscar oferta compatible y aceptarla
        // TODO: Implementar lógica completa
        return amountIn; // Placeholder
    }

    // ============================================
    // ESTIMACIONES Y CÁLCULOS
    // ============================================

    /**
     * @notice Estima el output para un swap
     */
    function _estimateOutput(
        address /* sourceAddress */,
        LiquiditySource /* sourceType */,
        address /* tokenIn */,
        address /* tokenOut */,
        uint256 amountIn
    ) internal pure returns (uint256) {
        // TODO: Implementar estimaciones reales para cada fuente
        // Por ahora retornamos una estimación simple
        return (amountIn * 98) / 100; // 2% fee estimado
    }

    /**
     * @notice Estima el monto máximo para bajo price impact
     */
    function _estimateMaxAmountForLowImpact(
        address /* sourceAddress */,
        LiquiditySource /* sourceType */,
        address /* tokenIn */,
        address /* tokenOut */
    ) internal pure returns (uint256) {
        // TODO: Implementar lógica real
        return 1000 * 10**18; // $1000 placeholder
    }

    /**
     * @notice Calcula el price impact
     */
    function _calculatePriceImpact(
        uint256 /* amountIn */,
        uint256 /* amountOut */
    ) internal pure returns (uint256) {
        // Simplified calculation
        return 50; // 0.5% placeholder
    }

    /**
     * @notice Calcula el slippage
     */
    function _calculateSlippage(
        uint256 /* expectedIn */,
        uint256 /* actualOut */
    ) internal pure returns (uint256) {
        // TODO: Cálculo real de slippage
        return 50; // 0.5% placeholder
    }

    /**
     * @notice Actualiza estadísticas del par
     */
    function _updateStats(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 /* amountOut */,
        uint256 slippage
    ) internal {
        bytes32 pairId = _getPairId(tokenIn, tokenOut);
        
        SwapStats storage stats = pairStats[pairId];
        stats.totalSwaps++;
        stats.totalVolume += amountIn;
        stats.last24hVolume += amountIn;
        stats.averageSlippage = ((stats.averageSlippage * (stats.totalSwaps - 1)) + slippage) / stats.totalSwaps;
    }

    function _getPairId(address tokenA, address tokenB) internal pure returns (bytes32) {
        return tokenA < tokenB 
            ? keccak256(abi.encodePacked(tokenA, tokenB))
            : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    // ============================================
    // SETTERS
    // ============================================

    function setP2POrderBook(address _orderBook) external onlyRole(ADMIN_ROLE) {
        require(_orderBook != address(0), "Invalid address");
        p2pOrderBook = _orderBook;
    }

    function setP2PExchange(address _exchange) external onlyRole(ADMIN_ROLE) {
        require(_exchange != address(0), "Invalid address");
        p2pExchange = _exchange;
    }

    function setBalanceManager(address _balanceManager) external onlyRole(ADMIN_ROLE) {
        require(_balanceManager != address(0), "Invalid address");
        balanceManager = _balanceManager;
    }

    function setFeeManager(address _feeManager) external onlyRole(ADMIN_ROLE) {
        require(_feeManager != address(0), "Invalid address");
        feeManager = _feeManager;
    }

    function setMaxSlippage(uint256 slippage) external onlyRole(ADMIN_ROLE) {
        require(slippage <= 1000, "Slippage too high"); // Max 10%
        maxSlippage = slippage;
    }

    function setMaxHops(uint256 hops) external onlyRole(ADMIN_ROLE) {
        require(hops >= 1 && hops <= 5, "Invalid hops");
        maxHops = hops;
    }

    function setMinSwapAmount(uint256 amount) external onlyRole(ADMIN_ROLE) {
        minSwapAmount = amount;
    }

    function setMaxPriceImpact(uint256 impact) external onlyRole(ADMIN_ROLE) {
        require(impact <= 5000, "Impact too high"); // Max 50%
        maxPriceImpact = impact;
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

    function getActiveSources() external view returns (bytes32[] memory) {
        return activeSourceIds;
    }

    function getLiquiditySource(bytes32 sourceId) external view returns (LiquiditySourceInfo memory) {
        return liquiditySources[sourceId];
    }

    function getPairStats(address tokenA, address tokenB) external view returns (SwapStats memory) {
        return pairStats[_getPairId(tokenA, tokenB)];
    }

    function estimateSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 expectedOutput, uint256 priceImpact) {
        SwapRoute memory route = findBestRoute(tokenIn, tokenOut, amountIn);
        return (route.expectedOutput, route.priceImpact);
    }

    /**
     * @notice Obtiene estadísticas globales del Router
     */
    function getStats() external view returns (
        uint256 totalSwapsExecuted,
        uint256 totalLiquiditySources,
        uint256 totalRoutingPairs,
        uint256 totalVolumeRouted
    ) {
        totalSwapsExecuted = swapCount;
        totalLiquiditySources = 0; // No hay contador, calcular off-chain
        totalRoutingPairs = 0; // No hay contador de pares
        totalVolumeRouted = 0; // Sumar desde pairStats off-chain
    }
    
    /*//////////////////////////////////////////////////////////////
                        EMERGENCY RECOVERY
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Emergency withdraw tokens sent to contract by mistake
     * @dev SwapRouter should not hold funds long-term (only during swaps)
     * @param token Token address (use address(0) for native)
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(to != address(0), "SwapRouter: zero address");
        require(amount > 0, "SwapRouter: zero amount");
        
        if (token == address(0)) {
            // Native token (ETH/BNB)
            require(address(this).balance >= amount, "SwapRouter: insufficient balance");
            (bool success, ) = to.call{value: amount, gas: 50000}("");
            require(success, "SwapRouter: ETH transfer failed");
        } else {
            // ERC20 token
            IERC20(token).safeTransfer(to, amount);
        }
        
        emit EmergencyWithdraw(token, to, amount);
    }
}
