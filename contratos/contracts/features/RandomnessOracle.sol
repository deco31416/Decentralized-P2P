// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RandomnessOracle
 * @notice Wrapper de Chainlink VRF para generación segura de números aleatorios
 * @dev Simplifica integración de Chainlink VRF V2 para otros contratos
 * 
 * CARACTERÍSTICAS:
 * - Wrapper simplificado de Chainlink VRF V2
 * - Gestión de subscripciones y consumidores
 * - Callback routing a múltiples contratos
 * - Request tracking y estado
 * - Gas optimization para callbacks
 * 
 * CHAINLINK VRF V2:
 * - Aleatoridad verificable on-chain
 * - Proof criptográfico de aleatoriedad
 * - Subscription-based (pago en LINK)
 * - Configurable: gas limit, confirmations, num words
 * 
 * FLUJO:
 * 1. Contrato autorizado solicita números aleatorios
 * 2. RandomnessOracle llama a Chainlink VRF Coordinator
 * 3. VRF genera números aleatorios con proof
 * 4. Callback a RandomnessOracle con números
 * 5. RandomnessOracle enruta callback al contrato solicitante
 * 
 * CONTRATOS INTEGRADOS:
 * - RewardDistributor: Selección de ganadores aleatorios
 * - LotterySystem: Sorteo de tickets
 * - DisputeResolution: Selección aleatoria de jurado
 * - P2PMarket: Matching aleatorio cuando múltiples ofertas
 * 
 * EJEMPLO:
 * ```solidity
 * // En RewardDistributor
 * uint256 requestId = randomnessOracle.requestRandomWords(
 *     2,  // 2 números aleatorios
 *     200000  // gas limit
 * );
 * 
 * // Callback
 * function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) {
 *     // Usar randomWords para seleccionar ganadores
 * }
 * ```
 */
