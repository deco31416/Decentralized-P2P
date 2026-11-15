// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice Token ERC20 para testing - Simula USDT, BUSD, etc.
 * @dev Permite mint ilimitado para testing, decimales configurables
 */
contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = decimals_;
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    /**
     * @notice Retorna los decimales del token
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens (solo owner)
     * @param to Dirección destino
     * @param amount Cantidad a mintear
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens propios
     * @param amount Cantidad a quemar
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Mint masivo para testing (solo owner)
     * @param recipients Array de direcciones
     * @param amounts Array de cantidades
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(recipients.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /**
     * @notice Mint automático para cualquiera (testnet faucet)
     * @dev Solo usar en testnet! Permite a cualquiera obtener tokens
     */
    function faucet(uint256 amount) external {
        require(amount <= 1000000 * 10 ** _decimals, "Max 1M per faucet");
        _mint(msg.sender, amount);
    }
}
