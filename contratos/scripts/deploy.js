const hre = require('hardhat')
const fs = require('fs')
const path = require('path')

/**
 * CAMBIACRIPTO V2 - DEPLOYMENT SCRIPT
 *
 * Deployment Order:
 * 1. Core: CambioToken, CircuitBreaker
 * 2. Oracle: PancakeTwapOracle
 * 3. Managers: FeeManager, ReputationManager, StakingManager
 * 4. Trading: TradeEscrow
 * 5. Disputes: AIResolverAdapter, DisputeManager
 * 6. Treasury: TreasuryManager, LiquidityEngine
 * 7. Configuration: Wire all contracts
 */

// Configuration per network
const CONFIG = {
  bscTestnet: {
    usdc: '0x64544969ed7EBf5f083679233325356EbE738930', // Testnet USDC
    pancakeRouter: '0xD99D1c33F9fC3444f8101754aBC46c52416550D1', // Testnet router
    floorPrice: '0.0001e6', // $0.0001 floor
    ceilingPrice: '10e6' // $10 ceiling
  },
  bscMainnet: {
    usdc: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d', // Mainnet USDC
    pancakeRouter: '0x10ED43C718714eb63d5aA57B78B54704E256024E', // Mainnet router
    floorPrice: '0.001e6', // $0.001 floor
    ceilingPrice: '100e6' // $100 ceiling
  }
}

// Deployment state
let addresses = {}

async function main() {
  console.log('🚀 CAMBIACRIPTO V2 - DEPLOYMENT')
  console.log('================================\n')

  const [deployer] = await hre.ethers.getSigners()
  console.log('Deployer:', deployer.address)
  console.log('Network:', hre.network.name)

  const balance = await hre.ethers.provider.getBalance(deployer.address)
  console.log('Balance:', hre.ethers.formatEther(balance), 'BNB\n')

  // Get network config
  const config = CONFIG[hre.network.name]
  if (!config) {
    throw new Error(`Network ${hre.network.name} not configured`)
  }

  try {
    // Phase 1: Core
    console.log('📦 PHASE 1: CORE CONTRACTS')
    await deployCore(deployer)

    // Phase 2: Oracle
    console.log('\n📡 PHASE 2: PRICE ORACLE')
    await deployOracle(deployer, config)

    // Phase 3: Managers
    console.log('\n⚙️  PHASE 3: MANAGERS')
    await deployManagers(deployer)

    // Phase 4: Trading
    console.log('\n💱 PHASE 4: TRADING')
    await deployTrading(deployer, config)

    // Phase 5: Disputes
    console.log('\n⚖️  PHASE 5: DISPUTES')
    await deployDisputes(deployer)

    // Phase 6: Treasury
    console.log('\n💰 PHASE 6: TREASURY')
    await deployTreasury(deployer, config)

    // Phase 7: Configuration
    console.log('\n🔧 PHASE 7: CONFIGURATION')
    await configureContracts(deployer)

    // Save addresses
    saveAddresses()

    console.log('\n✅ DEPLOYMENT COMPLETE!')
    console.log('Addresses saved to:', getAddressesPath())

    // Verification instructions
    console.log('\n📝 NEXT STEPS:')
    console.log('1. Verify contracts: npx hardhat run scripts/verify.js --network', hre.network.name)
    console.log('2. Seed liquidity: Transfer USDC + CAMBIO to LiquidityEngine')
    console.log('3. Register arbitrators: Call DisputeManager.registerAsArbitrator()')
    console.log('4. Test trades: Create test trade via TradeEscrow')
  } catch (error) {
    console.error('\n❌ DEPLOYMENT FAILED:', error)
    throw error
  }
}

// Phase 1: Core
async function deployCore(deployer) {
  console.log('Deploying CambioToken...')
  const CambioToken = await hre.ethers.getContractFactory('CambioToken')
  const cambioToken = await CambioToken.deploy(deployer.address)
  await cambioToken.waitForDeployment()
  addresses.cambioToken = await cambioToken.getAddress()
  console.log('✓ CambioToken:', addresses.cambioToken)

  console.log('Deploying CircuitBreaker...')
  const CircuitBreaker = await hre.ethers.getContractFactory('CircuitBreaker')
  const circuitBreaker = await CircuitBreaker.deploy(deployer.address)
  await circuitBreaker.waitForDeployment()
  addresses.circuitBreaker = await circuitBreaker.getAddress()
  console.log('✓ CircuitBreaker:', addresses.circuitBreaker)
}

// Phase 2: Oracle
async function deployOracle(deployer, config) {
  // Note: For testnet, create mock pair first if needed
  // For production, use actual PancakeSwap pair

  const pairAddress = '0x0000000000000000000000000000000000000000' // TODO: Set actual pair

  console.log('Deploying PancakeTwapOracleV2...')
  const Oracle = await hre.ethers.getContractFactory('PancakeTwapOracleV2')
  const oracle = await Oracle.deploy(
    deployer.address,
    pairAddress,
    addresses.cambioToken,
    config.usdc,
    config.floorPrice,
    config.ceilingPrice
  )
  await oracle.waitForDeployment()
  addresses.oracle = await oracle.getAddress()
  console.log('✓ PancakeTwapOracleV2:', addresses.oracle)
}

