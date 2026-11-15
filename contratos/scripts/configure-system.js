// ============================================
// 📝 GUÍA DE CONFIGURACIÓN POST-DEPLOYMENT
// CambiaCripto v2.2.1 - BSC Testnet
// ============================================

const { ethers } = require('hardhat')

/**
 * ORDEN DE CONFIGURACIÓN:
 * 1. Configurar tokens (whitelist)
 * 2. Configurar fees
 * 3. Configurar límites y restricciones
 * 4. Otorgar roles
 * 5. Aprobar intermediarios/validators
 * 6. Configurar oracles
 * 7. Testing
 */

async function configureSystem() {
  const [deployer, admin, operator] = await ethers.getSigners()

  console.log('🔧 Iniciando configuración del sistema...')
  console.log(`Deployer: ${deployer.address}`)
  console.log(`Admin: ${admin.address}`)
  console.log(`Operator: ${operator.address}\n`)

  // ============================================
  // 1️⃣ CONFIGURAR TOKENS (AssetManager)
  // ============================================
  console.log('📦 1. Configurando tokens...\n')

  const assetManager = await ethers.getContract('AssetManager')

  // Cargar tokens mock deployados
  const fs = require('fs')
  const path = require('path')
  const tokensPath = path.join(__dirname, '../deployed-tokens.json')
  
  if (!fs.existsSync(tokensPath)) {
    throw new Error('❌ No se encontró deployed-tokens.json. Ejecuta: npx hardhat run scripts/deploy-mock-tokens.js --network bsctestnet')
  }
  
  const TOKENS = JSON.parse(fs.readFileSync(tokensPath, 'utf8'))
  console.log('✅ Tokens cargados desde deployed-tokens.json\n')

  // Añadir USDT
  await assetManager.addToken(
    TOKENS.USDT, // address
    'USDT', // symbol
    'Tether USD', // name
    6, // decimals
    0, // category: 0 = Stablecoin
    true, // isActive
    true, // canDeposit
    true, // canWithdraw
    true, // canTrade
    true, // canStake
    1e6, // minDeposit: 1 USDT
    1000000e6, // maxDeposit: 1M USDT
    1e6, // minWithdraw: 1 USDT
    1000000e6, // maxWithdraw: 1M USDT
    10000e6, // dailyDepositLimit: 10k USDT
    10000e6, // dailyWithdrawLimit: 10k USDT
    30, // depositFee: 0.3% (30 basis points)
    50 // withdrawFee: 0.5% (50 basis points)
  )
  console.log('✅ USDT configurado')

  // Añadir BUSD
  await assetManager.addToken(
    TOKENS.BUSD,
    'BUSD',
    'Binance USD',
    18,
    0, // Stablecoin
    true,
    true,
    true,
    true,
    true,
    ethers.parseEther('1'),
    ethers.parseEther('1000000'),
    ethers.parseEther('1'),
    ethers.parseEther('1000000'),
    ethers.parseEther('10000'),
    ethers.parseEther('10000'),
    30,
    50
  )
  console.log('✅ BUSD configurado')

  // Añadir WBNB
  await assetManager.addToken(
    TOKENS.WBNB,
    'WBNB',
    'Wrapped BNB',
    18,
    1, // category: 1 = Native
    true,
    true,
    true,
    true,
    true,
    ethers.parseEther('0.01'), // min: 0.01 BNB
    ethers.parseEther('100'), // max: 100 BNB
    ethers.parseEther('0.01'),
    ethers.parseEther('100'),
    ethers.parseEther('10'),
    ethers.parseEther('10'),
    30,
    50
  )
  console.log('✅ WBNB configurado')

  // Añadir BTC (Mock)
  await assetManager.addToken(
    TOKENS.BTC,
    'BTC',
    'Mock Bitcoin',
    8, // 8 decimals (como BTC real)
    2, // category: 2 = Major
    true,
    true,
    true,
    true,
    false, // no stake
    ethers.parseUnits('0.001', 8),
    ethers.parseUnits('10', 8),
    ethers.parseUnits('0.001', 8),
    ethers.parseUnits('10', 8),
    ethers.parseUnits('1', 8),
    ethers.parseUnits('1', 8),
    30,
    50
  )
  console.log('✅ BTC configurado')

  // Añadir ETH (Mock)
  await assetManager.addToken(
    TOKENS.ETH,
    'ETH',
    'Mock Ethereum',
    18,
    2, // category: 2 = Major
    true,
    true,
    true,
    true,
    false,
    ethers.parseEther('0.01'),
    ethers.parseEther('100'),
    ethers.parseEther('0.01'),
    ethers.parseEther('100'),
    ethers.parseEther('10'),
    ethers.parseEther('10'),
    30,
    50
  )
  console.log('✅ ETH configurado')

  // Añadir CAMBIO (Token del proyecto)
  await assetManager.addToken(
    TOKENS.CAMBIO,
    'CAMBIO',
    'CambiaCripto Token',
    18,
    5, // category: 5 = Governance
    true,
    true,
    true,
    true,
    true, // SÍ puede hacer stake
    ethers.parseEther('10'), // min: 10 CAMBIO
    ethers.parseEther('10000000'), // max: 10M CAMBIO
    ethers.parseEther('10'),
    ethers.parseEther('10000000'),
    ethers.parseEther('100000'),
    ethers.parseEther('100000'),
    0, // sin fee de deposit
    0 // sin fee de withdraw
  )
  console.log('✅ CAMBIO configurado (token de gobernanza)')

  console.log('\n✅ Tokens configurados\n')

  // ============================================
  // 2️⃣ CONFIGURAR FEES (FeeManager)
  // ============================================
  console.log('💰 2. Configurando fees...\n')

  const feeManager = await ethers.getContract('FeeManager')

  // Configurar fees globales
  await feeManager.updateFees({
    tradingFee: 30, // 0.3%
    stakingFee: 0, // 0% (sin fee para stake)
    withdrawFee: 50, // 0.5%
    depositFee: 30, // 0.3%
    p2pFee: 50, // 0.5% para P2P
    bridgeFee: 100, // 1% para bridges
    quickBuyFee: 150, // 1.5% para quick buy
    referralReward: 1000 // 10% de las fees va a referrals
  })
  console.log('✅ Fees globales configurados')

  // Configurar distribución de fees
  await feeManager.updateDistribution({
    treasuryShare: 4000, // 40% al treasury
    stakingShare: 3000, // 30% a staking rewards
    burnShare: 2000, // 20% burn
    teamShare: 1000 // 10% al team
  })
  console.log('✅ Distribución de fees configurada')

  // Configurar fees por tipo de trade (V2)
  await feeManager.setFeeConfig(
    0, // TradeType: P2P
    50, // baseFee: 0.5%
    30, // minFee: 0.3%
    200, // maxFee: 2%
    true // isActive
  )
  console.log('✅ Fees P2P configurados')

  await feeManager.setFeeConfig(
    1, // TradeType: Bridge
    100, // 1%
    50,
    300,
    true
  )
  console.log('✅ Fees Bridge configurados')

  await feeManager.setFeeConfig(
    2, // TradeType: QuickBuy
    150, // 1.5%
    100,
    500,
    true
  )
  console.log('✅ Fees QuickBuy configurados')

  // Configurar descuentos por tier
  await feeManager.setTierDiscount(
    0, // Tier.BRONZE
    0, // 0% discount
    0 // 0 volume required
  )

  await feeManager.setTierDiscount(
    1, // Tier.SILVER
    1000, // 10% discount
    ethers.parseEther('10000') // 10k USD volume
  )

  await feeManager.setTierDiscount(
    2, // Tier.GOLD
    2000, // 20% discount
    ethers.parseEther('50000') // 50k USD
  )

  await feeManager.setTierDiscount(
    3, // Tier.PLATINUM
    3000, // 30% discount
    ethers.parseEther('100000') // 100k USD
  )

  await feeManager.setTierDiscount(
    4, // Tier.DIAMOND
    5000, // 50% discount
    ethers.parseEther('1000000') // 1M USD
  )
  console.log('✅ Descuentos por tier configurados')

  console.log('\n✅ Fees configurados\n')

  // ============================================
  // 3️⃣ CONFIGURAR KYC (KYCManager)
  // ============================================
  console.log('🔐 3. Configurando KYC...\n')

  const kycManager = await ethers.getContract('KYCManager')

  // Configurar límites por tier
  await kycManager.setTierLimits(
    0, // Tier.NONE
    ethers.parseEther('100'), // dailyLimit: $100
    ethers.parseEther('500'), // monthlyLimit: $500
    ethers.parseEther('50') // transactionLimit: $50
  )
  console.log('✅ Límites NONE configurados')

  await kycManager.setTierLimits(
    1, // Tier.BASIC
    ethers.parseEther('1000'), // $1k daily
    ethers.parseEther('10000'), // $10k monthly
    ethers.parseEther('500') // $500 per tx
  )
  console.log('✅ Límites BASIC configurados')

  await kycManager.setTierLimits(
    2, // Tier.INTERMEDIATE
    ethers.parseEther('10000'), // $10k daily
    ethers.parseEther('100000'), // $100k monthly
    ethers.parseEther('5000') // $5k per tx
  )
  console.log('✅ Límites INTERMEDIATE configurados')

  await kycManager.setTierLimits(
    3, // Tier.ADVANCED
    ethers.parseEther('50000'), // $50k daily
    ethers.parseEther('500000'), // $500k monthly
    ethers.parseEther('25000') // $25k per tx
  )
  console.log('✅ Límites ADVANCED configurados')

  await kycManager.setTierLimits(
    4, // Tier.PREMIUM
    ethers.parseEther('1000000'), // $1M daily (sin límite práctico)
    ethers.parseEther('10000000'), // $10M monthly
    ethers.parseEther('500000') // $500k per tx
  )
  console.log('✅ Límites PREMIUM configurados')

  console.log('\n✅ KYC configurado\n')

  // ============================================
  // 4️⃣ OTORGAR ROLES
  // ============================================
  console.log('👥 4. Otorgando roles...\n')

  // Roles principales (ajusta según tus contratos)
  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes('ADMIN_ROLE'))
  const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE'))
  const PAUSER_ROLE = ethers.keccak256(ethers.toUtf8Bytes('PAUSER_ROLE'))

  // Otorgar roles en AssetManager
  await assetManager.grantRole(ADMIN_ROLE, admin.address)
  await assetManager.grantRole(OPERATOR_ROLE, operator.address)
  console.log('✅ Roles en AssetManager otorgados')

  // Otorgar roles en FeeManager
  await feeManager.grantRole(ADMIN_ROLE, admin.address)
  console.log('✅ Roles en FeeManager otorgados')

  // Otorgar roles en KYCManager
  await kycManager.grantRole(ADMIN_ROLE, admin.address)
  await kycManager.grantRole(OPERATOR_ROLE, operator.address)
  console.log('✅ Roles en KYCManager otorgados')

  console.log('\n✅ Roles otorgados\n')

  // ============================================
  // 5️⃣ CONFIGURAR STAKING (StakingManager)
  // ============================================
  console.log('💎 5. Configurando staking...\n')

  const stakingManager = await ethers.getContract('StakingManagerV2')

  // Configurar pools de staking
  await stakingManager.setPoolConfig(
    0, // poolId: FLEXIBLE
    100, // APY: 1% (100 basis points)
    0, // lockPeriod: 0 (flexible)
    ethers.parseEther('100'), // minStake: 100 tokens
    ethers.parseEther('1000000'), // maxStake: 1M tokens
    10000, // multiplier: 1x (10000 = 100%)
    true // isActive
  )
  console.log('✅ Pool FLEXIBLE configurado')

  await stakingManager.setPoolConfig(
    1, // poolId: LOCKED_30
    1500, // APY: 15%
    30 * 24 * 60 * 60, // 30 días
    ethers.parseEther('100'),
    ethers.parseEther('1000000'),
    12000, // 1.2x multiplier
    true
  )
  console.log('✅ Pool LOCKED_30 configurado')

  await stakingManager.setPoolConfig(
    2, // poolId: LOCKED_90
    2500, // APY: 25%
    90 * 24 * 60 * 60, // 90 días
    ethers.parseEther('100'),
    ethers.parseEther('1000000'),
    15000, // 1.5x multiplier
    true
  )
  console.log('✅ Pool LOCKED_90 configurado')

  await stakingManager.setPoolConfig(
    3, // poolId: LOCKED_180
    4000, // APY: 40%
    180 * 24 * 60 * 60, // 180 días
    ethers.parseEther('100'),
    ethers.parseEther('1000000'),
    20000, // 2x multiplier
    true
  )
  console.log('✅ Pool LOCKED_180 configurado')

  await stakingManager.setPoolConfig(
    4, // poolId: LOCKED_365
    6000, // APY: 60%
    365 * 24 * 60 * 60, // 365 días
    ethers.parseEther('100'),
    ethers.parseEther('1000000'),
    30000, // 3x multiplier
    true
  )
  console.log('✅ Pool LOCKED_365 configurado')

  console.log('\n✅ Staking configurado\n')

  // ============================================
  // 6️⃣ CONFIGURAR ORACLES
  // ============================================
  console.log('🔮 6. Configurando oracles...\n')

  const priceOracle = await ethers.getContract('PancakeTwapOracleV2')

  // Configurar pairs de PancakeSwap en BSC Testnet
  const PANCAKE_PAIRS = {
    'BNB-USDT': '0x...', // Reemplazar con address real del par en testnet
    'BNB-BUSD': '0x...',
    'BTCB-USDT': '0x...'
  }

  // Configurar cada pair en el oracle
  // await priceOracle.setPair(TOKENS.WBNB, TOKENS.USDT, PANCAKE_PAIRS['BNB-USDT'])
  // await priceOracle.setPair(TOKENS.WBNB, TOKENS.BUSD, PANCAKE_PAIRS['BNB-BUSD'])
  // await priceOracle.setPair(TOKENS.BTCB, TOKENS.USDT, PANCAKE_PAIRS['BTCB-USDT'])

  console.log('⚠️  Oracles: Configurar pairs manualmente con addresses de testnet')
  console.log('📝 Ver: https://pancake.kiemtienonline360.com/ para pairs de testnet\n')

  // ============================================
  // 7️⃣ CONFIGURAR LIMITS & RESTRICTIONS
  // ============================================
  console.log('⚙️  7. Configurando límites y restricciones...\n')

  const withdrawManager = await ethers.getContract('WithdrawManager')
  const depositManager = await ethers.getContract('DepositManager')

  // Configurar cooldowns
  await withdrawManager.setGlobalCooldown(60) // 1 minuto entre retiros
  console.log('✅ Cooldown de retiros: 1 minuto')

  // Configurar queue threshold (retiros grandes van a cola)
  await withdrawManager.setQueueThreshold(
    TOKENS.USDT,
    10000e6 // 10k USDT
  )
  console.log('✅ Queue threshold USDT: 10k')

  await withdrawManager.setQueueThreshold(
    TOKENS.WBNB,
    ethers.parseEther('10') // 10 BNB
  )
  console.log('✅ Queue threshold BNB: 10')

  // Configurar emergency withdrawals (inicialmente deshabilitado)
  await withdrawManager.setEmergencyWithdrawalsEnabled(false)
  console.log('✅ Emergency withdrawals: DESHABILITADO')

  console.log('\n✅ Límites configurados\n')

  // ============================================
  // 8️⃣ APROBAR INTERMEDIARIOS (IntermediaryManager)
  // ============================================
  console.log('🤝 8. Configurando intermediarios...\n')

  const intermediaryManager = await ethers.getContract('IntermediaryManager')

  // Configurar requisitos de intermediario
  await intermediaryManager.setMinStake(
    ethers.parseEther('50000'), // 50k CAMBIO tokens
    true // isValidator
  )
  console.log('✅ Min stake validator: 50k CAMBIO')

  await intermediaryManager.setMinStake(
    ethers.parseEther('10000'), // 10k CAMBIO tokens
    false // isIntermediary
  )
  console.log('✅ Min stake intermediary: 10k CAMBIO')

  // Configurar collateral ratio
  await intermediaryManager.setCollateralRatio(15000) // 150%
  console.log('✅ Collateral ratio: 150%')

  await intermediaryManager.setLiquidationRatio(12000) // 120%
  console.log('✅ Liquidation ratio: 120%')

  console.log('\n✅ Intermediarios configurados\n')

  // ============================================
  // 9️⃣ CONFIGURAR BRIDGES
  // ============================================
  console.log('🌉 9. Configurando bridges...\n')

  const cryptoToFiatBridge = await ethers.getContract('CryptoToFiatBridge')
  const fiatToCryptoBridge = await ethers.getContract('FiatToCryptoBridge')
  const fiatToFiatBridge = await ethers.getContract('FiatToFiatBridge')

  // Configurar fees de bridges
  await cryptoToFiatBridge.setBridgeFee(100) // 1%
  console.log('✅ CryptoToFiat fee: 1%')

  await fiatToCryptoBridge.setBridgeFee(100) // 1%
  console.log('✅ FiatToCrypto fee: 1%')

  await fiatToFiatBridge.setBridgeFee(150) // 1.5%
  console.log('✅ FiatToFiat fee: 1.5%')

  // Configurar min validator stake
  await cryptoToFiatBridge.setMinValidatorStake(ethers.parseEther('50000'))
  await fiatToCryptoBridge.setMinValidatorStake(ethers.parseEther('50000'))
  console.log('✅ Min validator stake: 50k CAMBIO')

  // Configurar timeouts
  await cryptoToFiatBridge.setDefaultTimeout(24 * 60 * 60) // 24 horas
  await fiatToCryptoBridge.setDefaultTimeout(24 * 60 * 60)
  await fiatToFiatBridge.setDefaultTimeout(48 * 60 * 60) // 48 horas
  console.log('✅ Timeouts configurados')

  console.log('\n✅ Bridges configurados\n')

  // ============================================
  // 🔟 CONFIGURAR DISPUTE MANAGER
  // ============================================
  console.log('⚖️  10. Configurando dispute manager...\n')

  const disputeManager = await ethers.getContract('DisputeManagerV2')

  // Configurar requisitos de arbitrador
  await disputeManager.setMinArbitratorStake(ethers.parseEther('5000')) // 5k CAMBIO
  console.log('✅ Min arbitrator stake: 5k CAMBIO', ETH, CAMBIO

  await disputeManager.setMinArbitratorReputation(800) // 800/1000
  console.log('✅ Min arbitrator reputation: 800')

  // Configurar rewards de arbitraje
  await disputeManager.setArbitratorReward(ethers.parseEther('50')) // 50 CAMBIO por disputa
  console.log('✅ Arbitrator reward: 50 CAMBIO')

  console.log('\n✅ Dispute manager configurado\n')

  // ============================================
  // 1️⃣1️⃣ CONFIGURAR REFERRAL SYSTEM
  // ============================================
  console.log('🎁 11. Configurando sistema de referidos...\n')

  const referralManager = await ethers.getContract('ReferralManager')

  // Configurar rewards por nivel
  await referralManager.setLevelReward(
    0, // Level 1 (directo)
    1000 // 10% de las fees
  )
  console.log('✅ Level 1 reward: 10%')

  await referralManager.setLevelReward(
    1, // Level 2
    500 // 5%
  )
  console.log('✅ Level 2 reward: 5%')

  await referralManager.setLevelReward(
    2, // Level 3
    200 // 2%
  )
  console.log('✅ Level 3 reward: 2%')

  console.log('\n✅ Sistema de referidos configurado\n')

  // ============================================
  // ✅ RESUMEN FINAL
  // ============================================
  console.log('=' .repeat(50))
  console.log('🎉 CONFIGURACIÓN COMPLETADA')
  console.log('=' .repeat(50))
  console.log('\n📋 Configurado:')
  console.log('✅ 1. Tokens (USDT, BUSD, WBNB, BTCB)')
  console.log('✅ 2. Fees (trading, staking, withdrawal, etc.)')
  console.log('✅ 3. KYC (5 tiers con límites)')
  console.log('✅ 4. Roles (ADMIN, OPERATOR, PAUSER)')
  console.log('✅ 5. Staking (5 pools: flexible + locked)')
  console.log('✅ 6. Oracles (pendiente: configurar pairs reales)')
  console.log('✅ 7. Límites (cooldowns, queue thresholds)')
  console.log('✅ 8. Intermediarios (stakes + collateral)')
  console.log('✅ 9. Bridges (fees + timeouts)')
  console.log('✅ 10. Dispute manager (arbitradores)')
  console.log('✅ 11. Referral system (rewards por nivel)')
  console.log('\n⚠️  PENDIENTES MANUALES:')
  console.log('- Configurar pairs de PancakeSwap en oracle')
  console.log('- Aprobar primeros validators/intermediaries')
  console.log('- Financiar treasury con tokens para rewards')
  console.log('- Testing exhaustivo de cada función')
  console.log('\n🚀 Sistema listo para testing en BSC Testnet!')
}

