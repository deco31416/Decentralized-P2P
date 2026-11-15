// ============================================
// 🪙 DEPLOYMENT DE TOKENS MOCK - BSC Testnet
// ============================================

const { ethers } = require('hardhat')
const fs = require('fs')
const path = require('path')

/**
 * TOKENS A CREAR:
 * 1. MockUSDT (6 decimals) - Simula Tether
 * 2. MockBUSD (18 decimals) - Simula Binance USD
 * 3. MockBTC (8 decimals) - Simula Bitcoin
 * 4. MockETH (18 decimals) - Simula Ethereum
 * 5. MockWBNB (18 decimals) - Wrapped BNB
 * 6. CambioToken (18 decimals) - Token nativo del proyecto
 */

async function main() {
  console.log('🪙 Deployando tokens mock en BSC Testnet...\n')

  const [deployer] = await ethers.getSigners()
  console.log(`Deployer: ${deployer.address}`)
  console.log(`Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} BNB\n`)

  const deployedTokens = {}

  // ============================================
  // 1️⃣ MockUSDT (6 decimals)
  // ============================================
  console.log('1. Deployando MockUSDT...')
  const MockUSDT = await ethers.getContractFactory('MockERC20')
  const mockUSDT = await MockUSDT.deploy(
    'Mock Tether USD',
    'USDT',
    6, // 6 decimals (como USDT real)
    ethers.parseUnits('10000000', 6) // 10M USDT inicial
  )
  await mockUSDT.waitForDeployment()
  deployedTokens.USDT = await mockUSDT.getAddress()
  console.log(`✅ MockUSDT: ${deployedTokens.USDT}`)
  console.log(`   Supply: 10,000,000 USDT\n`)

  // ============================================
  // 2️⃣ MockBUSD (18 decimals)
  // ============================================
  console.log('2. Deployando MockBUSD...')
  const MockBUSD = await ethers.getContractFactory('MockERC20')
  const mockBUSD = await MockBUSD.deploy(
    'Mock Binance USD',
    'BUSD',
    18, // 18 decimals
    ethers.parseEther('10000000') // 10M BUSD inicial
  )
  await mockBUSD.waitForDeployment()
  deployedTokens.BUSD = await mockBUSD.getAddress()
  console.log(`✅ MockBUSD: ${deployedTokens.BUSD}`)
  console.log(`   Supply: 10,000,000 BUSD\n`)

  // ============================================
  // 3️⃣ MockBTC (8 decimals)
  // ============================================
  console.log('3. Deployando MockBTC...')
  const MockBTC = await ethers.getContractFactory('MockERC20')
  const mockBTC = await MockBTC.deploy(
    'Mock Bitcoin',
    'BTC',
    8, // 8 decimals (como BTC real)
    ethers.parseUnits('1000', 8) // 1,000 BTC inicial
  )
  await mockBTC.waitForDeployment()
  deployedTokens.BTC = await mockBTC.getAddress()
  console.log(`✅ MockBTC: ${deployedTokens.BTC}`)
  console.log(`   Supply: 1,000 BTC\n`)

  // ============================================
  // 4️⃣ MockETH (18 decimals)
  // ============================================
  console.log('4. Deployando MockETH...')
  const MockETH = await ethers.getContractFactory('MockERC20')
  const mockETH = await MockETH.deploy(
    'Mock Ethereum',
    'ETH',
    18, // 18 decimals
    ethers.parseEther('10000') // 10,000 ETH inicial
  )
  await mockETH.waitForDeployment()
  deployedTokens.ETH = await mockETH.getAddress()
  console.log(`✅ MockETH: ${deployedTokens.ETH}`)
  console.log(`   Supply: 10,000 ETH\n`)

  // ============================================
  // 5️⃣ MockWBNB (18 decimals)
  // ============================================
  console.log('5. Deployando MockWBNB...')
  const MockWBNB = await ethers.getContractFactory('MockWBNB')
  const mockWBNB = await MockWBNB.deploy()
  await mockWBNB.waitForDeployment()
  deployedTokens.WBNB = await mockWBNB.getAddress()
  console.log(`✅ MockWBNB: ${deployedTokens.WBNB}`)
  console.log(`   Supply: 0 (wrap BNB para obtener WBNB)\n`)

  // Mintear algo de WBNB inicial al deployer
  console.log('   Minteando 100 WBNB inicial al deployer...')
  await mockWBNB.faucet(ethers.parseEther('100'))
  console.log('   ✅ 100 WBNB minteados\n')

  // ============================================
  // 6️⃣ CambioToken (18 decimals) - Token del proyecto
  // ============================================
  console.log('6. Deployando CambioToken...')
  const CambioToken = await ethers.getContractFactory('MockERC20')
  const cambioToken = await CambioToken.deploy(
    'CambiaCripto Token',
    'CAMBIO',
    18, // 18 decimals
    ethers.parseEther('100000000') // 100M CAMBIO inicial
  )
  await cambioToken.waitForDeployment()
  deployedTokens.CAMBIO = await cambioToken.getAddress()
  console.log(`✅ CambioToken: ${deployedTokens.CAMBIO}`)
  console.log(`   Supply: 100,000,000 CAMBIO\n`)

  // ============================================
  // 📝 GUARDAR ADDRESSES
  // ============================================
  console.log('💾 Guardando addresses...\n')

  const addressesPath = path.join(__dirname, '../deployed-tokens.json')
  fs.writeFileSync(
    addressesPath,
    JSON.stringify(deployedTokens, null, 2)
  )
  console.log(`✅ Addresses guardadas en: deployed-tokens.json\n`)

  // ============================================
  // 📋 RESUMEN
  // ============================================
  console.log('=' .repeat(60))
  console.log('🎉 TOKENS MOCK DEPLOYADOS')
  console.log('=' .repeat(60))
  console.log('\n📦 Tokens creados:\n')
  console.log(`USDT  (6 dec):  ${deployedTokens.USDT}`)
  console.log(`BUSD  (18 dec): ${deployedTokens.BUSD}`)
  console.log(`BTC   (8 dec):  ${deployedTokens.BTC}`)
  console.log(`ETH   (18 dec): ${deployedTokens.ETH}`)
  console.log(`WBNB  (18 dec): ${deployedTokens.WBNB}`)
  console.log(`CAMBIO (18 dec): ${deployedTokens.CAMBIO}`)

  console.log('\n📝 PRÓXIMOS PASOS:\n')
  console.log('1. Copia estas addresses al .env:')
  console.log(`   TOKEN_USDT=${deployedTokens.USDT}`)
  console.log(`   TOKEN_BUSD=${deployedTokens.BUSD}`)
  console.log(`   TOKEN_BTC=${deployedTokens.BTC}`)
  console.log(`   TOKEN_ETH=${deployedTokens.ETH}`)
  console.log(`   TOKEN_WBNB=${deployedTokens.WBNB}`)
  console.log(`   TOKEN_CAMBIO=${deployedTokens.CAMBIO}`)

  console.log('\n2. Deploy los contratos principales:')
  console.log('   npx hardhat run scripts/deploy.js --network bsctestnet')

  console.log('\n3. Configura el sistema:')
  console.log('   npx hardhat run scripts/configure-system.js --network bsctestnet')

  console.log('\n💡 FAUCET: Usa token.faucet(amount) para obtener tokens gratis')
  console.log('   Ejemplo: await mockUSDT.faucet(ethers.parseUnits("1000", 6))')

  console.log('\n✅ Deployment completado!\n')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
