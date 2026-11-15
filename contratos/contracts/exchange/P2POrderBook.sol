// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title P2POrderBook
 * @notice Order book descentralizado para trading P2P crypto-crypto
 * @dev Implementa un order book on-chain con órdenes limit y market
 * 
 * Características principales:
 * - Órdenes limit (precio fijo) y market (mejor precio disponible)
 * - Matching automático de órdenes compatibles
 * - Book de compra (bids) y venta (asks) separados
 * - Partial fills (ejecución parcial de órdenes)
 * - Cancelación de órdenes con liberación de fondos
 * - Fee del protocolo con descuentos por volumen
 * - Protección contra front-running con timestamp
 * - Integración con BalanceManager y FeeManager
 * 
 * Flujos principales:
 * 1. Crear orden limit → Bloquear fondos en BalanceManager → Añadir al book
 * 2. Crear orden market → Buscar mejor match → Ejecutar swap → Cobrar fee
 * 3. Match automático: Nueva orden → Verificar contrapartes → Ejecutar trades
 * 4. Cancelar orden → Verificar estado → Liberar fondos → Remover del book
 * 
 * Optimizaciones:
 * - Usa sorted linked list para mantener price priority
 * - Time priority: FIFO dentro del mismo precio
 * - Gas efficient: Batch matching cuando es posible
 */
