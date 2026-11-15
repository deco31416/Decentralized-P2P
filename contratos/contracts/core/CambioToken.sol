// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title CambioToken
 * @notice ERC20 utility token for CambiaCripto P2P protocol
 * @dev Simple token with:
 *      - Fixed supply (1B tokens)
 *      - No minting after deployment
 *      - No taxes, no blacklist
 *      - Used for fee discounts via staking
 * 
 * Security:
 *      - Ownable2Step for safe ownership transfer
 *      - Standard ERC20 (no custom transfer logic)
 *      - Auditable and transparent
 * 
 * @custom:security-contact security@cambiacripto.com
 */
contract CambioToken is ERC20, Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Total supply: 1 billion tokens (1e9 * 1e18)
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deploy token and mint entire supply to deployer
     * @param initialOwner Address to receive all tokens and ownership
     */
    constructor(address initialOwner) ERC20("Cambio", "CAMBIO") Ownable(initialOwner) {
        require(initialOwner != address(0), "CambioToken: zero address");
        
        // Mint entire supply to initial owner
        _mint(initialOwner, TOTAL_SUPPLY);
    }
    
    /*//////////////////////////////////////////////////////////////
                        NO ADDITIONAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev This token is intentionally simple:
     *      - Standard transfer/approve/transferFrom (ERC20)
     *      - No minting (fixed supply)
     *      - No burning (preserve total supply)
     *      - No fees on transfer
     *      - No blacklist/whitelist
     * 
     * All functionality is standard OpenZeppelin ERC20.
     */
}
