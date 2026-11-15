// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockWBNB
 * @notice Mock de Wrapped BNB para testing
 * @dev Simula WBNB - Wrap/Unwrap de BNB
 */
contract MockWBNB is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() ERC20("Wrapped BNB", "WBNB") {}

    /**
     * @notice Depositar BNB y recibir WBNB
     */
    receive() external payable {
        deposit();
    }

    /**
     * @notice Wrap BNB -> WBNB
     */
    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Unwrap WBNB -> BNB
     * @param wad Cantidad de WBNB a unwrap
     */
    function withdraw(uint256 wad) public {
        require(balanceOf(msg.sender) >= wad, "Insufficient balance");
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    /**
     * @notice Faucet para testing (solo testnet)
     * @dev Permite obtener WBNB gratis sin depositar BNB
     */
    function faucet(uint256 amount) external {
        require(amount <= 100 ether, "Max 100 WBNB per faucet");
        _mint(msg.sender, amount);
    }
}
