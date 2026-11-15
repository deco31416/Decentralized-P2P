/**
 * @title Deploy Script para Sistema P2P Fiat-to-Fiat
 * @notice Despliega FiatFeeManager, FiatDisputeResolver y P2PFiatExchange
 * @dev Guarda las direcciones desplegadas en deployments.json
 *
 * Uso:
 *   npx hardhat run scripts/deploy-fiat-p2p.js --network bscTestnet
 *   npx hardhat run scripts/deploy-fiat-p2p.js --network bsc
 */

const hre = require('hardhat')
const fs = require('fs')
const path = require('path')

// Direcciones de tokens en BSC
const TOKENS = {
  bscMainnet: {
    USDT: '0x55d398326f99059fF775485246999027B3197955',
    BUSD: '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56'
  },
  bscTestnet: {
    USDT: '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd', // Mock USDT testnet
    BUSD: '0xaB1a4d4f1D656d2450692D237fdD6C7f9146e814' // Mock BUSD testnet
  }
}

// Configuración de comisiones por defecto (%)
const DEFAULT_MAX_FEES = {
  USD: 7, // 7% máximo
  EUR: 5, // 5% máximo
  COP: 10, // 10% máximo
  MXN: 8, // 8% máximo
  BRL: 8, // 8% máximo
  ARS: 12 // 12% máximo
}

async function main() {
  const [deployer] = await hre.ethers.getSigners()
  const network = hre.network.name

  console.log('🚀 Deploying Fiat P2P System...')
  console.log('📍 Network:', network)
  console.log('👤 Deployer:', deployer.address)
  console.log('💰 Balance:', hre.ethers.utils.formatEther(await deployer.getBalance()), 'BNB\n')

  // Obtener dirección USDT según la red
  const usdtAddress = TOKENS[network]?.USDT || TOKENS.bscTestnet.USDT
  console.log('💵 USDT Token:', usdtAddress)

  // ==============================================
  // 1️⃣ DESPLEGAR FiatFeeManager
  // ==============================================
  console.log('\n📦 Deploying FiatFeeManager...')
  const FiatFeeManager = await hre.ethers.getContractFactory('FiatFeeManager')
  const fiatFeeManager = await FiatFeeManager.deploy(deployer.address)
  await fiatFeeManager.deployed()
  console.log('✅ FiatFeeManager deployed:', fiatFeeManager.address)

  // ==============================================
  // 2️⃣ DESPLEGAR FiatDisputeResolver
  // ==============================================
  console.log('\n📦 Deploying FiatDisputeResolver...')
  const FiatDisputeResolver = await hre.ethers.getContractFactory('FiatDisputeResolver')
  const fiatDisputeResolver = await FiatDisputeResolver.deploy(
    deployer.address,
    hre.ethers.constants.AddressZero // P2P se configura después
  )
  await fiatDisputeResolver.deployed()
  console.log('✅ FiatDisputeResolver deployed:', fiatDisputeResolver.address)

  // ==============================================
  // 3️⃣ DESPLEGAR P2PFiatExchange
  // ==============================================
  console.log('\n📦 Deploying P2PFiatExchange...')
  const P2PFiatExchange = await hre.ethers.getContractFactory('P2PFiatExchange')
  const p2pFiatExchange = await P2PFiatExchange.deploy(
    deployer.address,
    usdtAddress,
    fiatFeeManager.address,
    fiatDisputeResolver.address
  )
  await p2pFiatExchange.deployed()
  console.log('✅ P2PFiatExchange deployed:', p2pFiatExchange.address)

  // ==============================================
  // 4️⃣ CONFIGURAR INTEGRACIÓN
  // ==============================================
  console.log('\n⚙️ Configuring contracts integration...')

  // Configurar P2P en DisputeResolver
  console.log('🔗 Setting P2P address in DisputeResolver...')
  let tx = await fiatDisputeResolver.setP2PFiatExchange(p2pFiatExchange.address)
  await tx.wait()
  console.log('✅ P2P address configured')

  // ==============================================
  // 5️⃣ CONFIGURAR COMISIONES MÁXIMAS
  // ==============================================
  console.log('\n💸 Setting default max fees...')

  for (const [currency, maxFee] of Object.entries(DEFAULT_MAX_FEES)) {
    console.log(`  Setting ${currency} max fee: ${maxFee}%`)
    tx = await fiatFeeManager.setMaxFiatFee(currency, maxFee)
    await tx.wait()
  }
  console.log('✅ Max fees configured')

  // ==============================================
  // 6️⃣ GUARDAR DEPLOYMENTS
  // ==============================================
  const deployments = {
    network,
    timestamp: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      FiatFeeManager: fiatFeeManager.address,
      FiatDisputeResolver: fiatDisputeResolver.address,
      P2PFiatExchange: p2pFiatExchange.address,
      USDT: usdtAddress
    },
    configuration: {
      fiatOrderTimeout: '24 hours',
      minimumFiatOrderUSD: '100 USDT',
      maxFees: DEFAULT_MAX_FEES
    }
  }

  const deploymentsPath = path.join(__dirname, '../deployments.json')
  let allDeployments = {}

  if (fs.existsSync(deploymentsPath)) {
    allDeployments = JSON.parse(fs.readFileSync(deploymentsPath, 'utf8'))
  }

  allDeployments[network] = deployments
  fs.writeFileSync(deploymentsPath, JSON.stringify(allDeployments, null, 2))

  console.log('\n💾 Deployments saved to deployments.json')

  // ==============================================
  // 7️⃣ RESUMEN
  // ==============================================
  console.log('\n' + '='.repeat(60))
  console.log('🎉 DEPLOYMENT SUCCESSFUL!')
  console.log('='.repeat(60))
  console.log('\n📄 Contract Addresses:')
  console.log('  FiatFeeManager:      ', fiatFeeManager.address)
  console.log('  FiatDisputeResolver: ', fiatDisputeResolver.address)
  console.log('  P2PFiatExchange:     ', p2pFiatExchange.address)
  console.log('  USDT Token:          ', usdtAddress)

  console.log('\n🔧 Next Steps:')
  console.log('  1. Verify contracts on BSCScan:')
  console.log(`     npx hardhat verify --network ${network} ${fiatFeeManager.address} "${deployer.address}"`)
  console.log(
    `     npx hardhat verify --network ${network} ${fiatDisputeResolver.address} "${deployer.address}" "${hre.ethers.constants.AddressZero}"`
  )
  console.log(
    `     npx hardhat verify --network ${network} ${p2pFiatExchange.address} "${deployer.address}" "${usdtAddress}" "${fiatFeeManager.address}" "${fiatDisputeResolver.address}"`
  )

  console.log('\n  2. Approve initial intermediaries:')
  console.log('     Run: scripts/approve-intermediaries.js')

  console.log('\n  3. Update frontend with new contract addresses')
  console.log('     File: lib/contracts.ts')

  console.log('\n' + '='.repeat(60))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Deployment failed:', error)
    process.exit(1)
  })
