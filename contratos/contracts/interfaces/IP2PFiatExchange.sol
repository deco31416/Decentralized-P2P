// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IP2PFiatExchange
 * @notice Interface para intercambios P2P fiat-to-fiat
 * @dev Soporta órdenes USD → COP con intermediarios y sistema de escrow
 */
interface IP2PFiatExchange {
    
    /// @notice Estados de una orden fiat-to-fiat
    enum FiatOrderStatus {
        Created,              // Usuario creó orden
        IntermediaryAccepted, // Intermediario aceptó, USDT bloqueado
        USDSent,              // Usuario marcó "USD enviado"
        COPSent,              // Intermediario marcó "COP enviado"
        Completed,            // Usuario confirmó "COP recibido"
        Disputed,             // Disputa abierta
        Cancelled             // Cancelada
    }
    
    /// @notice Información de comisiones fiat
    struct FiatFees {
        uint256 entryFeePercent;      // Comisión entrada (USD→USDT)
        uint256 exitFeePercent;       // Comisión salida (USDT→COP)
        uint256 entryFeeAmount;       // Monto en USD
        uint256 exitFeeAmount;        // Monto en USDT
        uint256 totalFeeUSDT;         // Total ganado por intermediario
    }
    
    /// @notice Orden Fiat-to-Fiat completa
    struct FiatToFiatOrder {
        uint256 orderId;
        address user;                 // Usuario final
        address intermediary;         // Intermediario (address(0) si no aceptada)
        string fiatFrom;              // "USD", "EUR", etc.
        string fiatTo;                // "COP", "MXN", etc.
        uint256 amountFrom;           // Cantidad fiat entrada (USD)
        uint256 amountTo;             // Cantidad fiat salida (COP)
        uint256 usdtAmount;           // USDT bloqueado del intermediario
        FiatFees fees;                // Estructura de comisiones
        FiatOrderStatus status;       // Estado actual
        uint256 createdAt;
        uint256 acceptedAt;
        uint256 usdSentAt;
        uint256 copSentAt;
        uint256 completedAt;
        uint256 deadline;             // 24h desde acceptedAt
        string userBankProof;         // IPFS hash comprobante USD
        string intermediaryBankProof; // IPFS hash comprobante COP
    }
    
    // ============================================
    // EVENTOS
    // ============================================
    
    event FiatOrderCreated(
        uint256 indexed orderId,
        address indexed user,
        string fiatFrom,
        string fiatTo,
        uint256 amount
    );
    
    event FiatOrderAccepted(
        uint256 indexed orderId,
        address indexed intermediary,
        uint256 usdtLocked
    );
    
    event USDSent(
        uint256 indexed orderId,
        address indexed user,
        string bankProof
    );
    
    event COPSent(
        uint256 indexed orderId,
        address indexed intermediary,
        string bankProof
    );
    
    event FiatOrderCompleted(
        uint256 indexed orderId,
        address indexed intermediary,
        uint256 feesEarned
    );
    
    event FiatOrderDisputed(
        uint256 indexed orderId,
        string reason
    );
    
    event FiatOrderCancelled(
        uint256 indexed orderId,
        address indexed canceller
    );
    
    // ============================================
    // FUNCIONES PRINCIPALES
    // ============================================
    
    /**
     * @notice Usuario crea orden fiat-to-fiat (USD → COP)
     * @param fiatFrom Moneda fiat de entrada ("USD", "EUR", etc.)
     * @param fiatTo Moneda fiat de salida ("COP", "MXN", etc.)
     * @param amountFrom Cantidad en fiat de entrada (ej: 1000 USD)
     * @param expectedRate Tasa de cambio esperada (ej: 1 USD = 5000 COP)
     * @return orderId ID de la orden creada
     */
    function createFiatToFiatOrder(
        string memory fiatFrom,
        string memory fiatTo,
        uint256 amountFrom,
        uint256 expectedRate
    ) external returns (uint256 orderId);
    
    /**
     * @notice Intermediario acepta orden (bloquea USDT)
     * @param orderId ID de la orden a aceptar
     */
    function acceptFiatOrder(uint256 orderId) external;
    
    /**
     * @notice Usuario marca USD enviado (sube comprobante)
     * @param orderId ID de la orden
     * @param bankProofIPFS Hash IPFS del comprobante bancario
     */
    function markUSDSent(uint256 orderId, string memory bankProofIPFS) external;
    
    /**
     * @notice Intermediario marca COP enviado (sube comprobante)
     * @param orderId ID de la orden
     * @param bankProofIPFS Hash IPFS del comprobante bancario
     */
    function markCOPSent(uint256 orderId, string memory bankProofIPFS) external;
    
    /**
     * @notice Usuario confirma COP recibido (libera USDT)
     * @param orderId ID de la orden
     */
    function confirmCOPReceived(uint256 orderId) external;
    
    /**
     * @notice Cancelar orden antes de ser aceptada
     * @param orderId ID de la orden
     */
    function cancelFiatOrder(uint256 orderId) external;
    
    /**
     * @notice Marcar orden como en disputa por timeout
     * @param orderId ID de la orden
     */
    function timeoutFiatOrder(uint256 orderId) external;
    
    // ============================================
    // VISTAS
    // ============================================
    
    /**
     * @notice Obtener información de orden
     */
    function getFiatOrder(uint256 orderId) external view returns (FiatToFiatOrder memory);
    
    /**
     * @notice Obtener órdenes de un usuario
     */
    function getUserFiatOrders(address user) external view returns (uint256[] memory);
    
    /**
     * @notice Obtener órdenes de un intermediario
     */
    function getIntermediaryFiatOrders(address intermediary) external view returns (uint256[] memory);
    
    /**
     * @notice Obtener órdenes activas (disponibles para aceptar)
     */
    function getActiveFiatOrders() external view returns (uint256[] memory);
}
