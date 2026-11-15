// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IFiatDisputeResolver.sol";

/**
 * @title FiatDisputeResolver
 * @notice Resolución de disputas para órdenes fiat-to-fiat
 * @dev Admin revisa comprobantes bancarios (IPFS) y decide el resultado
 * 
 * Flujo:
 * 1. Timeout 24h sin confirmación → raiseDispute() automático
 * 2. Usuario/Intermediario: submitEvidence(ipfs://comprobante)
 * 3. Admin: resolveDispute(disputeId, UserWins/IntermediaryWins)
 * 4. Fondos se liberan según decisión
 */
contract FiatDisputeResolver is AccessControl, ReentrancyGuard, IFiatDisputeResolver {
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    
    // ============================================
    // VARIABLES DE ESTADO
    // ============================================
    
    /// @notice Contador de disputas
    uint256 public disputeCount;
    
    /// @notice Mapeo de ID a disputa
    mapping(uint256 => Dispute) public disputes;
    
    /// @notice Disputas pendientes
    uint256[] public pendingDisputeIds;
    
    /// @notice Disputas por orden
    mapping(uint256 => uint256[]) public orderDisputes;
    
    /// @notice Evidencias adicionales por disputa
    mapping(uint256 => string[]) public disputeEvidence;
    
    /// @notice Dirección del contrato P2PFiatExchange
    address public p2pFiatExchange;
    
    /// @notice Tiempo máximo para resolver disputa (7 días)
    uint256 public constant MAX_RESOLUTION_TIME = 7 days;
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor(address _admin, address _p2pFiatExchange) {
        require(_admin != address(0), "Invalid admin");
        require(_p2pFiatExchange != address(0), "Invalid P2P contract");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(RESOLVER_ROLE, _admin);
        
        p2pFiatExchange = _p2pFiatExchange;
    }
    
    // ============================================
    // FUNCIONES PRINCIPALES
    // ============================================
    
    /**
     * @notice Crear una disputa para una orden
     * @param orderId ID de la orden fiat
     * @param reason Razón de la disputa
     */
    function raiseDispute(uint256 orderId, string memory reason) 
        external 
        nonReentrant
        returns (uint256 disputeId) 
    {
        require(bytes(reason).length > 0, "Empty reason");
        
        // Solo P2PFiatExchange puede crear disputas automáticas
        // O el usuario/intermediario manualmente
        require(
            msg.sender == p2pFiatExchange || 
            _isOrderParticipant(orderId, msg.sender),
            "Not authorized"
        );
        
        disputeCount++;
        disputeId = disputeCount;
        
        // Obtener participantes de la orden
        (address user, address intermediary) = _getOrderParticipants(orderId);
        
        disputes[disputeId] = Dispute({
            disputeId: disputeId,
            orderId: orderId,
            user: user,
            intermediary: intermediary,
            initiator: msg.sender == p2pFiatExchange ? address(0) : msg.sender,
            reason: reason,
            createdAt: block.timestamp,
            resolvedAt: 0,
            outcome: DisputeOutcome.Pending,
            adminNotes: ""
        });
        
        pendingDisputeIds.push(disputeId);
        orderDisputes[orderId].push(disputeId);
        
        emit DisputeRaised(disputeId, orderId, msg.sender, reason);
        
        return disputeId;
    }
    
    /**
     * @notice Enviar evidencia adicional
     * @param disputeId ID de la disputa
     * @param evidenceIPFS Hash IPFS de la evidencia
     */
    function submitEvidence(uint256 disputeId, string memory evidenceIPFS)
        external
        nonReentrant
    {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.createdAt > 0, "Dispute not found");
        require(dispute.outcome == DisputeOutcome.Pending, "Already resolved");
        require(bytes(evidenceIPFS).length > 0, "Empty evidence");
        require(
            msg.sender == dispute.user || msg.sender == dispute.intermediary,
            "Not participant"
        );
        
        disputeEvidence[disputeId].push(evidenceIPFS);
        
        emit EvidenceSubmitted(disputeId, msg.sender, evidenceIPFS);
    }
    
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
    ) external onlyRole(RESOLVER_ROLE) nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.createdAt > 0, "Dispute not found");
        require(dispute.outcome == DisputeOutcome.Pending, "Already resolved");
        require(outcome != DisputeOutcome.Pending, "Invalid outcome");
        
        dispute.outcome = outcome;
        dispute.resolvedAt = block.timestamp;
        dispute.adminNotes = adminNotes;
        
        // Remover de disputas pendientes
        _removePendingDispute(disputeId);
        
        emit DisputeResolved(disputeId, dispute.orderId, outcome, adminNotes);
        
        // Notificar al contrato P2P para liberar fondos
        _executeResolution(dispute.orderId, outcome);
    }
    
    // ============================================
    // FUNCIONES INTERNAS
    // ============================================
    
    /**
     * @notice Verificar si msg.sender es participante de la orden
     * @dev Integrado con P2PFiatExchange.getFiatOrder
     */
    function _isOrderParticipant(uint256 orderId, address account) 
        internal 
        view 
        returns (bool) 
    {
        if (p2pFiatExchange == address(0)) {
            return false;
        }
        
        // Obtener orden del contrato P2P
        (bool success, bytes memory data) = p2pFiatExchange.staticcall(
            abi.encodeWithSignature("getFiatOrder(uint256)", orderId)
        );
        
        if (!success) {
            return false;
        }
        
        // Decodificar solo orderId, user, intermediary (primeros 3 campos del struct)
        (
            , // orderId
            address orderUser,
            address orderIntermediary
            // ... resto ignorado
        ) = abi.decode(data, (uint256, address, address));
        
        return account == orderUser || account == orderIntermediary;
    }
    
    /**
     * @notice Obtener participantes de una orden
     * @dev Integrado con P2PFiatExchange.getFiatOrder
     */
    function _getOrderParticipants(uint256 orderId)
        internal
        view
        returns (address user, address intermediary)
    {
        if (p2pFiatExchange == address(0)) {
            return (address(0), address(0));
        }
        
        // Obtener orden del contrato P2P
        (bool success, bytes memory data) = p2pFiatExchange.staticcall(
            abi.encodeWithSignature("getFiatOrder(uint256)", orderId)
        );
        
        if (!success) {
            return (address(0), address(0));
        }
        
        // Decodificar solo orderId, user, intermediary
        (
            , // orderId
            address orderUser,
            address orderIntermediary
            // ... resto ignorado
        ) = abi.decode(data, (uint256, address, address));
        
        return (orderUser, orderIntermediary);
    }
    
    /**
     * @notice Ejecutar resolución de disputa - libera fondos según outcome
     * @dev Integrado con P2PFiatExchange.resolveDisputeAndReleaseFunds
     */
    function _executeResolution(uint256 orderId, DisputeOutcome outcome) 
        internal 
    {
        require(p2pFiatExchange != address(0), "P2P not configured");
        
        // Convertir DisputeOutcome a releaseTo (uint8)
        // 0 = usuario gana, 1 = intermediario gana, 2 = 50/50
        uint8 releaseTo;
        
        if (outcome == DisputeOutcome.UserWins) {
            releaseTo = 0;
        } else if (outcome == DisputeOutcome.IntermediaryWins) {
            releaseTo = 1;
        } else if (outcome == DisputeOutcome.PartialRefund) {
            releaseTo = 2;
        } else {
            revert("Invalid outcome");
        }
        
        // Llamar a P2PFiatExchange para liberar fondos
        (bool success, ) = p2pFiatExchange.call(
            abi.encodeWithSignature(
                "resolveDisputeAndReleaseFunds(uint256,uint8)",
                orderId,
                releaseTo
            )
        );
        
        require(success, "Fund release failed");
    }
    
    /**
     * @notice Remover disputa de lista de pendientes
     */
    function _removePendingDispute(uint256 disputeId) internal {
        for (uint256 i = 0; i < pendingDisputeIds.length; i++) {
            if (pendingDisputeIds[i] == disputeId) {
                pendingDisputeIds[i] = pendingDisputeIds[pendingDisputeIds.length - 1];
                pendingDisputeIds.pop();
                break;
            }
        }
    }
    
    // ============================================
    // VISTAS
    // ============================================
    
    /**
     * @notice Obtener información de una disputa
     */
    function getDispute(uint256 disputeId) 
        external 
        view 
        returns (Dispute memory) 
    {
        return disputes[disputeId];
    }
    
    /**
     * @notice Obtener disputas pendientes
     */
    function getPendingDisputes() 
        external 
        view 
        returns (uint256[] memory) 
    {
        return pendingDisputeIds;
    }
    
    /**
     * @notice Obtener disputas de una orden
     */
    function getOrderDisputes(uint256 orderId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return orderDisputes[orderId];
    }
    
    /**
     * @notice Obtener evidencias de una disputa
     */
    function getDisputeEvidence(uint256 disputeId)
        external
        view
        returns (string[] memory)
    {
        return disputeEvidence[disputeId];
    }
    
    /**
     * @notice Obtener estadísticas de disputas
     */
    function getDisputeStats()
        external
        view
        returns (
            uint256 totalDisputes,
            uint256 pending,
            uint256 userWins,
            uint256 intermediaryWins,
            uint256 partialRefunds
        )
    {
        totalDisputes = disputeCount;
        pending = pendingDisputeIds.length;
        
        for (uint256 i = 1; i <= disputeCount; i++) {
            DisputeOutcome outcome = disputes[i].outcome;
            if (outcome == DisputeOutcome.UserWins) userWins++;
            else if (outcome == DisputeOutcome.IntermediaryWins) intermediaryWins++;
            else if (outcome == DisputeOutcome.PartialRefund) partialRefunds++;
        }
    }
    
    // ============================================
    // FUNCIONES ADMIN
    // ============================================
    
    /**
     * @notice Actualizar dirección del contrato P2P
     */
    function setP2PFiatExchange(address _p2pFiatExchange)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(_p2pFiatExchange != address(0), "Invalid address");
        p2pFiatExchange = _p2pFiatExchange;
    }
    
    /**
     * @notice Agregar resolver adicional
     */
    function grantResolverRole(address resolver)
        external
        onlyRole(ADMIN_ROLE)
    {
        grantRole(RESOLVER_ROLE, resolver);
    }
    
    /**
     * @notice Remover resolver
     */
    function revokeResolverRole(address resolver)
        external
        onlyRole(ADMIN_ROLE)
    {
        revokeRole(RESOLVER_ROLE, resolver);
    }
}