// Phase 3: Managers
async function deployManagers(deployer) {
  console.log('Deploying FeeManagerV2...')
  const FeeManager = await hre.ethers.getContractFactory('FeeManagerV2')
  const feeManager = await FeeManager.deploy(deployer.address)
  await feeManager.waitForDeployment()
  addresses.feeManager = await feeManager.getAddress()
  console.log('✓ FeeManagerV2:', addresses.feeManager)

  console.log('Deploying ReputationManagerV2...')
  const ReputationManager = await hre.ethers.getContractFactory('ReputationManagerV2')
  const reputationManager = await ReputationManager.deploy(deployer.address)
  await reputationManager.waitForDeployment()
  addresses.reputationManager = await reputationManager.getAddress()
  console.log('✓ ReputationManagerV2:', addresses.reputationManager)

  console.log('Deploying StakingManagerV2...')
  const StakingManager = await hre.ethers.getContractFactory('StakingManagerV2')
  const stakingManager = await StakingManager.deploy(
    deployer.address,
    addresses.cambioToken,
    addresses.oracle,
    addresses.circuitBreaker
  )
  await stakingManager.waitForDeployment()
  addresses.stakingManager = await stakingManager.getAddress()
  console.log('✓ StakingManagerV2:', addresses.stakingManager)
}

// Phase 4: Trading
async function deployTrading(deployer, config) {
  console.log('Deploying TradeEscrowV2...')
  const TradeEscrow = await hre.ethers.getContractFactory('TradeEscrowV2')
  const tradeEscrow = await TradeEscrow.deploy(
    deployer.address,
    config.usdc,
    addresses.feeManager,
    addresses.reputationManager,
    addresses.stakingManager,
    addresses.circuitBreaker,
    deployer.address // Temporary treasury (will update later)
  )
  await tradeEscrow.waitForDeployment()
  addresses.tradeEscrow = await tradeEscrow.getAddress()
  console.log('✓ TradeEscrowV2:', addresses.tradeEscrow)
}

// Phase 5: Disputes
async function deployDisputes(deployer) {
  console.log('Deploying DisputeManagerV2...')
  const DisputeManager = await hre.ethers.getContractFactory('DisputeManagerV2')
  const disputeManager = await DisputeManager.deploy(
    deployer.address,
    addresses.cambioToken,
    addresses.reputationManager,
    addresses.stakingManager,
    addresses.oracle
  )
  await disputeManager.waitForDeployment()
  addresses.disputeManager = await disputeManager.getAddress()
  console.log('✓ DisputeManagerV2:', addresses.disputeManager)

  console.log('Deploying AIResolverAdapter...')
  const AIResolver = await hre.ethers.getContractFactory('AIResolverAdapter')
  const aiResolver = await AIResolver.deploy(deployer.address, addresses.disputeManager)
  await aiResolver.waitForDeployment()
  addresses.aiResolver = await aiResolver.getAddress()
  console.log('✓ AIResolverAdapter:', addresses.aiResolver)
}

// Phase 6: Treasury
async function deployTreasury(deployer, config) {
  // Deploy TreasuryManager with placeholder wallets
  console.log('Deploying TreasuryManagerV2...')
  const TreasuryManager = await hre.ethers.getContractFactory('TreasuryManagerV2')
  const treasuryManager = await TreasuryManager.deploy(
    deployer.address,
    config.usdc,
    deployer.address, // liquidityEngine (will set later)
    deployer.address, // stakingPool
    deployer.address, // treasuryWallet
    deployer.address, // referralPool
    deployer.address, // retainedEarnings
    deployer.address, // validatorPool
    deployer.address, // socialFiPool
    deployer.address, // lotteryPool
    deployer.address // marketOpsWallet
  )
  await treasuryManager.waitForDeployment()
  addresses.treasuryManager = await treasuryManager.getAddress()
  console.log('✓ TreasuryManagerV2:', addresses.treasuryManager)

  console.log('Deploying LiquidityEngineV2...')
  const LiquidityEngine = await hre.ethers.getContractFactory('LiquidityEngineV2')
  const liquidityEngine = await LiquidityEngine.deploy(
    deployer.address,
    config.usdc,
    addresses.cambioToken,
    '0x0000000000000000000000000000000000000000', // LP token (set after pair creation)
    config.pancakeRouter,
    addresses.circuitBreaker
  )
  await liquidityEngine.waitForDeployment()
  addresses.liquidityEngine = await liquidityEngine.getAddress()
  console.log('✓ LiquidityEngineV2:', addresses.liquidityEngine)
}

// Phase 7: Configuration
async function configureContracts(deployer) {
  console.log('Authorizing contracts...')

  // ReputationManager: Authorize TradeEscrow and DisputeManager
  const reputationManager = await hre.ethers.getContractAt('ReputationManagerV2', addresses.reputationManager)
  await reputationManager.setAuthorizedContract(addresses.tradeEscrow, true)
  console.log('✓ TradeEscrow authorized in ReputationManager')

  await reputationManager.setAuthorizedContract(addresses.disputeManager, true)
  console.log('✓ DisputeManager authorized in ReputationManager')

  // TradeEscrow: Set treasury
  const tradeEscrow = await hre.ethers.getContractAt('TradeEscrowV2', addresses.tradeEscrow)
  await tradeEscrow.setTreasury(addresses.treasuryManager)
  console.log('✓ Treasury set in TradeEscrow')

  // TreasuryManager: Set LiquidityEngine
  const treasuryManager = await hre.ethers.getContractAt('TreasuryManagerV2', addresses.treasuryManager)
  await treasuryManager.setLiquidityEngine(addresses.liquidityEngine)
  console.log('✓ LiquidityEngine set in TreasuryManager')

  console.log('✓ All contracts configured')
}

// Utilities
function saveAddresses() {
  const filePath = getAddressesPath()
  const data = {
    network: hre.network.name,
    timestamp: new Date().toISOString(),
    addresses: addresses
  }

  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2))
}

function getAddressesPath() {
  return path.join(__dirname, '..', 'deployments', `${hre.network.name}.json`)
}

// Execute
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