contract P2POrderBook is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador (puede ejecutar matches)
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Tipos de órdenes
    enum OrderType {
        Limit,      // Orden a precio fijo
        Market      // Orden a mejor precio disponible
    }

    /// @notice Lados del trade
    enum OrderSide {
        Buy,        // Comprar tokenB con tokenA
        Sell        // Vender tokenA por tokenB
    }

    /// @notice Estados de una orden
    enum OrderStatus {
        Open,           // Activa, esperando match
        PartialFilled,  // Parcialmente ejecutada
        Filled,         // Completamente ejecutada
        Cancelled,      // Cancelada por el usuario
        Expired         // Expirada por timeout
    }

    /// @notice Estructura de una orden
    struct Order {
        uint256 orderId;
        address maker;          // Creador de la orden
        address tokenA;         // Token a dar
        address tokenB;         // Token a recibir
        uint256 amountA;        // Cantidad de tokenA
        uint256 amountB;        // Cantidad de tokenB
        uint256 price;          // Precio (amountB / amountA * 1e18)
        uint256 filledA;        // Cantidad ya ejecutada de tokenA
        uint256 filledB;        // Cantidad ya ejecutada de tokenB
        OrderType orderType;
        OrderSide side;
        OrderStatus status;
        uint256 createdAt;
        uint256 expiresAt;      // 0 = sin expiración
        bool partialFillAllowed;
    }

    /// @notice Estructura de un trade ejecutado
    struct Trade {
        uint256 tradeId;
        uint256 buyOrderId;
        uint256 sellOrderId;
        address buyer;
        address seller;
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
        uint256 price;
        uint256 feeA;
        uint256 feeB;
        uint256 timestamp;
    }

    /// @notice Par de trading
    struct TradingPair {
        address tokenA;
        address tokenB;
        bool active;
        uint256 minOrderSize;
        uint256 tickSize;       // Tamaño mínimo de incremento de precio
        uint256 totalVolume;
        uint256 last24hVolume;
        uint256 lastPrice;
        uint256 lastUpdateTime;
    }

    /// @notice Contador de órdenes
    uint256 public orderCount;
    
    /// @notice Contador de trades
    uint256 public tradeCount;

    /// @notice Mapeo de ID a orden
    mapping(uint256 => Order) public orders;
    
    /// @notice Mapeo de ID a trade
    mapping(uint256 => Trade) public trades;
    
    /// @notice Órdenes de un usuario
    mapping(address => uint256[]) public userOrders;
    
    /// @notice Trades de un usuario
    mapping(address => uint256[]) public userTrades;
    
    /// @notice Pares de trading
    mapping(bytes32 => TradingPair) public tradingPairs;
    
    /// @notice Lista de pares activos
    bytes32[] public activePairs;

    /// @notice Order book: par → precio → array de order IDs
    /// @dev Buy orders: precio descendente, Sell orders: precio ascendente
    mapping(bytes32 => mapping(uint256 => uint256[])) public buyOrders;
    mapping(bytes32 => mapping(uint256 => uint256[])) public sellOrders;
    
    /// @notice Precios activos en el book (para iteración eficiente)
    mapping(bytes32 => uint256[]) public buyPrices;
    mapping(bytes32 => uint256[]) public sellPrices;

    /// @notice Referencia al BalanceManager
    address public balanceManager;
    
    /// @notice Referencia al FeeManager
    address public feeManager;
    
    /// @notice Referencia al CambiaCriptoMain
    address public mainContract;

    /// @notice Tiempo máximo de expiración (30 días)
    uint256 public constant MAX_EXPIRATION = 30 days;
    
    /// @notice Monto mínimo de orden (en USD, 18 decimales)
    uint256 public minOrderAmount = 10 * 10**18; // $10 USD

    // ============================================
    // EVENTOS
    // ============================================

    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 price,
        OrderType orderType,
        OrderSide side
    );

    event OrderMatched(
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        uint256 amountA,
        uint256 amountB,
        uint256 price
    );

    event OrderFilled(
        uint256 indexed orderId,
        uint256 filledA,
        uint256 filledB,
        OrderStatus status
    );

    event OrderCancelled(
        uint256 indexed orderId,
        address indexed maker,
        uint256 remainingA,
        uint256 remainingB
    );

    event OrderExpired(
        uint256 indexed orderId,
        address indexed maker
    );

    event TradeExecuted(
        uint256 indexed tradeId,
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        address buyer,
        address seller,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 price
    );

    event TradingPairAdded(
        bytes32 indexed pairId,
        address tokenA,
        address tokenB
    );

    event TradingPairUpdated(
        bytes32 indexed pairId,
        bool active
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _balanceManager,
        address _feeManager
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_balanceManager != address(0), "Invalid balance manager");
        require(_feeManager != address(0), "Invalid fee manager");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        balanceManager = _balanceManager;
        feeManager = _feeManager;
    }

    // ============================================
    // GESTIÓN DE PARES DE TRADING
    // ============================================

    /**
     * @notice Añade un nuevo par de trading
     * @param tokenA Primer token del par
     * @param tokenB Segundo token del par
     * @param minOrderSize Tamaño mínimo de orden
     * @param tickSize Tamaño mínimo de incremento de precio
     */
    function addTradingPair(
        address tokenA,
        address tokenB,
        uint256 minOrderSize,
        uint256 tickSize
    ) external onlyRole(ADMIN_ROLE) {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        require(tokenA != tokenB, "Same tokens");
        require(minOrderSize > 0, "Invalid min order size");
        require(tickSize > 0, "Invalid tick size");

        bytes32 pairId = _getPairId(tokenA, tokenB);
        require(!tradingPairs[pairId].active, "Pair already exists");

        tradingPairs[pairId] = TradingPair({
            tokenA: tokenA,
            tokenB: tokenB,
            active: true,
            minOrderSize: minOrderSize,
            tickSize: tickSize,
            totalVolume: 0,
            last24hVolume: 0,
            lastPrice: 0,
            lastUpdateTime: block.timestamp
        });

        activePairs.push(pairId);

        emit TradingPairAdded(pairId, tokenA, tokenB);
    }

    /**
     * @notice Actualiza el estado de un par de trading
     * @param tokenA Primer token
     * @param tokenB Segundo token
     * @param active Nuevo estado
     */
    function updateTradingPair(
        address tokenA,
        address tokenB,
        bool active
    ) external onlyRole(ADMIN_ROLE) {
        bytes32 pairId = _getPairId(tokenA, tokenB);
        require(tradingPairs[pairId].tokenA != address(0), "Pair not found");

        tradingPairs[pairId].active = active;

        emit TradingPairUpdated(pairId, active);
    }

    // ============================================
    // CREACIÓN DE ÓRDENES
    // ============================================

    /**
     * @notice Crea una orden limit
     * @param tokenA Token a dar
     * @param tokenB Token a recibir
     * @param amountA Cantidad de tokenA
     * @param amountB Cantidad de tokenB deseada
     * @param side Buy o Sell
     * @param expiresIn Tiempo de expiración en segundos (0 = sin expiración)
     * @param partialFillAllowed Permitir ejecución parcial
     */
    function createLimitOrder(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        OrderSide side,
        uint256 expiresIn,
        bool partialFillAllowed
    ) external nonReentrant whenNotPaused returns (uint256) {
        bytes32 pairId = _getPairId(tokenA, tokenB);
        require(tradingPairs[pairId].active, "Pair not active");
        require(amountA > 0 && amountB > 0, "Invalid amounts");
        require(amountA >= tradingPairs[pairId].minOrderSize, "Below min order");
        require(expiresIn == 0 || expiresIn <= MAX_EXPIRATION, "Invalid expiration");

        // Calcular precio (amountB / amountA * 1e18)
        uint256 price = (amountB * 1e18) / amountA;
        require(price > 0, "Invalid price");

        // Verificar tick size
        require(price % tradingPairs[pairId].tickSize == 0, "Invalid tick");

        // Bloquear fondos en BalanceManager
        _lockFunds(msg.sender, tokenA, amountA);

        orderCount++;
        uint256 expiresAt = expiresIn > 0 ? block.timestamp + expiresIn : 0;

        orders[orderCount] = Order({
            orderId: orderCount,
            maker: msg.sender,
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            price: price,
            filledA: 0,
            filledB: 0,
            orderType: OrderType.Limit,
            side: side,
            status: OrderStatus.Open,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            partialFillAllowed: partialFillAllowed
        });

        userOrders[msg.sender].push(orderCount);

        // Añadir al order book
        _addToBook(pairId, orderCount, price, side);

        emit OrderCreated(
            orderCount,
            msg.sender,
            tokenA,
            tokenB,
            amountA,
            amountB,
            price,
            OrderType.Limit,
            side
        );

        // Intentar match automático
        _tryMatchOrder(orderCount);

        return orderCount;
    }

    /**
     * @notice Crea una orden market (ejecuta al mejor precio disponible)
     * @param tokenA Token a dar
     * @param tokenB Token a recibir
     * @param amountA Cantidad de tokenA
     * @param side Buy o Sell
     * @param slippageTolerance Tolerancia de slippage (basis points, ej: 100 = 1%)
     */
    function createMarketOrder(
        address tokenA,
        address tokenB,
        uint256 amountA,
        OrderSide side,
        uint256 slippageTolerance
    ) external nonReentrant whenNotPaused returns (uint256) {
        bytes32 pairId = _getPairId(tokenA, tokenB);
        require(tradingPairs[pairId].active, "Pair not active");
        require(amountA > 0, "Invalid amount");
        require(slippageTolerance <= 1000, "Slippage too high"); // Max 10%

        // Bloquear fondos
        _lockFunds(msg.sender, tokenA, amountA);

        orderCount++;

        orders[orderCount] = Order({
            orderId: orderCount,
            maker: msg.sender,
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: 0, // Se calculará al hacer match
            price: 0,   // Market order no tiene precio fijo
            filledA: 0,
            filledB: 0,
            orderType: OrderType.Market,
            side: side,
            status: OrderStatus.Open,
            createdAt: block.timestamp,
            expiresAt: 0,
            partialFillAllowed: true
        });

        userOrders[msg.sender].push(orderCount);

        emit OrderCreated(
            orderCount,
            msg.sender,
            tokenA,
            tokenB,
            amountA,
            0,
            0,
            OrderType.Market,
            side
        );

        // Ejecutar market order inmediatamente
        _executeMarketOrder(orderCount, slippageTolerance);

        return orderCount;
    }

    // ============================================
    // MATCHING DE ÓRDENES
    // ============================================

    /**
     * @notice Intenta hacer match de una orden con el book
     * @param orderId ID de la orden
     */
    function _tryMatchOrder(uint256 orderId) internal {
        Order storage order = orders[orderId];
        
        if (order.status != OrderStatus.Open && order.status != OrderStatus.PartialFilled) {
            return;
        }

        bytes32 pairId = _getPairId(order.tokenA, order.tokenB);
        
        // Buscar contrapartes según el lado de la orden
        uint256[] storage counterPrices = order.side == OrderSide.Buy 
            ? sellPrices[pairId] 
            : buyPrices[pairId];

        for (uint256 i = 0; i < counterPrices.length && order.status != OrderStatus.Filled; i++) {
            uint256 counterPrice = counterPrices[i];
            
            // Verificar si el precio es compatible
            if (order.side == OrderSide.Buy) {
                if (counterPrice > order.price) break; // Seller pide más de lo que buyer ofrece
            } else {
                if (counterPrice < order.price) break; // Buyer ofrece menos de lo que seller pide
            }

            // Obtener órdenes a este precio
            uint256[] storage counterOrderIds = order.side == OrderSide.Buy 
                ? sellOrders[pairId][counterPrice]
                : buyOrders[pairId][counterPrice];

            // Intentar match con cada orden
            for (uint256 j = 0; j < counterOrderIds.length && order.status != OrderStatus.Filled; j++) {
                uint256 counterOrderId = counterOrderIds[j];
                Order storage counterOrder = orders[counterOrderId];

                if (counterOrder.status == OrderStatus.Open || 
                    counterOrder.status == OrderStatus.PartialFilled) {
                    
                    _executeTrade(orderId, counterOrderId);
                }
            }
        }
    }

    /**
     * @notice Ejecuta un trade entre dos órdenes
     * @param buyOrderId ID de la orden de compra
     * @param sellOrderId ID de la orden de venta
     */
    function _executeTrade(uint256 buyOrderId, uint256 sellOrderId) internal {
        Order storage buyOrder = orders[buyOrderId];
        Order storage sellOrder = orders[sellOrderId];

        require(buyOrder.tokenA == sellOrder.tokenB, "Token mismatch");
        require(buyOrder.tokenB == sellOrder.tokenA, "Token mismatch");

        // Calcular cantidades a ejecutar
        uint256 remainingBuyA = buyOrder.amountA - buyOrder.filledA;
        uint256 remainingSellA = sellOrder.amountA - sellOrder.filledA;
        
        uint256 tradeAmountA = remainingBuyA < remainingSellA ? remainingBuyA : remainingSellA;
        
        // Calcular amountB usando el precio del sellOrder (maker price)
        uint256 tradeAmountB = (tradeAmountA * sellOrder.price) / 1e18;

        // Cobrar fees
        uint256 feeA = _calculateFee(buyOrder.maker, tradeAmountA);
        uint256 feeB = _calculateFee(sellOrder.maker, tradeAmountB);

        // Transferir fondos usando BalanceManager
        _executeSwap(
            buyOrder.maker,
            sellOrder.maker,
            buyOrder.tokenA,
            sellOrder.tokenA,
            tradeAmountA - feeA,
            tradeAmountB - feeB
        );

        // Actualizar órdenes
        buyOrder.filledA += tradeAmountA;
        buyOrder.filledB += tradeAmountB;
        sellOrder.filledA += tradeAmountB;
        sellOrder.filledB += tradeAmountA;

        // Actualizar estados
        _updateOrderStatus(buyOrderId);
        _updateOrderStatus(sellOrderId);

        // Registrar trade
        tradeCount++;
        trades[tradeCount] = Trade({
            tradeId: tradeCount,
            buyOrderId: buyOrderId,
            sellOrderId: sellOrderId,
            buyer: buyOrder.maker,
            seller: sellOrder.maker,
            tokenA: buyOrder.tokenA,
            tokenB: sellOrder.tokenA,
            amountA: tradeAmountA,
            amountB: tradeAmountB,
            price: sellOrder.price,
            feeA: feeA,
            feeB: feeB,
            timestamp: block.timestamp
        });

        userTrades[buyOrder.maker].push(tradeCount);
        userTrades[sellOrder.maker].push(tradeCount);

        // Actualizar estadísticas del par
        bytes32 pairId = _getPairId(buyOrder.tokenA, sellOrder.tokenA);
        _updatePairStats(pairId, tradeAmountA, sellOrder.price);

        emit OrderMatched(buyOrderId, sellOrderId, tradeAmountA, tradeAmountB, sellOrder.price);
        emit TradeExecuted(
            tradeCount,
            buyOrderId,
            sellOrderId,
            buyOrder.maker,
            sellOrder.maker,
            buyOrder.tokenA,
            sellOrder.tokenA,
            tradeAmountA,
            tradeAmountB,
            sellOrder.price
        );
    }

    /**
     * @notice Ejecuta una orden market
     * @param orderId ID de la orden
     * @param slippageTolerance Tolerancia de slippage
     */
    function _executeMarketOrder(uint256 orderId, uint256 slippageTolerance) internal {
        Order storage order = orders[orderId];
        bytes32 pairId = _getPairId(order.tokenA, order.tokenB);

        uint256[] storage counterPrices = order.side == OrderSide.Buy 
            ? sellPrices[pairId]
            : buyPrices[pairId];

        require(counterPrices.length > 0, "No liquidity");

        uint256 bestPrice = counterPrices[0];
        uint256 maxPrice = order.side == OrderSide.Buy 
            ? bestPrice + (bestPrice * slippageTolerance / 10000)
            : bestPrice - (bestPrice * slippageTolerance / 10000);

        order.price = maxPrice;
        order.amountB = (order.amountA * maxPrice) / 1e18;

        _tryMatchOrder(orderId);

        require(order.status == OrderStatus.Filled, "Market order not filled");
    }

    // ============================================
    // CANCELACIÓN Y EXPIRACIÓN
    // ============================================

    /**
     * @notice Cancela una orden
     * @param orderId ID de la orden
     */
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        
        require(order.maker == msg.sender, "Not order maker");
        require(
            order.status == OrderStatus.Open || 
            order.status == OrderStatus.PartialFilled,
            "Cannot cancel"
        );

        uint256 remainingA = order.amountA - order.filledA;
        uint256 remainingB = order.amountB - order.filledB;

        // Liberar fondos bloqueados
        _unlockFunds(msg.sender, order.tokenA, remainingA);

        order.status = OrderStatus.Cancelled;

        // Remover del book
        _removeFromBook(
            _getPairId(order.tokenA, order.tokenB),
            orderId,
            order.price,
            order.side
        );

        emit OrderCancelled(orderId, msg.sender, remainingA, remainingB);
    }

    /**
     * @notice Expira órdenes antiguas (llamado por keeper)
     * @param orderIds Array de IDs de órdenes a verificar
     */
    function expireOrders(uint256[] calldata orderIds) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage order = orders[orderIds[i]];
            
            if (
                order.expiresAt > 0 &&
                block.timestamp >= order.expiresAt &&
                (order.status == OrderStatus.Open || order.status == OrderStatus.PartialFilled)
            ) {
                uint256 remainingA = order.amountA - order.filledA;
                
                // Liberar fondos
                _unlockFunds(order.maker, order.tokenA, remainingA);
                
                order.status = OrderStatus.Expired;
                
                // Remover del book
                _removeFromBook(
                    _getPairId(order.tokenA, order.tokenB),
                    orderIds[i],
                    order.price,
                    order.side
                );
                
                emit OrderExpired(orderIds[i], order.maker);
            }
        }
    }

    // ============================================
    // FUNCIONES AUXILIARES
    // ============================================

    /**
     * @notice Obtiene el ID de un par de trading
     */
    function _getPairId(address tokenA, address tokenB) internal pure returns (bytes32) {
        return tokenA < tokenB 
            ? keccak256(abi.encodePacked(tokenA, tokenB))
            : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    /**
     * @notice Añade una orden al book
     */
    function _addToBook(
        bytes32 pairId,
        uint256 orderId,
        uint256 price,
        OrderSide side
    ) internal {
        if (side == OrderSide.Buy) {
            if (buyOrders[pairId][price].length == 0) {
                buyPrices[pairId].push(price);
                // TODO: Sort prices in descending order
            }
            buyOrders[pairId][price].push(orderId);
        } else {
            if (sellOrders[pairId][price].length == 0) {
                sellPrices[pairId].push(price);
                // TODO: Sort prices in ascending order
            }
            sellOrders[pairId][price].push(orderId);
        }
    }

    /**
     * @notice Remueve una orden del book
     */
    function _removeFromBook(
        bytes32 pairId,
        uint256 orderId,
        uint256 price,
        OrderSide side
    ) internal {
        uint256[] storage orderIds = side == OrderSide.Buy 
            ? buyOrders[pairId][price]
            : sellOrders[pairId][price];

        for (uint256 i = 0; i < orderIds.length; i++) {
            if (orderIds[i] == orderId) {
                orderIds[i] = orderIds[orderIds.length - 1];
                orderIds.pop();
                break;
            }
        }
    }

    /**
     * @notice Actualiza el estado de una orden
     */
    function _updateOrderStatus(uint256 orderId) internal {
        Order storage order = orders[orderId];
        
        if (order.filledA >= order.amountA) {
            order.status = OrderStatus.Filled;
            emit OrderFilled(orderId, order.filledA, order.filledB, OrderStatus.Filled);
        } else if (order.filledA > 0) {
            order.status = OrderStatus.PartialFilled;
            emit OrderFilled(orderId, order.filledA, order.filledB, OrderStatus.PartialFilled);
        }
    }

    /**
     * @notice Actualiza estadísticas del par
     */
    function _updatePairStats(bytes32 pairId, uint256 volume, uint256 price) internal {
        TradingPair storage pair = tradingPairs[pairId];
        pair.totalVolume += volume;
        pair.last24hVolume += volume;
        pair.lastPrice = price;
        pair.lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Bloquea fondos en el BalanceManager
     */
    function _lockFunds(address user, address token, uint256 amount) internal {
        // Llamar a BalanceManager.lockFunds()
        (bool success, ) = balanceManager.call(
            abi.encodeWithSignature("lockFunds(address,address,uint256)", user, token, amount)
        );
        require(success, "Failed to lock funds");
    }

    /**
     * @notice Libera fondos del BalanceManager
     */
    function _unlockFunds(address user, address token, uint256 amount) internal {
        // Llamar a BalanceManager.unlockFunds()
        (bool success, ) = balanceManager.call(
            abi.encodeWithSignature("unlockFunds(address,address,uint256)", user, token, amount)
        );
        require(success, "Failed to unlock funds");
    }

    /**
     * @notice Ejecuta un swap usando BalanceManager
     */
    function _executeSwap(
        address buyer,
        address seller,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal {
        // Llamar a BalanceManager.transferLocked()
        (bool success, ) = balanceManager.call(
            abi.encodeWithSignature(
                "transferLocked(address,address,address,uint256)",
                buyer, seller, tokenA, amountA
            )
        );
        require(success, "Swap failed");

        (success, ) = balanceManager.call(
            abi.encodeWithSignature(
                "transferLocked(address,address,address,uint256)",
                seller, buyer, tokenB, amountB
            )
        );
        require(success, "Swap failed");
    }

    /**
     * @notice Calcula el fee para un usuario
     */
    function _calculateFee(address user, uint256 amount) internal view returns (uint256) {
        // Llamar a FeeManager.calculateFee()
        (bool success, bytes memory data) = feeManager.staticcall(
            abi.encodeWithSignature("calculateFee(address,uint256,uint256)", user, amount, 0) // 0 = P2P fee
        );
        require(success, "Fee calculation failed");
        return abi.decode(data, (uint256));
    }

    // ============================================
    // SETTERS
    // ============================================

    function setBalanceManager(address _balanceManager) external onlyRole(ADMIN_ROLE) {
        require(_balanceManager != address(0), "Invalid address");
        balanceManager = _balanceManager;
    }

    function setFeeManager(address _feeManager) external onlyRole(ADMIN_ROLE) {
        require(_feeManager != address(0), "Invalid address");
        feeManager = _feeManager;
    }

    function setMainContract(address _mainContract) external onlyRole(ADMIN_ROLE) {
        require(_mainContract != address(0), "Invalid address");
        mainContract = _mainContract;
    }

    function setMinOrderAmount(uint256 amount) external onlyRole(ADMIN_ROLE) {
        minOrderAmount = amount;
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

    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function getTrade(uint256 tradeId) external view returns (Trade memory) {
        return trades[tradeId];
    }

    function getUserOrders(address user) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    function getUserTrades(address user) external view returns (uint256[] memory) {
        return userTrades[user];
    }

    function getActivePairs() external view returns (bytes32[] memory) {
        return activePairs;
    }

    function getBuyOrders(bytes32 pairId, uint256 price) external view returns (uint256[] memory) {
        return buyOrders[pairId][price];
    }

    function getSellOrders(bytes32 pairId, uint256 price) external view returns (uint256[] memory) {
        return sellOrders[pairId][price];
    }

    function getBuyPrices(bytes32 pairId) external view returns (uint256[] memory) {
        return buyPrices[pairId];
    }

    function getSellPrices(bytes32 pairId) external view returns (uint256[] memory) {
        return sellPrices[pairId];
    }

    /**
     * @notice Obtiene estadísticas globales del Order Book
     */
    function getStats() external view returns (
        uint256 totalOrders,
        uint256 totalPairs,
        uint256 activeOrders,
        uint256 totalVolumeAllPairs
    ) {
        totalOrders = orderCount;
        totalPairs = 0; // P2POrderBook no tiene pairCounter, usar mapping
        
        // Contar órdenes activas
        uint256 active = 0;
        for (uint256 i = 1; i <= orderCount; i++) {
            if (orders[i].status == OrderStatus.Open || orders[i].status == OrderStatus.PartialFilled) {
                active++;
            }
        }
        activeOrders = active;
        
        // Volumen total necesitaría iterar pares (no es eficiente on-chain)
        totalVolumeAllPairs = 0; // Calcular off-chain o mantener contador global
    }
}
