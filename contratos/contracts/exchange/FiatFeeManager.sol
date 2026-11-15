// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IFiatFeeManager.sol";

/**
 * @title FiatFeeManager
 * @notice Gestor de comisiones para órdenes fiat-to-fiat
 * @dev Admin setea topes máximos, intermediarios configuran sus porcentajes
 * 
 * Flujo:
 * 1. Admin: setMaxFiatFee("USD", 7) → 7% máximo para USD
 * 2. Admin: approveIntermediary(address, true) → Aprobar intermediario (KYC)
 * 3. Intermediario: setIntermediaryFee("USD", 5) → 5% (< 7% tope) ✅
 * 4. Sistema calcula: entrada 5% + salida 8% = comisión total
 */
contract FiatFeeManager is AccessControl, ReentrancyGuard, IFiatFeeManager {
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // ============================================
    // VARIABLES DE ESTADO
    // ============================================
    
    /// @notice TOPES MÁXIMOS de comisión por moneda fiat (seteable por admin)
    /// @dev Ejemplo: maxFiatFeePercentage["USD"] = 7 → 7% máximo
    mapping(string => uint256) public maxFiatFeePercentage;
    
    /// @notice Comisiones personalizadas de cada intermediario por moneda
    /// @dev intermediaryFiatFee[intermediary]["USD"] = 5 → 5% (< 7% tope)
    mapping(address => mapping(string => uint256)) public intermediaryFiatFee;
    
    /// @notice Intermediarios aprobados (KYC/whitelist)
    mapping(address => bool) public approvedIntermediaries;
    
    /// @notice Porcentaje máximo permitido (20%)
    uint256 public constant MAX_FEE_PERCENTAGE = 20;
    
    /// @notice Porcentaje mínimo permitido (0.1%)
    uint256 public constant MIN_FEE_PERCENTAGE = 1; // 0.1% = 1 (en base 1000)
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor(address _admin) {
        require(_admin != address(0), "Invalid admin");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        
        // Configurar topes por defecto
        maxFiatFeePercentage["USD"] = 7;  // 7%
        maxFiatFeePercentage["EUR"] = 5;  // 5%
        maxFiatFeePercentage["COP"] = 10; // 10%
        maxFiatFeePercentage["MXN"] = 8;  // 8%
        maxFiatFeePercentage["BRL"] = 8;  // 8%
        maxFiatFeePercentage["ARS"] = 12; // 12%
    }
    
    // ============================================
    // FUNCIONES ADMIN
    // ============================================
    
    /**
     * @notice Admin setea TOPE MÁXIMO de comisión por moneda fiat
     * @param fiatCurrency Código de moneda ("USD", "EUR", "COP", etc.)
     * @param maxPercent Porcentaje máximo (7 = 7%)
     */
    function setMaxFiatFee(string memory fiatCurrency, uint256 maxPercent)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(bytes(fiatCurrency).length > 0, "Empty currency");
        require(maxPercent > 0 && maxPercent <= MAX_FEE_PERCENTAGE, "Invalid percentage");
        
        maxFiatFeePercentage[fiatCurrency] = maxPercent;
        
        emit MaxFiatFeeSet(fiatCurrency, maxPercent);
    }
    
    /**
     * @notice Admin aprueba/desaprueba intermediario (KYC)
     * @param intermediary Dirección del intermediario
     * @param approved true para aprobar, false para desaprobar
     */
    function approveIntermediary(address intermediary, bool approved)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(intermediary != address(0), "Invalid intermediary");
        
        approvedIntermediaries[intermediary] = approved;
        
        emit IntermediaryApproved(intermediary, approved);
    }
    
    // ============================================
    // FUNCIONES INTERMEDIARIO
    // ============================================
    
    /**
     * @notice Intermediario configura SU comisión (dentro del tope)
     * @param fiatCurrency Código de moneda
     * @param feePercent Su porcentaje (debe ser <= tope admin)
     */
    function setIntermediaryFee(string memory fiatCurrency, uint256 feePercent)
        external
    {
        require(approvedIntermediaries[msg.sender], "Not approved intermediary");
        
        uint256 maxFee = maxFiatFeePercentage[fiatCurrency];
        require(maxFee > 0, "Fiat currency not supported");
        require(feePercent > 0 && feePercent <= maxFee, "Fee exceeds max or is zero");
        
        intermediaryFiatFee[msg.sender][fiatCurrency] = feePercent;
        
        emit IntermediaryFeeSet(msg.sender, fiatCurrency, feePercent);
    }
    
    // ============================================
    // VISTAS
    // ============================================
    
    /**
     * @notice Obtener tope máximo para una moneda
     */
    function getMaxFiatFee(string memory fiatCurrency) 
        external 
        view 
        returns (uint256) 
    {
        return maxFiatFeePercentage[fiatCurrency];
    }
    
    /**
     * @notice Obtener comisión de un intermediario para una moneda
     */
    function getIntermediaryFee(address intermediary, string memory fiatCurrency)
        external
        view
        returns (uint256)
    {
        return intermediaryFiatFee[intermediary][fiatCurrency];
    }
    
    /**
     * @notice Verificar si intermediario está aprobado
     */
    function isApprovedIntermediary(address intermediary) 
        external 
        view 
        returns (bool) 
    {
        return approvedIntermediaries[intermediary];
    }
    
    /**
     * @notice Calcular comisiones totales para una orden
     * @param intermediary Dirección del intermediario
     * @param fiatFrom Moneda de entrada (USD)
     * @param fiatTo Moneda de salida (COP)
     * @param amountFrom Monto entrada (1000 USD)
     * @return entryFeePercent Porcentaje comisión entrada (5%)
     * @return exitFeePercent Porcentaje comisión salida (8%)
     * @return entryFeeAmount Monto comisión entrada ($50)
     * @return exitFeeAmount Monto comisión salida ($76)
     * @return totalFeeUSDT Total en USDT ($126)
     */
    function calculateFees(
        address intermediary,
        string memory fiatFrom,
        string memory fiatTo,
        uint256 amountFrom
    ) external view returns (
        uint256 entryFeePercent,
        uint256 exitFeePercent,
        uint256 entryFeeAmount,
        uint256 exitFeeAmount,
        uint256 totalFeeUSDT
    ) {
        require(approvedIntermediaries[intermediary], "Not approved");
        
        entryFeePercent = intermediaryFiatFee[intermediary][fiatFrom];
        exitFeePercent = intermediaryFiatFee[intermediary][fiatTo];
        
        require(entryFeePercent > 0, "Entry fee not set");
        require(exitFeePercent > 0, "Exit fee not set");
        
        // Calcular comisión entrada: USD → USDT
        entryFeeAmount = (amountFrom * entryFeePercent) / 100;
        
        // Monto después de comisión entrada
        uint256 usdtAfterEntry = amountFrom - entryFeeAmount;
        
        // Calcular comisión salida: USDT → COP
        exitFeeAmount = (usdtAfterEntry * exitFeePercent) / 100;
        
        // Total comisiones en USDT
        totalFeeUSDT = entryFeeAmount + exitFeeAmount;
    }
    
    // ============================================
    // FUNCIONES ADMIN ADICIONALES
    // ============================================
    
    /**
     * @notice Batch aprobar múltiples intermediarios
     */
    function batchApproveIntermediaries(
        address[] calldata intermediaries,
        bool approved
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < intermediaries.length; i++) {
            require(intermediaries[i] != address(0), "Invalid intermediary");
            approvedIntermediaries[intermediaries[i]] = approved;
            emit IntermediaryApproved(intermediaries[i], approved);
        }
    }
    
    /**
     * @notice Batch setear topes para múltiples monedas
     */
    function batchSetMaxFiatFees(
        string[] calldata currencies,
        uint256[] calldata maxPercents
    ) external onlyRole(ADMIN_ROLE) {
        require(currencies.length == maxPercents.length, "Length mismatch");
        
        for (uint256 i = 0; i < currencies.length; i++) {
            require(bytes(currencies[i]).length > 0, "Empty currency");
            require(maxPercents[i] > 0 && maxPercents[i] <= MAX_FEE_PERCENTAGE, "Invalid percentage");
            
            maxFiatFeePercentage[currencies[i]] = maxPercents[i];
            emit MaxFiatFeeSet(currencies[i], maxPercents[i]);
        }
    }
}
