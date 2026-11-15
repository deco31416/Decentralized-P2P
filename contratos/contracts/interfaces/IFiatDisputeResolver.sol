// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFiatDisputeResolver
 * @notice Interface para resolución de disputas en órdenes fiat
 * @dev Admin revisa comprobantes bancarios y decide
 */
interface IFiatDisputeResolver {
    
    /// @notice Resultado de una disputa
    enum DisputeOutcome {
        Pending,              // En revisión
        UserWins,             // Usuario gana, recupera fondos
        IntermediaryWins,     // Intermediario gana, recibe USDT
        PartialRefund         // Reembolso parcial (50/50)
    }
    
    /// @notice Información de una disputa
    struct Dispute {
        uint256 disputeId;
        uint256 orderId;
        address user;
        address intermediary;
        address initiator;        // Quien inició la disputa
        string reason;            // Razón de la disputa
        uint256 createdAt;
        uint256 resolvedAt;
        DisputeOutcome outcome;
        string adminNotes;        // Notas del admin
    }
    
    // ============================================
    // EVENTOS
    // ============================================
    
    event DisputeRaised(
        uint256 indexed disputeId,
        uint256 indexed orderId,
        address indexed initiator,
        string reason
    );
    
    event DisputeResolved(
        uint256 indexed disputeId,
        uint256 indexed orderId,
        DisputeOutcome outcome,
        string adminNotes
    );
    
    event EvidenceSubmitted(
        uint256 indexed disputeId,
        address indexed submitter,
        string evidenceIPFS
    );
    
    // ============================================
    // FUNCIONES
    // ============================================
    
    /**
     * @notice Crear una disputa para una orden
     * @param orderId ID de la orden fiat
     * @param reason Razón de la disputa
     */
    function raiseDispute(uint256 orderId, string memory reason) external returns (uint256 disputeId);
    
    /**
     * @notice Enviar evidencia adicional
     * @param disputeId ID de la disputa
     * @param evidenceIPFS Hash IPFS de la evidencia
     */
    function submitEvidence(uint256 disputeId, string memory evidenceIPFS) external;
    
    /**
     * @notice Admin resuelve disputa
     * @param disputeId ID de la disputa
     * @param outcome Resultado (UserWins, IntermediaryWins, etc.)
     * @param adminNotes Notas explicativas
     */
    function resolveDispute(
        uint256 disputeId,
        DisputeOutcome outcome,
        string memory adminNotes
    ) external;
    
    // ============================================
    // VISTAS
    // ============================================
    
    /**
     * @notice Obtener información de una disputa
     */
    function getDispute(uint256 disputeId) external view returns (Dispute memory);
    
    /**
     * @notice Obtener disputas pendientes
     */
    function getPendingDisputes() external view returns (uint256[] memory);
    
    /**
     * @notice Obtener disputas de una orden
     */
    function getOrderDisputes(uint256 orderId) external view returns (uint256[] memory);
}
