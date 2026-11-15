// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBalanceManager
 * @notice Interface para el BalanceManager
 */
interface IBalanceManager {
    /**
     * @notice Información de balance de usuario por token
     */
    struct Balance {
        uint256 available;      // Balance disponible
        uint256 locked;         // Balance bloqueado en trades/escrow
        uint256 totalDeposited; // Total histórico depositado
        uint256 totalWithdrawn; // Total histórico retirado
    }

    /**
     * @notice Obtiene el balance de un usuario para un token
     * @param user Dirección del usuario
     * @param token Dirección del token
     * @return available Balance disponible
     * @return locked Balance bloqueado
     * @return totalDeposited Total depositado
     * @return totalWithdrawn Total retirado
     */
    function balances(address user, address token) external view returns (
        uint256 available,
        uint256 locked,
        uint256 totalDeposited,
        uint256 totalWithdrawn
    );

    /**
     * @notice Deposita tokens al balance del usuario
     * @param token Dirección del token
     * @param amount Cantidad a depositar
     */
    function deposit(address token, uint256 amount) external;

    /**
     * @notice Retira tokens del balance del usuario
     * @param token Dirección del token
     * @param amount Cantidad a retirar
     */
    function withdraw(address token, uint256 amount) external;

    /**
     * @notice Bloquea balance para un trade
     * @param user Usuario cuyo balance se bloqueará
     * @param token Token a bloquear
     * @param amount Cantidad a bloquear
     */
    function lockBalance(address user, address token, uint256 amount) external;

    /**
     * @notice Libera balance bloqueado
     * @param user Usuario cuyo balance se liberará
     * @param token Token a liberar
     * @param amount Cantidad a liberar
     */
    function unlockBalance(address user, address token, uint256 amount) external;

    /**
     * @notice Transfiere balance entre usuarios
     * @param from Usuario origen
     * @param to Usuario destino
     * @param token Token a transferir
     * @param amount Cantidad a transferir
     */
    function transferBalance(
        address from,
        address to,
        address token,
        uint256 amount
    ) external;

    /**
     * @notice Verifica si un token está soportado
     * @param token Dirección del token
     * @return true si el token está soportado
     */
    function supportedTokens(address token) external view returns (bool);

    /**
     * @notice Obtiene el límite de retiro diario
     * @param user Usuario
     * @param token Token
     * @return Límite diario
     */
    function dailyWithdrawLimit(address user, address token) external view returns (uint256);
}
