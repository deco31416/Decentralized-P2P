// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IDOManager
 * @notice Sistema completo de Initial DEX Offerings (IDO)
 * @dev Implementa pools IDO con vesting, whitelist y caps por usuario
 * 
 * Características principales:
 * - Creación de pools IDO con configuración flexible
 * - Whitelist de participantes con caps individuales
 * - Vesting schedules personalizables
 * - Tiers de participación (Bronce, Plata, Oro, Platino)
 * - Distribución automática de tokens
 * - Sistema de reembolso en caso de fallo
 * - Staking requirements por tier
 * 
 * Flujo de un IDO:
 * 1. Admin: createIDO(token, price, hardCap, startTime, endTime) → Pool creado
 * 2. Admin: addToWhitelist(user, tier, cap) → Usuario whitelisted
 * 3. Usuario: participate(idoId, amount) → Compra tokens en el IDO
 * 4. Admin: finalizeIDO(idoId) si hardCap alcanzado → Activa distribución
 * 5. Usuario: claimTokens(idoId) → Reclama tokens según vesting
 * 
 * Estados de IDO:
 * Pending → Active → Completed → Finalized
 *           ↓         ↓
 *        Cancelled  Failed
 */
contract IDOManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============================================
    // ROLES
    // ============================================
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============================================
    // ENUMS
    // ============================================

    /// @notice Estados de un IDO
    enum IDOStatus {
        Pending,        // Creado pero no iniciado
        Active,         // En curso, aceptando participaciones
        Completed,      // Terminado, esperando finalización
        Finalized,      // Finalizado, tokens distribuibles
        Cancelled,      // Cancelado, reembolsos disponibles
        Failed          // Falló (no alcanzó softCap), reembolsos disponibles
    }

    /// @notice Tiers de participación
    enum Tier {
        None,           // No whitelisted
        Bronze,         // Bronce - Cap bajo
        Silver,         // Plata - Cap medio
        Gold,           // Oro - Cap alto
        Platinum        // Platino - Cap muy alto + early access
    }

    // ============================================
    // ESTRUCTURAS
    // ============================================

    /// @notice Configuración de vesting
    struct VestingSchedule {
        uint256 cliffDuration;      // Cliff en segundos (ej: 30 días)
        uint256 vestingDuration;    // Duración total del vesting
        uint256 tgePercentage;      // % liberado en TGE (10000 = 100%)
        uint256 vestingInterval;    // Intervalo entre releases (ej: 7 días)
    }

    /// @notice Pool de IDO
    struct IDOPool {
        uint256 idoId;
        address projectToken;       // Token a vender
        address paymentToken;       // Token de pago (USDT, BUSD, etc.)
        uint256 tokenPrice;         // Precio por token (en payment token, 1e18 = 1:1)
        uint256 softCap;            // Mínimo para considerar exitoso
        uint256 hardCap;            // Máximo total a recaudar
        uint256 totalRaised;        // Total recaudado hasta ahora
        uint256 totalSold;          // Total de tokens vendidos
        uint256 minParticipation;   // Mínima participación por usuario
        uint256 maxParticipation;   // Máxima participación por usuario (default)
        uint256 startTime;          // Timestamp de inicio
        uint256 endTime;            // Timestamp de fin
        uint256 tgeTime;            // Token Generation Event timestamp
        IDOStatus status;
        VestingSchedule vesting;
        uint256 participantCount;   // Total de participantes
        bool whitelistOnly;         // Solo usuarios whitelisted
        uint256 earlyAccessDuration; // Duración de early access para Platinum
        uint256 createdAt;
    }

    /// @notice Participación de usuario en un IDO
    struct UserParticipation {
        uint256 amountPaid;         // Cantidad pagada en payment token
        uint256 tokensAllocated;    // Tokens asignados
        uint256 tokensClaimed;      // Tokens reclamados
        uint256 lastClaimTime;      // Último claim
        bool hasParticipated;
        bool hasRefunded;           // Si ya recibió reembolso
        Tier tier;
        uint256 maxAllocation;      // Cap personalizado
    }

    /// @notice Información de whitelist del usuario
    struct WhitelistInfo {
        bool isWhitelisted;
        Tier tier;
        uint256 customCap;          // Cap personalizado (0 = usar default del tier)
        uint256 stakedAmount;       // Cantidad de tokens stakeados
        uint256 whitelistedAt;
    }

    // ============================================
    // VARIABLES DE ESTADO
    // ============================================

    /// @notice Contador de IDOs
    uint256 public idoCount;

    /// @notice Mapeo de ID a pool de IDO
    mapping(uint256 => IDOPool) public idoPools;

    /// @notice Participación de usuarios: idoId => user => participation
    mapping(uint256 => mapping(address => UserParticipation)) public userParticipations;

    /// @notice Whitelist por IDO: idoId => user => info
    mapping(uint256 => mapping(address => WhitelistInfo)) public whitelists;

    /// @notice Lista de participantes por IDO
    mapping(uint256 => address[]) public idoParticipants;

    /// @notice Caps por tier (en payment token, ej: USDT)
    mapping(Tier => uint256) public tierCaps;

    /// @notice Requisitos de staking por tier (en platform token)
    mapping(Tier => uint256) public tierStakingRequirements;

    /// @notice Fee del IDO (en basis points, 100 = 1%)
    uint256 public platformFeeBps = 300; // 3%

    /// @notice Wallet para recibir fees
    address public feeCollector;

    // ============================================
    // EVENTOS
    // ============================================

    event IDOCreated(
        uint256 indexed idoId,
        address indexed projectToken,
        address indexed paymentToken,
        uint256 tokenPrice,
        uint256 hardCap,
        uint256 startTime,
        uint256 endTime
    );

    event IDOStatusChanged(uint256 indexed idoId, IDOStatus oldStatus, IDOStatus newStatus);

    event UserWhitelisted(
        uint256 indexed idoId,
        address indexed user,
        Tier tier,
        uint256 maxAllocation
    );

    event UserParticipated(
        uint256 indexed idoId,
        address indexed user,
        uint256 amountPaid,
        uint256 tokensAllocated
    );

    event TokensClaimed(
        uint256 indexed idoId,
        address indexed user,
        uint256 amount
    );

    event IDOFinalized(uint256 indexed idoId, uint256 totalRaised, uint256 totalSold);

    event RefundIssued(uint256 indexed idoId, address indexed user, uint256 amount);

    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(address _admin, address _feeCollector) {
        require(_admin != address(0), "Invalid admin");
        require(_feeCollector != address(0), "Invalid fee collector");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        feeCollector = _feeCollector;

        // Configurar caps por tier (en USDT con 18 decimales)
        tierCaps[Tier.Bronze] = 500e18;     // $500
        tierCaps[Tier.Silver] = 2000e18;    // $2,000
        tierCaps[Tier.Gold] = 5000e18;      // $5,000
        tierCaps[Tier.Platinum] = 10000e18; // $10,000

        // Configurar requisitos de staking (en platform token)
        tierStakingRequirements[Tier.Bronze] = 1000e18;     // 1,000 tokens
        tierStakingRequirements[Tier.Silver] = 5000e18;     // 5,000 tokens
        tierStakingRequirements[Tier.Gold] = 15000e18;      // 15,000 tokens
        tierStakingRequirements[Tier.Platinum] = 50000e18;  // 50,000 tokens
    }

    // ============================================
    // FUNCIONES DE CREACIÓN Y GESTIÓN DE IDO
    // ============================================

    /**
     * @notice Crea un nuevo pool de IDO
     * @param projectToken Token del proyecto a vender
     * @param paymentToken Token de pago (USDT, BUSD, etc.)
     * @param tokenPrice Precio por token
     * @param softCap Mínimo para considerar exitoso
     * @param hardCap Máximo a recaudar
     * @param minParticipation Mínima participación por usuario
     * @param maxParticipation Máxima participación por usuario
     * @param startTime Timestamp de inicio
     * @param endTime Timestamp de fin
     * @param tgeTime Token Generation Event timestamp
     * @param whitelistOnly Solo usuarios whitelisted
     */
    function createIDO(
        address projectToken,
        address paymentToken,
        uint256 tokenPrice,
        uint256 softCap,
        uint256 hardCap,
        uint256 minParticipation,
        uint256 maxParticipation,
        uint256 startTime,
        uint256 endTime,
        uint256 tgeTime,
        bool whitelistOnly,
        VestingSchedule calldata vesting
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        require(projectToken != address(0) && paymentToken != address(0), "Invalid tokens");
        require(tokenPrice > 0, "Invalid price");
        require(softCap > 0 && softCap <= hardCap, "Invalid caps");
        require(minParticipation > 0 && minParticipation <= maxParticipation, "Invalid participation limits");
        require(startTime > block.timestamp, "Start time must be future");
        require(endTime > startTime, "End time must be after start");
        require(tgeTime >= endTime, "TGE must be after IDO end");
        require(vesting.tgePercentage <= 10000, "TGE % too high");

        idoCount++;
        uint256 idoId = idoCount;

        idoPools[idoId] = IDOPool({
            idoId: idoId,
            projectToken: projectToken,
            paymentToken: paymentToken,
            tokenPrice: tokenPrice,
            softCap: softCap,
            hardCap: hardCap,
            totalRaised: 0,
            totalSold: 0,
            minParticipation: minParticipation,
            maxParticipation: maxParticipation,
            startTime: startTime,
            endTime: endTime,
            tgeTime: tgeTime,
            status: IDOStatus.Pending,
            vesting: vesting,
            participantCount: 0,
            whitelistOnly: whitelistOnly,
            earlyAccessDuration: 24 hours, // Platinum early access por defecto
            createdAt: block.timestamp
        });

        emit IDOCreated(idoId, projectToken, paymentToken, tokenPrice, hardCap, startTime, endTime);

        return idoId;
    }

    /**
     * @notice Agrega usuarios a la whitelist de un IDO
     * @param idoId ID del IDO
     * @param users Array de direcciones de usuarios
     * @param tiers Array de tiers correspondientes
     * @param customCaps Array de caps personalizados (0 = usar default)
     */
    function addToWhitelist(
        uint256 idoId,
        address[] calldata users,
        Tier[] calldata tiers,
        uint256[] calldata customCaps
    ) external onlyRole(OPERATOR_ROLE) {
        require(users.length == tiers.length && users.length == customCaps.length, "Length mismatch");
        
        IDOPool storage ido = idoPools[idoId];
        require(ido.idoId != 0, "IDO not found");
        require(ido.status == IDOStatus.Pending, "IDO already started");

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            Tier tier = tiers[i];
            uint256 customCap = customCaps[i];

            require(user != address(0), "Invalid user");
            require(tier != Tier.None, "Invalid tier");

            uint256 maxAllocation = customCap > 0 ? customCap : tierCaps[tier];

            whitelists[idoId][user] = WhitelistInfo({
                isWhitelisted: true,
                tier: tier,
                customCap: customCap,
                stakedAmount: 0, // Se actualizaría con integración de staking
                whitelistedAt: block.timestamp
            });

            emit UserWhitelisted(idoId, user, tier, maxAllocation);
        }
    }

    /**
     * @notice Actualiza el estado de un IDO
     * @param idoId ID del IDO
     */
    function updateIDOStatus(uint256 idoId) public {
        IDOPool storage ido = idoPools[idoId];
        require(ido.idoId != 0, "IDO not found");

        IDOStatus oldStatus = ido.status;
        IDOStatus newStatus = oldStatus;

        // Pending → Active
        if (ido.status == IDOStatus.Pending && block.timestamp >= ido.startTime) {
            newStatus = IDOStatus.Active;
        }
        // Active → Completed
        else if (ido.status == IDOStatus.Active) {
            if (block.timestamp >= ido.endTime || ido.totalRaised >= ido.hardCap) {
                newStatus = IDOStatus.Completed;
            }
        }

        if (newStatus != oldStatus) {
            ido.status = newStatus;
            emit IDOStatusChanged(idoId, oldStatus, newStatus);
        }
    }

    // ============================================
    // FUNCIONES DE PARTICIPACIÓN
    // ============================================

    /**
     * @notice Participa en un IDO
     * @param idoId ID del IDO
     * @param amount Cantidad de payment token a invertir
     */
    function participate(uint256 idoId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        IDOPool storage ido = idoPools[idoId];
        require(ido.idoId != 0, "IDO not found");

        // Actualizar estado
        updateIDOStatus(idoId);

        require(ido.status == IDOStatus.Active, "IDO not active");
        require(block.timestamp >= ido.startTime && block.timestamp < ido.endTime, "Outside IDO period");

        // Verificar early access para Platinum
        if (block.timestamp < ido.startTime + ido.earlyAccessDuration) {
            WhitelistInfo storage whitelist = whitelists[idoId][msg.sender];
            require(whitelist.tier == Tier.Platinum, "Early access only for Platinum");
        }

        // Verificar whitelist si requerido
        if (ido.whitelistOnly) {
            WhitelistInfo storage whitelist = whitelists[idoId][msg.sender];
            require(whitelist.isWhitelisted, "Not whitelisted");
            require(whitelist.tier != Tier.None, "Invalid tier");
        }

        UserParticipation storage participation = userParticipations[idoId][msg.sender];

        // Calcular máxima participación permitida
        uint256 maxAllocation = ido.maxParticipation;
        if (ido.whitelistOnly) {
            WhitelistInfo storage whitelist = whitelists[idoId][msg.sender];
            maxAllocation = whitelist.customCap > 0 ? whitelist.customCap : tierCaps[whitelist.tier];
        }

        require(amount >= ido.minParticipation, "Below minimum");
        require(participation.amountPaid + amount <= maxAllocation, "Exceeds max allocation");
        require(ido.totalRaised + amount <= ido.hardCap, "Exceeds hard cap");

        // Calcular tokens a asignar
        uint256 tokensToAllocate = (amount * 1e18) / ido.tokenPrice;

        // Transferir payment token del usuario al contrato
        IERC20(ido.paymentToken).safeTransferFrom(msg.sender, address(this), amount);

        // Actualizar participación
        if (!participation.hasParticipated) {
            participation.hasParticipated = true;
            participation.tier = ido.whitelistOnly ? whitelists[idoId][msg.sender].tier : Tier.None;
            participation.maxAllocation = maxAllocation;
            idoParticipants[idoId].push(msg.sender);
            ido.participantCount++;
        }

        participation.amountPaid += amount;
        participation.tokensAllocated += tokensToAllocate;

        ido.totalRaised += amount;
        ido.totalSold += tokensToAllocate;

        emit UserParticipated(idoId, msg.sender, amount, tokensToAllocate);

        // Actualizar estado si alcanzó hardCap
        if (ido.totalRaised >= ido.hardCap) {
            ido.status = IDOStatus.Completed;
            emit IDOStatusChanged(idoId, IDOStatus.Active, IDOStatus.Completed);
        }
    }

    // ============================================
    // FUNCIONES DE FINALIZACIÓN Y DISTRIBUCIÓN
    // ============================================

    /**
     * @notice Finaliza un IDO después de que termine
     * @param idoId ID del IDO
     */
    function finalizeIDO(uint256 idoId) external onlyRole(OPERATOR_ROLE) {
        IDOPool storage ido = idoPools[idoId];
        require(ido.idoId != 0, "IDO not found");

        // Actualizar estado
        updateIDOStatus(idoId);

        require(ido.status == IDOStatus.Completed, "IDO not completed");
        require(block.timestamp >= ido.endTime, "IDO not ended");

        // Verificar si alcanzó softCap
        if (ido.totalRaised < ido.softCap) {
            ido.status = IDOStatus.Failed;
            emit IDOStatusChanged(idoId, IDOStatus.Completed, IDOStatus.Failed);
            return;
        }

        // Calcular fee de plataforma
        uint256 platformFee = (ido.totalRaised * platformFeeBps) / 10000;
        uint256 projectRevenue = ido.totalRaised - platformFee;

        // Transferir fondos
        IERC20(ido.paymentToken).safeTransfer(feeCollector, platformFee);
        IERC20(ido.paymentToken).safeTransfer(msg.sender, projectRevenue); // Asumiendo que el operator es el proyecto

        ido.status = IDOStatus.Finalized;
        
        emit IDOStatusChanged(idoId, IDOStatus.Completed, IDOStatus.Finalized);
        emit IDOFinalized(idoId, ido.totalRaised, ido.totalSold);
    }

    /**
     * @notice Reclama tokens según el vesting schedule
     * @param idoId ID del IDO
     * @return amount Cantidad de tokens reclamados
     */
    function claimTokens(uint256 idoId) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (uint256 amount) 
    {
        IDOPool storage ido = idoPools[idoId];
        require(ido.idoId != 0, "IDO not found");
        require(ido.status == IDOStatus.Finalized, "IDO not finalized");
        require(block.timestamp >= ido.tgeTime, "TGE not started");

        UserParticipation storage participation = userParticipations[idoId][msg.sender];
        require(participation.hasParticipated, "Not participated");
        require(participation.tokensAllocated > participation.tokensClaimed, "Nothing to claim");

        uint256 claimableAmount = calculateClaimable(idoId, msg.sender);
        require(claimableAmount > 0, "Nothing to claim yet");

        participation.tokensClaimed += claimableAmount;
        participation.lastClaimTime = block.timestamp;

        // Transferir tokens al usuario
        IERC20(ido.projectToken).safeTransfer(msg.sender, claimableAmount);

        emit TokensClaimed(idoId, msg.sender, claimableAmount);

        return claimableAmount;
    }

    /**
     * @notice Calcula la cantidad de tokens reclamables
     * @param idoId ID del IDO
     * @param user Dirección del usuario
     * @return claimable Cantidad de tokens reclamables
     */
    function calculateClaimable(uint256 idoId, address user) 
        public 
        view 
        returns (uint256 claimable) 
    {
        IDOPool storage ido = idoPools[idoId];
        UserParticipation storage participation = userParticipations[idoId][user];

        if (!participation.hasParticipated || block.timestamp < ido.tgeTime) {
            return 0;
        }

        uint256 totalAllocated = participation.tokensAllocated;
        VestingSchedule memory vesting = ido.vesting;

        // TGE release
        uint256 tgeRelease = (totalAllocated * vesting.tgePercentage) / 10000;

        // Verificar cliff
        uint256 cliffEnd = ido.tgeTime + vesting.cliffDuration;
        if (block.timestamp < cliffEnd) {
            // Solo TGE release durante cliff
            return tgeRelease > participation.tokensClaimed ? 
                   tgeRelease - participation.tokensClaimed : 0;
        }

        // Después del cliff, calcular vesting
        uint256 timeSinceCliff = block.timestamp - cliffEnd;
        uint256 vestingEnd = cliffEnd + vesting.vestingDuration;

        if (block.timestamp >= vestingEnd) {
            // Vesting completo
            return totalAllocated - participation.tokensClaimed;
        }

        // Vesting proporcional
        uint256 vestedAmount = tgeRelease + 
            ((totalAllocated - tgeRelease) * timeSinceCliff) / vesting.vestingDuration;

        return vestedAmount > participation.tokensClaimed ? 
               vestedAmount - participation.tokensClaimed : 0;
    }

    // ============================================
    // FUNCIONES DE REEMBOLSO
    // ============================================

    /**
     * @notice Solicita reembolso si el IDO falló
     * @param idoId ID del IDO
     * @return amount Cantidad reembolsada
     */
    function claimRefund(uint256 idoId) 
        external 
        nonReentrant 
        returns (uint256 amount) 
    {
        IDOPool storage ido = idoPools[idoId];
        require(ido.idoId != 0, "IDO not found");
        require(ido.status == IDOStatus.Failed || ido.status == IDOStatus.Cancelled, "IDO not failed/cancelled");

        UserParticipation storage participation = userParticipations[idoId][msg.sender];
        require(participation.hasParticipated, "Not participated");
        require(!participation.hasRefunded, "Already refunded");

        amount = participation.amountPaid;
        require(amount > 0, "Nothing to refund");

        participation.hasRefunded = true;

        // Transferir reembolso
        IERC20(ido.paymentToken).safeTransfer(msg.sender, amount);

        emit RefundIssued(idoId, msg.sender, amount);

        return amount;
    }

    /**
     * @notice Cancela un IDO antes de que inicie
     * @param idoId ID del IDO
     */
    function cancelIDO(uint256 idoId) external onlyRole(ADMIN_ROLE) {
        IDOPool storage ido = idoPools[idoId];
        require(ido.idoId != 0, "IDO not found");
        require(ido.status == IDOStatus.Pending, "IDO already started");

        IDOStatus oldStatus = ido.status;
        ido.status = IDOStatus.Cancelled;

        emit IDOStatusChanged(idoId, oldStatus, IDOStatus.Cancelled);
    }

    // ============================================
    // FUNCIONES DE LECTURA
    // ============================================

    /**
     * @notice Obtiene todos los participantes de un IDO
     * @param idoId ID del IDO
     * @return participants Array de direcciones
     */
    function getIDOParticipants(uint256 idoId) external view returns (address[] memory) {
        return idoParticipants[idoId];
    }

    /**
     * @notice Verifica si un usuario está whitelisted
     * @param idoId ID del IDO
     * @param user Dirección del usuario
     * @return isWhitelisted True si está whitelisted
     */
    function isWhitelisted(uint256 idoId, address user) external view returns (bool) {
        return whitelists[idoId][user].isWhitelisted;
    }

    /**
     * @notice Obtiene el tier de un usuario
     * @param idoId ID del IDO
     * @param user Dirección del usuario
     * @return tier Tier del usuario
     */
    function getUserTier(uint256 idoId, address user) external view returns (Tier) {
        return whitelists[idoId][user].tier;
    }

    // ============================================
    // FUNCIONES ADMINISTRATIVAS
    // ============================================

    /**
     * @notice Actualiza el fee de plataforma
     * @param newFeeBps Nuevo fee en basis points
     */
    function setPlatformFee(uint256 newFeeBps) external onlyRole(ADMIN_ROLE) {
        require(newFeeBps <= 1000, "Fee too high"); // Max 10%
        uint256 oldFeeBps = platformFeeBps;
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(oldFeeBps, newFeeBps);
    }

    /**
     * @notice Actualiza el fee collector
     * @param newCollector Nueva dirección
     */
    function setFeeCollector(address newCollector) external onlyRole(ADMIN_ROLE) {
        require(newCollector != address(0), "Invalid collector");
        address oldCollector = feeCollector;
        feeCollector = newCollector;
        emit FeeCollectorUpdated(oldCollector, newCollector);
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
     * @notice Retira tokens atrapados
     * @param token Dirección del token
     * @param to Dirección destino
     * @param amount Cantidad
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
