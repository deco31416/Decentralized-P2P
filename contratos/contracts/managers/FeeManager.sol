// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FeeManager
 * @author deoc31416
 * @notice Gestión centralizada de fees del protocolo
 * @dev Maneja colección, cálculo y distribución automática de fees
 * 
 * Características:
 * - Fees diferenciados por tipo de operación
 * - Distribución automática a múltiples destinos
 * - Tracking de fees generados
 * - Sistema de descuentos por volumen
 */
contract FeeManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== ROLES ==========
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ========== CONSTANTS (V2 INTEGRATION) ==========
    
    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS = 10_000;
    
    /// @notice ABSOLUTE MINIMUM FEE (0.1%) - NEVER ZERO
    /// @dev CRITICAL: No user ever trades for free
    uint256 public constant ABSOLUTE_MIN_BPS = 10; // 0.1%

    // ========== ENUMS (V2 INTEGRATION) ==========
    
    enum TradeType { CryptoCrypto, FiatCrypto, CryptoFiat, FiatFiat }
    enum Tier { None, Tier1, Tier2, Tier3, Tier4 }

    // ========== STRUCTS ==========
    
    /// @notice Estructura de fees (en basis points, 10000 = 100%)
    struct FeeStructure {
        uint256 p2pTradeFee;        // Fee en trades P2P crypto-crypto
        uint256 fiatBridgeFee;      // Fee en intercambios crypto-fiat
        uint256 intermediaryFee;    // Fee para intermediarios
        uint256 stakingEarlyFee;    // Fee por unstake anticipado
        uint256 idoCreationFee;     // Fee por crear IDO
        uint256 disputeFee;         // Fee/stake para abrir disputa
        uint256 withdrawFee;        // Fee de retiro
    }

    /// @notice Estructura de distribución de fees (en porcentaje)
    struct FeeDistribution {
        uint256 treasuryPercent;    // % al treasury (rewards/lotería)
        uint256 stakingPercent;     // % a staking rewards
        uint256 burnPercent;        // % a burn (deflacionario)
        uint256 teamPercent;        // % al team
    }

    /// @notice Tier de descuento por volumen
    struct VolumeTier {
        uint256 minVolume;          // Volumen mínimo para tier
        uint256 discountBps;        // Descuento en basis points
    }

    /// @notice V2 Fee Configuration per trade type
    struct FeeConfig {
        uint256 baseBps;       // Base fee in basis points
        uint256 vipBps;        // VIP (Tier 4) fee in basis points
        uint256 minUsd;        // Minimum fee in USD (6 decimals)
    }
    
    /// @notice V2 Tier discount configuration
    struct TierDiscount {
        uint256 discountBps;   // Discount percentage (10000 = 100%)
        uint256 monthlyCapUsd; // Max discount per month (6 decimals)
    }

    // ========== STATE VARIABLES ==========
    
    /// @notice Estructura de fees actual
    FeeStructure public fees;

    /// @notice Distribución de fees
    FeeDistribution public distribution;

    /// @notice Dirección del treasury
    address public treasury;

    /// @notice Dirección del staking contract
    address public stakingContract;

    /// @notice Dirección del team wallet
    address public teamWallet;

    /// @notice Token principal del ecosistema (CAMBIO)
    address public cambioToken;

    /// @notice Fees acumulados por token: token => amount
    mapping(address => uint256) public accumulatedFees;

    /// @notice Fees distribuidos por token: token => amount
    mapping(address => uint256) public distributedFees;

    /// @notice Volumen de trading por usuario: user => volume (en USD equivalent)
    mapping(address => uint256) public userTradingVolume;

    /// @notice Fees generados por usuario: user => token => amount
    mapping(address => mapping(address => uint256)) public userFeesGenerated;

    // ========== V2 STATE VARIABLES ==========
    
    /// @notice Fee configuration per trade type (V2)
    mapping(TradeType => FeeConfig) public feeConfigs;
    
    /// @notice Tier discount configuration (V2)
    mapping(Tier => TierDiscount) public tierDiscounts;


    // ========== 
    /// @notice Tiers de descuento por volumen
    VolumeTier[] public volumeTiers;

    /// @notice Threshold para auto-distribución
    uint256 public autoDistributeThreshold = 1000 * 10**18; // 1000 tokens

    /// @notice Última vez que se distribuyeron fees
    uint256 public lastDistribution;

    /// @notice Intervalo mínimo entre distribuciones (1 día)
    uint256 public distributionInterval = 1 days;

    // ========== EVENTS ==========
    
    event FeeCollected(
        address indexed from,
        address indexed token,
        uint256 amount,
        string feeType
    );
    
    event FeesDistributed(
        address indexed token,
        uint256 toTreasury,
        uint256 toStaking,
        uint256 burned,
        uint256 toTeam
    );
    
    event FeeStructureUpdated(FeeStructure oldFees, FeeStructure newFees);
    event DistributionUpdated(FeeDistribution oldDist, FeeDistribution newDist);
    event VolumeTierAdded(uint256 minVolume, uint256 discount);
    event UserVolumeUpdated(address indexed user, uint256 newVolume);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event StakingContractUpdated(address indexed oldStaking, address indexed newStaking);

    // ========== CONSTRUCTOR ==========
    
    constructor(
        address admin,
        address _treasury,
        address _stakingContract,
        address _teamWallet,
        address _cambioToken
    ) {
        require(admin != address(0), "Invalid admin");
        require(_treasury != address(0), "Invalid treasury");
        require(_teamWallet != address(0), "Invalid team wallet");
        require(_cambioToken != address(0), "Invalid token");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        treasury = _treasury;
        stakingContract = _stakingContract;
        teamWallet = _teamWallet;
        cambioToken = _cambioToken;

        // Fees por defecto
        fees = FeeStructure({
            p2pTradeFee: 50,        // 0.5%
            fiatBridgeFee: 100,     // 1.0%
            intermediaryFee: 50,    // 0.5%
            stakingEarlyFee: 20,    // 0.2%
            idoCreationFee: 200,    // 2.0%
            disputeFee: 100,        // 1.0%
            withdrawFee: 10         // 0.1%
        });

        // Distribución por defecto
        distribution = FeeDistribution({
            treasuryPercent: 40,    // 40% al treasury
            stakingPercent: 30,     // 30% a staking
            burnPercent: 20,        // 20% a burn
            teamPercent: 10         // 10% al team
        });

        // Tiers de volumen por defecto
        _addVolumeTier(0, 0);               // $0+: 0% descuento
        _addVolumeTier(10000 * 10**18, 10);  // $10k+: 10% descuento
        _addVolumeTier(50000 * 10**18, 20);  // $50k+: 20% descuento
        _addVolumeTier(100000 * 10**18, 30); // $100k+: 30% descuento
        _addVolumeTier(500000 * 10**18, 50); // $500k+: 50% descuento
    }

    // ========== FEE COLLECTION FUNCTIONS ==========
    
    /**
     * @notice Cobra fee de un trade P2P
     * @param user Usuario que paga el fee
     * @param token Token del fee
     * @param tradeAmount Monto del trade
     * @return Cantidad de fee cobrado
     */
    function collectP2PFee(address user, address token, uint256 tradeAmount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        returns (uint256)
    {
        uint256 baseFee = (tradeAmount * fees.p2pTradeFee) / 10000;
        uint256 discount = _calculateDiscount(user, baseFee);
        uint256 finalFee = baseFee - discount;

        _collectFee(user, token, finalFee, "P2P_TRADE");
        return finalFee;
    }

    /**
     * @notice Cobra fee de un intercambio fiat bridge
     * @param user Usuario que paga el fee
     * @param token Token del fee
     * @param amount Monto del intercambio
     * @return Cantidad de fee cobrado
     */
    function collectFiatBridgeFee(address user, address token, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        returns (uint256)
    {
        uint256 baseFee = (amount * fees.fiatBridgeFee) / 10000;
        uint256 discount = _calculateDiscount(user, baseFee);
        uint256 finalFee = baseFee - discount;

        _collectFee(user, token, finalFee, "FIAT_BRIDGE");
        return finalFee;
    }

    /**
     * @notice Cobra fee de intermediario
     * @param intermediary Intermediario que recibe el fee
     * @param token Token del fee
     * @param amount Monto de la transacción
     * @return Cantidad de fee para intermediario
     */
    function collectIntermediaryFee(address intermediary, address token, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        returns (uint256)
    {
        uint256 fee = (amount * fees.intermediaryFee) / 10000;
        
        // Este fee va directo al intermediario, no se acumula para distribución
        emit FeeCollected(intermediary, token, fee, "INTERMEDIARY");
        return fee;
    }

    /**
     * @notice Cobra fee por unstake anticipado
     * @param user Usuario que paga el fee
     * @param amount Monto del unstake
     * @return Cantidad de fee cobrado
     */
    function collectStakingFee(address user, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        returns (uint256)
    {
        uint256 fee = (amount * fees.stakingEarlyFee) / 10000;
        _collectFee(user, cambioToken, fee, "STAKING_EARLY");
        return fee;
    }

    /**
     * @notice Cobra fee por crear IDO
     * @param creator Creador del IDO
     * @param amount Monto del IDO
     * @return Cantidad de fee cobrado
     */
    function collectIDOFee(address creator, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        returns (uint256)
    {
        uint256 fee = (amount * fees.idoCreationFee) / 10000;
        _collectFee(creator, cambioToken, fee, "IDO_CREATION");
        return fee;
    }

    /**
     * @notice Cobra fee por abrir disputa
     * @param user Usuario que abre disputa
     * @param amount Monto en disputa
     * @return Cantidad de fee/stake cobrado
     */
    function collectDisputeFee(address user, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        returns (uint256)
    {
        uint256 fee = (amount * fees.disputeFee) / 10000;
        _collectFee(user, cambioToken, fee, "DISPUTE");
        return fee;
    }

    /**
     * @notice Función interna para colectar fees
     */
    function _collectFee(address from, address token, uint256 amount, string memory feeType)
        internal
    {
        if (amount == 0) return;

        accumulatedFees[token] += amount;
        userFeesGenerated[from][token] += amount;

        emit FeeCollected(from, token, amount, feeType);

        // Auto-distribuir si alcanza threshold
        if (accumulatedFees[token] >= autoDistributeThreshold) {
            _distributeFees(token);
        }
    }

    // ========== DISTRIBUTION FUNCTIONS ==========
    
    /**
     * @notice Distribuye fees acumulados de un token
     * @param token Token a distribuir
     */
    function distributeFees(address token) external nonReentrant {
        require(
            block.timestamp >= lastDistribution + distributionInterval,
            "Distribution too soon"
        );
        _distributeFees(token);
    }

    /**
     * @notice Distribución interna de fees
     */
    function _distributeFees(address token) internal {
        uint256 amount = accumulatedFees[token];
        if (amount == 0) return;

        // Calcular distribución
        uint256 toTreasury = (amount * distribution.treasuryPercent) / 100;
        uint256 toStaking = (amount * distribution.stakingPercent) / 100;
        uint256 toBurn = (amount * distribution.burnPercent) / 100;
        uint256 toTeam = (amount * distribution.teamPercent) / 100;

        // Transferir
        IERC20 tokenContract = IERC20(token);
        
        if (toTreasury > 0) {
            tokenContract.safeTransfer(treasury, toTreasury);
        }
        
        if (toStaking > 0 && stakingContract != address(0)) {
            tokenContract.safeTransfer(stakingContract, toStaking);
        }
        
        if (toBurn > 0 && token == cambioToken) {
            // Burn del token CAMBIO
            try IERC20(token).transfer(address(0xdead), toBurn) {} catch {}
        }
        
        if (toTeam > 0) {
            tokenContract.safeTransfer(teamWallet, toTeam);
        }

        // Actualizar contadores
        accumulatedFees[token] = 0;
        distributedFees[token] += amount;
        lastDistribution = block.timestamp;

        emit FeesDistributed(token, toTreasury, toStaking, toBurn, toTeam);
    }

    // ========== VOLUME TRACKING ==========
    
    /**
     * @notice Actualiza volumen de trading de un usuario
     * @param user Usuario
     * @param volumeUSD Volumen en USD (con 18 decimales)
     */
    function updateUserVolume(address user, uint256 volumeUSD)
        external
        onlyRole(OPERATOR_ROLE)
    {
        userTradingVolume[user] += volumeUSD;
        emit UserVolumeUpdated(user, userTradingVolume[user]);
    }

    /**
     * @notice Calcula descuento por volumen
     * @param user Usuario
     * @param baseFee Fee base
     * @return Descuento a aplicar
     */
    function _calculateDiscount(address user, uint256 baseFee)
        internal
        view
        returns (uint256)
    {
        uint256 volume = userTradingVolume[user];
        uint256 discountBps = 0;

        // Encontrar tier correspondiente
        for (uint256 i = volumeTiers.length; i > 0; i--) {
            if (volume >= volumeTiers[i - 1].minVolume) {
                discountBps = volumeTiers[i - 1].discountBps;
                break;
            }
        }

        return (baseFee * discountBps) / 10000;
    }

    /**
     * @notice Obtiene descuento actual de un usuario
     * @param user Usuario
     * @return Descuento en basis points
     */
    function getUserDiscount(address user) external view returns (uint256) {
        uint256 volume = userTradingVolume[user];

        for (uint256 i = volumeTiers.length; i > 0; i--) {
            if (volume >= volumeTiers[i - 1].minVolume) {
                return volumeTiers[i - 1].discountBps;
            }
        }

        return 0;
    }

    // ========== VIEW FUNCTIONS ==========
    
    /**
     * @notice Calcula fee para un trade
     * @param user Usuario
     * @param amount Monto del trade
     * @param feeType Tipo de fee (0=P2P, 1=Fiat)
     * @return Fee final después de descuento
     */
    function calculateFee(address user, uint256 amount, uint256 feeType)
        external
        view
        returns (uint256)
    {
        uint256 baseFee;
        
        if (feeType == 0) {
            baseFee = (amount * fees.p2pTradeFee) / 10000;
        } else if (feeType == 1) {
            baseFee = (amount * fees.fiatBridgeFee) / 10000;
        } else {
            return 0;
        }

        uint256 discount = _calculateDiscount(user, baseFee);
        return baseFee - discount;
    }

    /**
     * @notice Obtiene fees acumulados de un token
     * @param token Token
     * @return Fees acumulados
     */
    function getAccumulatedFees(address token) external view returns (uint256) {
        return accumulatedFees[token];
    }

    /**
     * @notice Obtiene fees generados por un usuario
     * @param user Usuario
     * @param token Token
     * @return Fees generados
     */
    function getUserFeesGenerated(address user, address token)
        external
        view
        returns (uint256)
    {
        return userFeesGenerated[user][token];
    }

    // ========== ADMIN FUNCTIONS ==========
    
    /**
     * @notice Actualiza estructura de fees
     * @param newFees Nueva estructura
     */
    function updateFees(FeeStructure memory newFees) external onlyRole(ADMIN_ROLE) {
        // Validar que fees no sean excesivos (max 5%)
        require(newFees.p2pTradeFee <= 500, "P2P fee too high");
        require(newFees.fiatBridgeFee <= 500, "Fiat fee too high");
        require(newFees.intermediaryFee <= 500, "Intermediary fee too high");

        FeeStructure memory oldFees = fees;
        fees = newFees;

        emit FeeStructureUpdated(oldFees, newFees);
    }

    /**
     * @notice Actualiza distribución de fees
     * @param newDistribution Nueva distribución
     */
    function updateDistribution(FeeDistribution memory newDistribution)
        external
        onlyRole(ADMIN_ROLE)
    {
        // Validar que suma sea 100%
        require(
            newDistribution.treasuryPercent +
            newDistribution.stakingPercent +
            newDistribution.burnPercent +
            newDistribution.teamPercent == 100,
            "Must sum to 100%"
        );

        FeeDistribution memory oldDist = distribution;
        distribution = newDistribution;

        emit DistributionUpdated(oldDist, newDistribution);
    }

    /**
     * @notice Agrega tier de volumen
     * @param minVolume Volumen mínimo
     * @param discountBps Descuento en basis points
     */
    function addVolumeTier(uint256 minVolume, uint256 discountBps)
        external
        onlyRole(ADMIN_ROLE)
    {
        _addVolumeTier(minVolume, discountBps);
    }

    function _addVolumeTier(uint256 minVolume, uint256 discountBps) internal {
        require(discountBps <= 10000, "Invalid discount");
        
        volumeTiers.push(VolumeTier({
            minVolume: minVolume,
            discountBps: discountBps
        }));

        emit VolumeTierAdded(minVolume, discountBps);
    }

    /**
     * @notice Actualiza treasury
     * @param newTreasury Nueva dirección
     */
    function setTreasury(address newTreasury) external onlyRole(ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid address");
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Actualiza staking contract
     * @param newStaking Nueva dirección
     */
    function setStakingContract(address newStaking) external onlyRole(ADMIN_ROLE) {
        address oldStaking = stakingContract;
        stakingContract = newStaking;
        emit StakingContractUpdated(oldStaking, newStaking);
    }

    /**
     * @notice Actualiza team wallet
     * @param newTeam Nueva dirección
     */
    function setTeamWallet(address newTeam) external onlyRole(ADMIN_ROLE) {
        require(newTeam != address(0), "Invalid address");
        teamWallet = newTeam;
    }

    /**
     * @notice Actualiza threshold de auto-distribución
     * @param newThreshold Nuevo threshold
     */
    function setAutoDistributeThreshold(uint256 newThreshold)
        external
        onlyRole(ADMIN_ROLE)
    {
        autoDistributeThreshold = newThreshold;
    }

    /**
     * @notice Actualiza intervalo de distribución
     * @param newInterval Nuevo intervalo
     */
    function setDistributionInterval(uint256 newInterval)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(newInterval >= 1 hours, "Interval too short");
        distributionInterval = newInterval;
    }

    // ========== V2 FEE CALCULATION (NEVER-ZERO) ==========
    
    /**
     * @notice Calculate fee for a trade (V2 - NEVER-ZERO)
     * @param tradeType Type of trade (crypto-crypto, fiat-fiat, etc.)
     * @param amountUsd Trade amount in USD (6 decimals)
     * @param userTier User's staking tier
     * @return feeUsd Fee amount in USD (6 decimals)
     * @dev CRITICAL: Always returns minimum 0.1% fee (ABSOLUTE_MIN_BPS)
     */
    function calculateFee(
        TradeType tradeType,
        uint256 amountUsd,
        Tier userTier
    ) external view returns (uint256 feeUsd) {
        require(amountUsd > 0, "FeeManager: zero amount");
        
        FeeConfig memory config = feeConfigs[tradeType];
        require(config.baseBps > 0, "FeeManager: invalid trade type");
        
        // Step 1: Calculate base fee
        uint256 baseFeeUsd = (amountUsd * config.baseBps) / BPS;
        
        // Step 2: Apply tier discount
        uint256 finalFeeUsd = baseFeeUsd;
        if (userTier != Tier.None) {
            TierDiscount memory discount = tierDiscounts[userTier];
            uint256 discountAmount = (baseFeeUsd * discount.discountBps) / BPS;
            finalFeeUsd = baseFeeUsd - discountAmount;
        }
        
        // Step 3: Enforce minimum fee
        if (finalFeeUsd < config.minUsd) {
            finalFeeUsd = config.minUsd;
        }
        
        // Step 4: CRITICAL - Enforce absolute minimum (0.1%)
        uint256 absoluteMin = (amountUsd * ABSOLUTE_MIN_BPS) / BPS;
        if (finalFeeUsd < absoluteMin) {
            finalFeeUsd = absoluteMin;
        }
        
        return finalFeeUsd;
    }
    
    /**
     * @notice Get effective fee rate (post-discount)
     * @param tradeType Type of trade
     * @param userTier User's tier
     * @return effectiveBps Effective fee rate in basis points
     */
    function getEffectiveRate(
        TradeType tradeType,
        Tier userTier
    ) external view returns (uint256 effectiveBps) {
        FeeConfig memory config = feeConfigs[tradeType];
        
        if (userTier == Tier.None) {
            return config.baseBps;
        }
        
        TierDiscount memory discount = tierDiscounts[userTier];
        uint256 discountedRate = config.baseBps - ((config.baseBps * discount.discountBps) / BPS);
        
        // Ensure never below absolute minimum
        if (discountedRate < ABSOLUTE_MIN_BPS) {
            return ABSOLUTE_MIN_BPS;
        }
        
        return discountedRate;
    }
    
    // ========== V2 ADMIN FUNCTIONS ==========
    
    /**
     * @notice Update fee configuration for a trade type (V2)
     * @param tradeType Type of trade to update
     * @param baseBps New base fee (basis points)
     * @param vipBps New VIP fee (basis points)
     * @param minUsd New minimum fee (USD, 6 decimals)
     */
    function setFeeConfig(
        TradeType tradeType,
        uint256 baseBps,
        uint256 vipBps,
        uint256 minUsd
    ) external onlyRole(ADMIN_ROLE) {
        require(baseBps >= ABSOLUTE_MIN_BPS, "FeeManager: base below absolute min");
        require(vipBps >= ABSOLUTE_MIN_BPS, "FeeManager: vip below absolute min");
        require(baseBps <= 10000, "FeeManager: base too high");
        require(vipBps <= baseBps, "FeeManager: vip must be <= base");
        
        feeConfigs[tradeType] = FeeConfig(baseBps, vipBps, minUsd);
    }
    
    /**
     * @notice Update tier discount configuration (V2)
     * @param tier Tier to update
     * @param discountBps New discount percentage (10000 = 100%)
     * @param monthlyCapUsd New monthly cap (USD, 6 decimals)
     */
    function setTierDiscount(
        Tier tier,
        uint256 discountBps,
        uint256 monthlyCapUsd
    ) external onlyRole(ADMIN_ROLE) {
        require(tier != Tier.None, "FeeManager: invalid tier");
        require(discountBps <= 10000, "FeeManager: discount too high");
        
        tierDiscounts[tier] = TierDiscount(discountBps, monthlyCapUsd);
    }
    
    /**
     * @notice Initialize V2 fee configs (called once after upgrade)
     */
    function initializeV2Configs() external onlyRole(ADMIN_ROLE) {
        // Initialize fee configs
        feeConfigs[TradeType.CryptoCrypto] = FeeConfig(100, 30, 1e6);    // 1.0% base, 0.3% VIP, $1 min
        feeConfigs[TradeType.FiatCrypto] = FeeConfig(200, 60, 2e6);     // 2.0% base, 0.6% VIP, $2 min
        feeConfigs[TradeType.CryptoFiat] = FeeConfig(180, 54, 2e6);     // 1.8% base, 0.54% VIP, $2 min
        feeConfigs[TradeType.FiatFiat] = FeeConfig(350, 105, 5e6);      // 3.5% base, 1.05% VIP, $5 min
        
        // Initialize tier discounts
        tierDiscounts[Tier.Tier1] = TierDiscount(4000, 10_000e6);  // 40% discount, $10k cap
        tierDiscounts[Tier.Tier2] = TierDiscount(6000, 25_000e6);  // 60% discount, $25k cap
        tierDiscounts[Tier.Tier3] = TierDiscount(8000, 50_000e6);  // 80% discount, $50k cap
        tierDiscounts[Tier.Tier4] = TierDiscount(7000, 100_000e6); // 70% discount, $100k cap
    }
}

