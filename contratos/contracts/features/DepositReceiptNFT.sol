// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title DepositReceiptNFT
 * @notice NFT ERC721 como recibo de depósito con metadata on-chain
 * @dev NFT no transferible que representa un depósito en el sistema
 * 
 * Características principales:
 * - NFT como comprobante de depósito
 * - Metadata completamente on-chain (SVG generado dinámicamente)
 * - No transferible (soulbound) excepto por admin
 * - Burneable cuando se retira el depósito
 * - Enumerable para listar todos los NFTs de un usuario
 * - URI storage para metadata personalizada
 * - Información visual del depósito (token, cantidad, fecha)
 * - Colores dinámicos según el token
 * - QR code visual (simulado)
 * 
 * Metadata incluye:
 * - Token depositado
 * - Cantidad depositada
 * - Valor en USD
 * - Fecha de depósito
 * - ID del depósito
 * - Estado del depósito
 * - Imagen SVG generada dinámicamente
 * 
 * Uso:
 * 1. DepositManager mintea NFT al usuario al depositar
 * 2. Usuario puede consultar su NFT para ver detalles
 * 3. NFT se quema cuando se retira el depósito
 * 4. Admin puede transferir en casos especiales
 * 
 * Seguridad:
 * - Solo DepositManager puede mintear
 * - Solo DepositManager puede quemar
 * - Transferencias bloqueadas (soulbound)
 * - Metadata inmutable una vez minteado
 */