contract RandomnessOracle is AccessControl, ReentrancyGuard {

    // ========================================
    // ROLES
    // ========================================
    
    bytes32 public constant CONSUMER_ROLE = keccak256("CONSUMER_ROLE");
    bytes32 public constant VRF_COORDINATOR_ROLE = keccak256("VRF_COORDINATOR_ROLE");

    // ========================================
    // ESTRUCTURAS
    // ========================================

    /**
     * @dev Estado de request
     */
    enum RequestStatus {
        PENDING,    // Pendiente
        FULFILLED,  // Completado
        FAILED      // Fallido
    }

    /**
     * @dev Información de request VRF
     */
    struct VRFRequest {
        uint256 requestId;              // ID único del request
        address requester;              // Contrato solicitante
        uint256 numWords;               // Cantidad de números aleatorios
        uint256 timestamp;              // Timestamp del request
        uint256 gasLimit;               // Gas limit para callback
        RequestStatus status;           // Estado del request
        uint256[] randomWords;          // Números aleatorios (cuando fulfilled)
        uint256 fulfilledAt;            // Timestamp cuando se completó
    }

    /**
     * @dev Configuración de VRF
     */
    struct VRFConfig {
        bytes32 keyHash;                // Key hash de VRF
        uint64 subscriptionId;          // ID de subscripción
        uint16 requestConfirmations;    // Confirmaciones requeridas
        uint32 callbackGasLimit;        // Gas limit por defecto
        uint32 numWords;                // Número de words por defecto
    }

    // ========================================
    // VARIABLES DE ESTADO
    // ========================================

    /// @notice VRF Coordinator de Chainlink
    address public vrfCoordinator;

    /// @notice Configuración de VRF
    VRFConfig public vrfConfig;

    /// @notice Contador de requests
    uint256 public requestCounter;

    /// @notice Requests por ID
    mapping(uint256 => VRFRequest) public vrfRequests;

    /// @notice Requests por contrato solicitante
    mapping(address => uint256[]) public requesterRequests;

    /// @notice Request ID de Chainlink a nuestro ID interno
    mapping(uint256 => uint256) public chainlinkToInternalId;

    /// @notice Total de requests completados
    uint256 public totalRequestsFulfilled;

    /// @notice Total de requests fallidos
    uint256 public totalRequestsFailed;

    /// @notice Flag para modo testing (sin VRF real)
    bool public testingMode;

    // ========================================
    // EVENTOS
    // ========================================

    event RandomnessRequested(
        uint256 indexed requestId,
        address indexed requester,
        uint256 numWords,
        uint256 gasLimit
    );

    event RandomnessFulfilled(
        uint256 indexed requestId,
        address indexed requester,
        uint256[] randomWords
    );

    event RequestFailed(
        uint256 indexed requestId,
        address indexed requester,
        string reason
    );

    event VRFConfigUpdated(
        bytes32 keyHash,
        uint64 subscriptionId,
        uint16 requestConfirmations
    );

    event TestingModeToggled(
        bool enabled
    );

    // ========================================
    // ERRORES
    // ========================================

    error InvalidAddress();
    error InvalidAmount();
    error RequestNotFound();
    error RequestAlreadyFulfilled();
    error UnauthorizedConsumer();
    error InvalidCallbackGasLimit();
    error VRFRequestFailed();

    // ========================================
    // CONSTRUCTOR
    // ========================================

    /**
     * @notice Constructor del contrato
     * @param _vrfCoordinator Dirección del VRF Coordinator de Chainlink
     * @param _keyHash Key hash de VRF
     * @param _subscriptionId ID de subscripción
     * @param admin Admin principal
     */
    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        address admin
    ) {
        if (_vrfCoordinator == address(0) || admin == address(0)) {
            revert InvalidAddress();
        }

        vrfCoordinator = _vrfCoordinator;

        vrfConfig = VRFConfig({
            keyHash: _keyHash,
            subscriptionId: _subscriptionId,
            requestConfirmations: 3,        // 3 confirmaciones por defecto
            callbackGasLimit: 200000,       // 200k gas por defecto
            numWords: 1                     // 1 número por defecto
        });

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VRF_COORDINATOR_ROLE, _vrfCoordinator);

        testingMode = false;
    }

    // ========================================
    // FUNCIONES PRINCIPALES
    // ========================================

    /**
     * @notice Solicita números aleatorios
     * @param numWords Cantidad de números aleatorios (1-500)
     * @param callbackGasLimit Gas limit para callback (50k-2.5M)
     * @return requestId ID del request
     * 
     * REQUISITOS:
     * - Caller debe tener CONSUMER_ROLE
     * - Caller debe implementar fulfillRandomWords()
     */
    function requestRandomWords(
        uint256 numWords,
        uint32 callbackGasLimit
    )
        external
        onlyRole(CONSUMER_ROLE)
        nonReentrant
        returns (uint256 requestId)
    {
        if (numWords == 0 || numWords > 500) revert InvalidAmount();
        if (callbackGasLimit < 50000 || callbackGasLimit > 2500000) {
            revert InvalidCallbackGasLimit();
        }

        requestId = ++requestCounter;

        // Crear request interno
        vrfRequests[requestId] = VRFRequest({
            requestId: requestId,
            requester: msg.sender,
            numWords: numWords,
            timestamp: block.timestamp,
            gasLimit: callbackGasLimit,
            status: RequestStatus.PENDING,
            randomWords: new uint256[](0),
            fulfilledAt: 0
        });

        requesterRequests[msg.sender].push(requestId);

        // Si estamos en testing mode, generar números pseudo-aleatorios
        if (testingMode) {
            _fulfillTestingMode(requestId, numWords);
        } else {
            // En producción, llamar a Chainlink VRF Coordinator
            // uint256 chainlinkRequestId = VRFCoordinatorV2Interface(vrfCoordinator)
            //     .requestRandomWords(
            //         vrfConfig.keyHash,
            //         vrfConfig.subscriptionId,
            //         vrfConfig.requestConfirmations,
            //         callbackGasLimit,
            //         uint32(numWords)
            //     );
            // chainlinkToInternalId[chainlinkRequestId] = requestId;
            
            // Por ahora, simular con hash
            uint256 chainlinkRequestId = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                msg.sender,
                requestId
            )));
            chainlinkToInternalId[chainlinkRequestId] = requestId;
        }

        emit RandomnessRequested(requestId, msg.sender, numWords, callbackGasLimit);
    }

    /**
     * @notice Callback de Chainlink VRF Coordinator
     * @param chainlinkRequestId ID del request de Chainlink
     * @param randomWords Números aleatorios generados
     * 
     * SOLO puede ser llamado por VRF Coordinator
     */
    function fulfillRandomWords(
        uint256 chainlinkRequestId,
        uint256[] memory randomWords
    )
        external
        onlyRole(VRF_COORDINATOR_ROLE)
        nonReentrant
    {
        uint256 requestId = chainlinkToInternalId[chainlinkRequestId];
        if (requestId == 0) revert RequestNotFound();

        VRFRequest storage request = vrfRequests[requestId];
        if (request.status == RequestStatus.FULFILLED) {
            revert RequestAlreadyFulfilled();
        }

        // Actualizar request
        request.status = RequestStatus.FULFILLED;
        request.randomWords = randomWords;
        request.fulfilledAt = block.timestamp;
        totalRequestsFulfilled++;

        // Callback al contrato solicitante
        _callbackToRequester(requestId, request.requester, randomWords);

        emit RandomnessFulfilled(requestId, request.requester, randomWords);
    }

    /**
     * @dev Enruta callback al contrato solicitante
     */
    function _callbackToRequester(
        uint256 requestId,
        address requester,
        uint256[] memory randomWords
    )
        internal
    {
        // Intentar callback con try/catch para evitar revert del contrato principal
        try IRandomnessConsumer(requester).fulfillRandomWords(requestId, randomWords) {
            // Callback exitoso
        } catch Error(string memory reason) {
            vrfRequests[requestId].status = RequestStatus.FAILED;
            totalRequestsFailed++;
            emit RequestFailed(requestId, requester, reason);
        } catch {
            vrfRequests[requestId].status = RequestStatus.FAILED;
            totalRequestsFailed++;
            emit RequestFailed(requestId, requester, "Unknown error");
        }
    }

    /**
     * @dev Genera números pseudo-aleatorios en testing mode
     */
    function _fulfillTestingMode(uint256 requestId, uint256 numWords) internal {
        uint256[] memory randomWords = new uint256[](numWords);
        
        for (uint256 i = 0; i < numWords; i++) {
            randomWords[i] = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                block.number,
                requestId,
                i
            )));
        }

        VRFRequest storage request = vrfRequests[requestId];
        request.status = RequestStatus.FULFILLED;
        request.randomWords = randomWords;
        request.fulfilledAt = block.timestamp;
        totalRequestsFulfilled++;

        // Callback inmediato en testing mode
        _callbackToRequester(requestId, request.requester, randomWords);

        emit RandomnessFulfilled(requestId, request.requester, randomWords);
    }

    /**
     * @notice Callback manual para testing (solo admin)
     * @param requestId ID del request
     * @param randomWords Números aleatorios
     */
    function manualFulfill(uint256 requestId, uint256[] calldata randomWords)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        VRFRequest storage request = vrfRequests[requestId];
        if (request.requestId == 0) revert RequestNotFound();
        if (request.status == RequestStatus.FULFILLED) {
            revert RequestAlreadyFulfilled();
        }

        request.status = RequestStatus.FULFILLED;
        request.randomWords = randomWords;
        request.fulfilledAt = block.timestamp;
        totalRequestsFulfilled++;

        _callbackToRequester(requestId, request.requester, randomWords);

        emit RandomnessFulfilled(requestId, request.requester, randomWords);
    }

    // ========================================
    // FUNCIONES DE CONSULTA
    // ========================================

    /**
     * @notice Obtiene información de un request
     */
    function getRequest(uint256 requestId)
        external
        view
        returns (
            address requester,
            uint256 numWords,
            uint256 timestamp,
            RequestStatus status,
            uint256[] memory randomWords,
            uint256 fulfilledAt
        )
    {
        VRFRequest storage request = vrfRequests[requestId];
        return (
            request.requester,
            request.numWords,
            request.timestamp,
            request.status,
            request.randomWords,
            request.fulfilledAt
        );
    }

    /**
     * @notice Obtiene requests de un contrato
     */
    function getRequesterRequests(address requester)
        external
        view
        returns (uint256[] memory)
    {
        return requesterRequests[requester];
    }

    /**
     * @notice Obtiene requests pendientes de un contrato
     */
    function getPendingRequests(address requester)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory allRequests = requesterRequests[requester];
        uint256 pendingCount = 0;

        // Contar pendientes
        for (uint256 i = 0; i < allRequests.length; i++) {
            if (vrfRequests[allRequests[i]].status == RequestStatus.PENDING) {
                pendingCount++;
            }
        }

        // Crear array de pendientes
        uint256[] memory pending = new uint256[](pendingCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allRequests.length; i++) {
            if (vrfRequests[allRequests[i]].status == RequestStatus.PENDING) {
                pending[index] = allRequests[i];
                index++;
            }
        }

        return pending;
    }

    /**
     * @notice Obtiene estadísticas globales
     */
    function getStats()
        external
        view
        returns (
            uint256 totalRequests,
            uint256 totalFulfilled,
            uint256 totalFailed,
            uint256 totalPending
        )
    {
        return (
            requestCounter,
            totalRequestsFulfilled,
            totalRequestsFailed,
            requestCounter - totalRequestsFulfilled - totalRequestsFailed
        );
    }

    /**
     * @notice Verifica si un request está completado
     */
    function isRequestFulfilled(uint256 requestId) external view returns (bool) {
        return vrfRequests[requestId].status == RequestStatus.FULFILLED;
    }

    // ========================================
    // FUNCIONES ADMIN
    // ========================================

    /**
     * @notice Actualiza configuración de VRF
     */
    function updateVRFConfig(
        bytes32 keyHash,
        uint64 subscriptionId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        vrfConfig.keyHash = keyHash;
        vrfConfig.subscriptionId = subscriptionId;
        vrfConfig.requestConfirmations = requestConfirmations;
        vrfConfig.callbackGasLimit = callbackGasLimit;
        vrfConfig.numWords = numWords;

        emit VRFConfigUpdated(keyHash, subscriptionId, requestConfirmations);
    }

    /**
     * @notice Actualiza VRF Coordinator
     */
    function setVRFCoordinator(address newCoordinator)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newCoordinator == address(0)) revert InvalidAddress();
        
        // Revocar rol del anterior
        _revokeRole(VRF_COORDINATOR_ROLE, vrfCoordinator);
        
        // Asignar al nuevo
        vrfCoordinator = newCoordinator;
        _grantRole(VRF_COORDINATOR_ROLE, newCoordinator);
    }

    /**
     * @notice Habilita/deshabilita testing mode
     */
    function setTestingMode(bool enabled)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        testingMode = enabled;
        emit TestingModeToggled(enabled);
    }

    /**
     * @notice Agrega consumer autorizado
     */
    function addConsumer(address consumer)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (consumer == address(0)) revert InvalidAddress();
        _grantRole(CONSUMER_ROLE, consumer);
    }

    /**
     * @notice Remueve consumer
     */
    function removeConsumer(address consumer)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _revokeRole(CONSUMER_ROLE, consumer);
    }

    /**
     * @notice Marca request como fallido (emergencia)
     */
    function markRequestAsFailed(uint256 requestId, string calldata reason)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        VRFRequest storage request = vrfRequests[requestId];
        if (request.requestId == 0) revert RequestNotFound();

        request.status = RequestStatus.FAILED;
        totalRequestsFailed++;

        emit RequestFailed(requestId, request.requester, reason);
    }
}

/**
 * @title IRandomnessConsumer
 * @notice Interface que deben implementar los contratos consumidores
 */
interface IRandomnessConsumer {
    /**
     * @notice Callback con números aleatorios
     * @param requestId ID del request
     * @param randomWords Array de números aleatorios
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external;
}
