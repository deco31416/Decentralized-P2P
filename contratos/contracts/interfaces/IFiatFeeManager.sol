// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFiatFeeManager
 * @notice Interface para gestión de comisiones fiat con topes por moneda
 * @dev Admin setea topes máximos, intermediarios configuran sus %
 */
interface IFiatFeeManager {
    
    // ============================================
    // EVENTOS
    // ============================================
    
    event MaxFiatFeeSet(
        string fiatCurrency,
        uint256 maxPercent
    );
    
    event IntermediaryFeeSet(
        address indexed intermediary,
        string fiatCurrency,
        uint256 feePercent
    );
    
    event IntermediaryApproved(
        address indexed intermediary,
        bool approved
    );
    
    // ============================================
    // FUNCIONES ADMIN
    // ============================================
    
    /**
     * @notice Admin setea TOPE MÁXIMO de comisión por moneda fiat
     * @param fiatCurrency Código de moneda ("USD", "EUR", "COP", etc.)
     * @param maxPercent Porcentaje máximo (7 = 7%)
     */
    function setMaxFiatFee(string memory fiatCurrency, uint256 maxPercent) external;
    
    /**
     * @notice Admin aprueba/desaprueba intermediario (KYC)
     * @param intermediary Dirección del intermediario
     * @param approved true para aprobar, false para desaprobar
     */
    function approveIntermediary(address intermediary, bool approved) external;
    
    // ============================================
    // FUNCIONES INTERMEDIARIO
    // ============================================
    
    /**
     * @notice Intermediario configura SU comisión (dentro del tope)
     * @param fiatCurrency Código de moneda
     * @param feePercent Su porcentaje (debe ser <= tope admin)
     */
    function setIntermediaryFee(string memory fiatCurrency, uint256 feePercent) external;
    
    // ============================================
    // VISTAS
    // ============================================
    
    /**
     * @notice Obtener tope máximo para una moneda
     */
    function getMaxFiatFee(string memory fiatCurrency) external view returns (uint256);
    
    /**
     * @notice Obtener comisión de un intermediario para una moneda
     */
    function getIntermediaryFee(address intermediary, string memory fiatCurrency) 
        external view returns (uint256);
    
    /**
     * @notice Verificar si intermediario está aprobado
     */
    function isApprovedIntermediary(address intermediary) external view returns (bool);
    
    /**
     * @notice Calcular comisiones totales para una orden
     * @param intermediary Dirección del intermediario
     * @param fiatFrom Moneda de entrada
     * @param fiatTo Moneda de salida
     * @param amountFrom Monto entrada
     * @return entryFeePercent Porcentaje comisión entrada
     * @return exitFeePercent Porcentaje comisión salida
     * @return entryFeeAmount Monto comisión entrada
     * @return exitFeeAmount Monto comisión salida
     * @return totalFeeUSDT Total en USDT
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
    );
}