contract DepositReceiptNFT is 
    ERC721, 
    ERC721URIStorage, 
    ERC721Enumerable, 
    AccessControl, 
    Pausable 
{
    using Strings for uint256;

    /// @notice Rol de administrador
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de minter (DepositManager)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /// @notice Rol de burner (DepositManager)
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    /// @notice Rol de pausador
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Información del depósito asociado al NFT
    struct DepositInfo {
        uint256 depositId;
        address depositor;
        address token;
        string tokenSymbol;
        uint256 amount;
        uint256 valueUSD;
        uint256 depositedAt;
        bool active;
    }

    /// @notice Mapeo de tokenId a información del depósito
    mapping(uint256 => DepositInfo) public depositInfo;
    
    /// @notice Contador de tokens
    uint256 private _tokenIdCounter;
    
    /// @notice NFTs transferibles (false por defecto = soulbound)
    bool public transfersEnabled;
    
    /// @notice Base URI para metadata externa (opcional)
    string private _baseTokenURI;

    /// @notice Referencia al DepositManager
    address public depositManager;

    /// @notice Colores por símbolo de token
    mapping(string => string) public tokenColors;

    // ============================================
    // EVENTOS
    // ============================================

    event ReceiptMinted(
        uint256 indexed tokenId,
        address indexed depositor,
        uint256 indexed depositId,
        address token,
        uint256 amount
    );

    event ReceiptBurned(
        uint256 indexed tokenId,
        uint256 indexed depositId
    );

    event TransfersEnabledChanged(
        bool enabled
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _admin,
        address _depositManager
    ) ERC721("CambiaCripto Deposit Receipt", "CCDR") {
        require(_admin != address(0), "Invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        if (_depositManager != address(0)) {
            depositManager = _depositManager;
            _grantRole(MINTER_ROLE, _depositManager);
            _grantRole(BURNER_ROLE, _depositManager);
        }

        transfersEnabled = false;

        // Configurar colores por defecto
        tokenColors["BTC"] = "#F7931A";
        tokenColors["ETH"] = "#627EEA";
        tokenColors["USDT"] = "#26A17B";
        tokenColors["USDC"] = "#2775CA";
        tokenColors["DAI"] = "#F5AC37";
        tokenColors["CAMBIO"] = "#6366F1";
    }

    // ============================================
    // MINTING
    // ============================================

    /**
     * @notice Mintea un NFT recibo de depósito
     * @param to Dirección del depositante
     * @param depositId ID del depósito
     * @param token Token depositado
     * @param tokenSymbol Símbolo del token
     * @param amount Cantidad depositada
     * @param valueUSD Valor en USD
     */
    function mint(
        address to,
        uint256 depositId,
        address token,
        string memory tokenSymbol,
        uint256 amount,
        uint256 valueUSD
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        require(to != address(0), "Invalid recipient");
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");

        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        // Guardar información del depósito
        DepositInfo storage info = depositInfo[tokenId];
        info.depositId = depositId;
        info.depositor = to;
        info.token = token;
        info.tokenSymbol = tokenSymbol;
        info.amount = amount;
        info.valueUSD = valueUSD;
        info.depositedAt = block.timestamp;
        info.active = true;

        // Mintear NFT
        _safeMint(to, tokenId);

        // Generar y setear URI
        string memory uri = _generateTokenURI(tokenId);
        _setTokenURI(tokenId, uri);

        emit ReceiptMinted(tokenId, to, depositId, token, amount);

        return tokenId;
    }

    /**
     * @notice Quema un NFT recibo
     * @param tokenId ID del token a quemar
     */
    function burn(uint256 tokenId) external onlyRole(BURNER_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        DepositInfo storage info = depositInfo[tokenId];
        info.active = false;

        emit ReceiptBurned(tokenId, info.depositId);

        _burn(tokenId);
    }

    // ============================================
    // METADATA ON-CHAIN
    // ============================================

    /**
     * @notice Genera URI del token completamente on-chain
     */
    function _generateTokenURI(uint256 tokenId) internal view returns (string memory) {
        DepositInfo memory info = depositInfo[tokenId];
        
        string memory svg = _generateSVG(tokenId);
        string memory attributes = _generateAttributes(info);
        
        string memory json = string(abi.encodePacked(
            '{"name": "Deposit Receipt #',
            tokenId.toString(),
            '",',
            '"description": "CambiaCripto Deposit Receipt - Proof of ',
            _formatAmount(info.amount),
            ' ',
            info.tokenSymbol,
            ' deposited",',
            '"image": "data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '",',
            '"attributes": ',
            attributes,
            '}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    /**
     * @notice Genera SVG del NFT
     */
    function _generateSVG(uint256 tokenId) internal view returns (string memory) {
        DepositInfo memory info = depositInfo[tokenId];
        string memory color = _getTokenColor(info.tokenSymbol);
        
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%)">',
            '<defs>',
            '<linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">',
            '<stop offset="0%" style="stop-color:', color, ';stop-opacity:0.8" />',
            '<stop offset="100%" style="stop-color:', color, ';stop-opacity:0.4" />',
            '</linearGradient>',
            '</defs>',
            '<rect width="400" height="600" fill="url(#grad)" opacity="0.1"/>',
            '<rect x="20" y="20" width="360" height="560" rx="20" fill="white" fill-opacity="0.95"/>',
            '<text x="200" y="70" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="#1f2937" text-anchor="middle">DEPOSIT RECEIPT</text>',
            '<text x="200" y="100" font-family="monospace" font-size="14" fill="#6b7280" text-anchor="middle">#',
            tokenId.toString(),
            '</text>',
            '<circle cx="200" cy="180" r="60" fill="', color, '" opacity="0.2"/>',
            '<text x="200" y="195" font-family="Arial, sans-serif" font-size="32" font-weight="bold" fill="', color, '" text-anchor="middle">',
            info.tokenSymbol,
            '</text>',
            '<line x1="60" y1="260" x2="340" y2="260" stroke="#e5e7eb" stroke-width="2"/>',
            '<text x="60" y="300" font-family="Arial, sans-serif" font-size="14" fill="#6b7280">Amount:</text>',
            '<text x="340" y="300" font-family="monospace" font-size="16" font-weight="bold" fill="#1f2937" text-anchor="end">',
            _formatAmount(info.amount),
            '</text>',
            '<text x="60" y="340" font-family="Arial, sans-serif" font-size="14" fill="#6b7280">Value USD:</text>',
            '<text x="340" y="340" font-family="monospace" font-size="16" font-weight="bold" fill="#1f2937" text-anchor="end">$',
            _formatUSD(info.valueUSD),
            '</text>',
            '<text x="60" y="380" font-family="Arial, sans-serif" font-size="14" fill="#6b7280">Date:</text>',
            '<text x="340" y="380" font-family="monospace" font-size="14" fill="#1f2937" text-anchor="end">',
            _formatDate(info.depositedAt),
            '</text>',
            '<line x1="60" y1="400" x2="340" y2="400" stroke="#e5e7eb" stroke-width="2"/>',
            '<rect x="150" y="430" width="100" height="100" fill="white" stroke="', color, '" stroke-width="2"/>',
            '<text x="200" y="485" font-family="monospace" font-size="10" fill="', color, '" text-anchor="middle">QR CODE</text>',
            '<text x="200" y="560" font-family="Arial, sans-serif" font-size="12" fill="#9ca3af" text-anchor="middle">CambiaCripto.com</text>',
            '</svg>'
        ));
    }

    /**
     * @notice Genera atributos JSON
     */
    function _generateAttributes(DepositInfo memory info) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '[',
            '{"trait_type": "Token", "value": "', info.tokenSymbol, '"},',
            '{"trait_type": "Amount", "value": "', _formatAmount(info.amount), '"},',
            '{"trait_type": "Value USD", "display_type": "number", "value": ', _formatUSD(info.valueUSD), '},',
            '{"trait_type": "Deposit ID", "display_type": "number", "value": ', info.depositId.toString(), '},',
            '{"trait_type": "Status", "value": "', info.active ? 'Active' : 'Inactive', '"},',
            '{"trait_type": "Deposit Date", "display_type": "date", "value": ', info.depositedAt.toString(), '}',
            ']'
        ));
    }

    // ============================================
    // HELPERS
    // ============================================

    /**
     * @notice Obtiene color del token
     */
    function _getTokenColor(string memory symbol) internal view returns (string memory) {
        string memory color = tokenColors[symbol];
        if (bytes(color).length == 0) {
            return "#6366F1"; // Color por defecto
        }
        return color;
    }

    /**
     * @notice Formatea cantidad
     */
    function _formatAmount(uint256 amount) internal pure returns (string memory) {
        // Simplificado: mostrar primeros 6 dígitos
        uint256 displayAmount = amount / 1e12; // Dividir por 1e12 para mostrar con 6 decimales
        return displayAmount.toString();
    }

    /**
     * @notice Formatea valor USD
     */
    function _formatUSD(uint256 valueUSD) internal pure returns (string memory) {
        uint256 dollars = valueUSD / 1e18;
        return dollars.toString();
    }

    /**
     * @notice Formatea fecha
     */
    function _formatDate(uint256 timestamp) internal pure returns (string memory) {
        // Simplificado: mostrar timestamp
        return timestamp.toString();
    }

    // ============================================
    // TRANSFERENCIAS (SOULBOUND)
    // ============================================

    /**
     * @notice Override para bloquear transferencias
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override(ERC721, ERC721Enumerable) returns (address) {
        address from = _ownerOf(tokenId);
        
        // Permitir mint y burn
        if (from == address(0) || to == address(0)) {
            return super._update(to, tokenId, auth);
        }
        
        // Bloquear transferencias si no están habilitadas
        require(transfersEnabled || hasRole(ADMIN_ROLE, msg.sender), "Transfers disabled");
        
        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Habilita/deshabilita transferencias
     */
    function setTransfersEnabled(bool enabled) external onlyRole(ADMIN_ROLE) {
        transfersEnabled = enabled;
        emit TransfersEnabledChanged(enabled);
    }

    // ============================================
    // CONFIGURACIÓN
    // ============================================

    /**
     * @notice Configura color de token
     */
    function setTokenColor(string memory symbol, string memory color) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        tokenColors[symbol] = color;
    }

    /**
     * @notice Configura DepositManager
     */
    function setDepositManager(address _depositManager) external onlyRole(ADMIN_ROLE) {
        require(_depositManager != address(0), "Invalid address");
        
        if (depositManager != address(0)) {
            _revokeRole(MINTER_ROLE, depositManager);
            _revokeRole(BURNER_ROLE, depositManager);
        }
        
        depositManager = _depositManager;
        _grantRole(MINTER_ROLE, _depositManager);
        _grantRole(BURNER_ROLE, _depositManager);
    }

    /**
     * @notice Configura base URI
     */
    function setBaseURI(string memory baseURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = baseURI;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============================================
    // OVERRIDES REQUERIDOS
    // ============================================

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ============================================
    // VISTAS
    // ============================================

    /**
     * @notice Obtiene información del depósito asociado al NFT
     */
    function getDepositInfo(uint256 tokenId) external view returns (DepositInfo memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return depositInfo[tokenId];
    }

    /**
     * @notice Obtiene todos los NFTs de un usuario
     */
    function getUserReceipts(address user) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(user);
        uint256[] memory receipts = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            receipts[i] = tokenOfOwnerByIndex(user, i);
        }
        
        return receipts;
    }

    /**
     * @notice Obtiene información de múltiples NFTs
     */
    function getBatchDepositInfo(uint256[] memory tokenIds) 
        external 
        view 
        returns (DepositInfo[] memory) 
    {
        DepositInfo[] memory infos = new DepositInfo[](tokenIds.length);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (_ownerOf(tokenIds[i]) != address(0)) {
                infos[i] = depositInfo[tokenIds[i]];
            }
        }
        
        return infos;
    }

    /**
     * @notice Total de NFTs minteados
     */
    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @notice Verifica si un NFT está activo
     */
    function isActive(uint256 tokenId) external view returns (bool) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return depositInfo[tokenId].active;
    }
}