// ============================================
// FUNCIONES DE UTILIDAD
// ============================================

/**
 * Verificar configuración actual
 */
async function verifyConfiguration() {
  console.log('🔍 Verificando configuración...\n')

  const assetManager = await ethers.getContract('AssetManager')
  const feeManager = await ethers.getContract('FeeManager')
  const kycManager = await ethers.getContract('KYCManager')

  // Verificar tokens
  const tokenCount = await assetManager.supportedTokens.length
  console.log(`Tokens configurados: ${tokenCount}`)

  // Verificar fees
  const fees = await feeManager.fees()
  console.log(`Trading fee: ${fees.tradingFee / 100}%`)
  console.log(`Bridge fee: ${fees.bridgeFee / 100}%`)

  // Verificar KYC tiers
  const basicLimits = await kycManager.tierLimits(1)
  console.log(`\nKYC BASIC limits:`)
  console.log(`  Daily: ${ethers.formatEther(basicLimits.dailyLimit)} USD`)
  console.log(`  Monthly: ${ethers.formatEther(basicLimits.monthlyLimit)} USD`)
}

/**
 * Emergency: Pausar todo el sistema
 */
async function emergencyPauseAll() {
  console.log('🚨 PAUSING ALL CONTRACTS...\n')

  const contracts = [
    'P2PExchange',
    'P2PFiatExchange',
    'SwapRouter',
    'DepositManager',
    'WithdrawManager',
    'CryptoToFiatBridge',
    'FiatToCryptoBridge',
    'FiatToFiatBridge'
  ]

  for (const name of contracts) {
    const contract = await ethers.getContract(name)
    await contract.pause()
    console.log(`✅ ${name} paused`)
  }

  console.log('\n🛑 Sistema completamente pausado')
}

/**
 * Emergency: Despausar sistema
 */
async function emergencyUnpauseAll() {
  console.log('▶️  UNPAUSING ALL CONTRACTS...\n')

  const contracts = [
    'P2PExchange',
    'P2PFiatExchange',
    'SwapRouter',
    'DepositManager',
    'WithdrawManager',
    'CryptoToFiatBridge',
    'FiatToCryptoBridge',
    'FiatToFiatBridge'
  ]

  for (const name of contracts) {
    const contract = await ethers.getContract(name)
    await contract.unpause()
    console.log(`✅ ${name} unpaused`)
  }

  console.log('\n✅ Sistema activo')
}

// ============================================
// EXPORTAR FUNCIONES
// ============================================

module.exports = {
  configureSystem,
  verifyConfiguration,
  emergencyPauseAll,
  emergencyUnpauseAll
}

// Si se ejecuta directamente
if (require.main === module) {
  configureSystem()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error)
      process.exit(1)
    })
}
