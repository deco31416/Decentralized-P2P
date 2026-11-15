// ============================================
// 🪙 DEPLOYMENT COMPLETO DE TOKENS - BSC Testnet
// Incluye: Major cryptos + Stablecoins
// ============================================

const { ethers } = require('hardhat')
const fs = require('fs')
const path = require('path')

/**
 * TOKENS A CREAR:
 * 
 * MAJOR CRYPTOS:
 * - BTC, ETH, WBNB (ya estaban)
 * - WBTC, WLD, PEPE, CRV, AAVE, NOW, HYPE
 * 
 * STABLECOINS:
 * - USDT, USDC, DAI, FDUSD, USDD, PYUSD, OUSD, TUSD
 * 
 * GOVERNANCE:
 * - CAMBIO (token del proyecto)
 */

const TOKENS_CONFIG = [
  // ============================================
  // STABLECOINS (6 decimals como USDT real)
  // ============================================
  {
    name: 'Mock Tether USD',
    symbol: 'USDT',
    decimals: 6,
    initialSupply: '10000000', // 10M
    category: 'stablecoin'
  },
  {
    name: 'Mock USD Coin',
    symbol: 'USDC',
    decimals: 6,
    initialSupply: '10000000',
    category: 'stablecoin'
  },
  {
    name: 'Mock First Digital USD',
    symbol: 'FDUSD',
    decimals: 6,
    initialSupply: '10000000',
    category: 'stablecoin'
  },
  
  // ============================================
  // STABLECOINS (18 decimals)
  // ============================================
  {
    name: 'Mock Dai',
    symbol: 'DAI',
    decimals: 18,
    initialSupply: '10000000',
    category: 'stablecoin'
  },
  {
    name: 'Mock Decentralized USD',
    symbol: 'USDD',
    decimals: 18,
    initialSupply: '10000000',
    category: 'stablecoin'
  },
  {
    name: 'Mock PayPal USD',
    symbol: 'PYUSD',
    decimals: 6,
    initialSupply: '10000000',
    category: 'stablecoin'
  },
  {
    name: 'Mock Origin Dollar',
    symbol: 'OUSD',
    decimals: 18,
    initialSupply: '10000000',
    category: 'stablecoin'
  },
  {
    name: 'Mock TrueUSD',
    symbol: 'TUSD',
    decimals: 18,
    initialSupply: '10000000',
    category: 'stablecoin'
  },

  // ============================================
  // MAJOR CRYPTOS
  // ============================================
  {
    name: 'Mock Bitcoin',
    symbol: 'BTC',
    decimals: 8,
    initialSupply: '1000',
    category: 'major'
  },
  {
    name: 'Mock Wrapped Bitcoin',
    symbol: 'WBTC',
    decimals: 8,
    initialSupply: '1000',
    category: 'major'
  },
  {
    name: 'Mock Ethereum',
    symbol: 'ETH',
    decimals: 18,
    initialSupply: '10000',
    category: 'major'
  },

  // ============================================
  // DEFI & ALTCOINS
  // ============================================
  {
    name: 'Mock Worldcoin',
    symbol: 'WLD',
    decimals: 18,
    initialSupply: '1000000',
    category: 'altcoin'
  },
  {
    name: 'Mock Pepe',
    symbol: 'PEPE',
    decimals: 18,
    initialSupply: '420690000000000', // 420T (meme coin)
    category: 'altcoin'
  },
  {
    name: 'Mock Curve DAO',
    symbol: 'CRV',
    decimals: 18,
    initialSupply: '3000000000', // 3B
    category: 'altcoin'
  },
  {
    name: 'Mock Aave',
    symbol: 'AAVE',
    decimals: 18,
    initialSupply: '16000000', // 16M
    category: 'altcoin'
  },
  {
    name: 'Mock ChangeNOW',
    symbol: 'NOW',
    decimals: 8,
    initialSupply: '200000000', // 200M
    category: 'altcoin'
  },
  {
    name: 'Mock Hyperliquid',
    symbol: 'HYPE',
    decimals: 18,
    initialSupply: '1000000000', // 1B
    category: 'altcoin'
  },

  // ============================================
  // GOVERNANCE (Token del proyecto)
  // ============================================
  {
    name: 'CambiaCripto Token',
    symbol: 'CAMBIO',
    decimals: 18,
    initialSupply: '100000000', // 100M
    category: 'governance'
  }
]

async function main() {
  console.log('🪙 Deployando tokens completos en BSC Testnet...\n')

  const [deployer] = await ethers.getSigners()
  console.log(`Deployer: ${deployer.address}`)
  console.log(`Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} BNB\n`)

  const deployedTokens = {}
  const tokensByCategory = {
    stablecoin: [],
    major: [],
    altcoin: [],
    governance: []
  }

  // ============================================
  // DEPLOY MockWBNB (especial)
  // ============================================
  console.log('🔷 Deployando MockWBNB (Wrapped BNB)...')
  const MockWBNB = await ethers.getContractFactory('MockWBNB')
  const mockWBNB = await MockWBNB.deploy()
  await mockWBNB.waitForDeployment()
  const wbnbAddress = await mockWBNB.getAddress()
  deployedTokens.WBNB = wbnbAddress
  tokensByCategory.major.push('WBNB')
  console.log(`✅ WBNB: ${wbnbAddress}`)
  
  // Mint inicial de WBNB
  await mockWBNB.faucet(ethers.parseEther('100'))
  console.log(`   Minted: 100 WBNB al deployer\n`)

  // ============================================
  // DEPLOY TODOS LOS TOKENS ERC20
  // ============================================
  const MockERC20 = await ethers.getContractFactory('MockERC20')

  for (let i = 0; i < TOKENS_CONFIG.length; i++) {
    const config = TOKENS_CONFIG[i]
    const num = i + 1
    
    console.log(`${num}. Deployando ${config.symbol}...`)
    
    // Calcular supply según decimals
    let supply
    if (config.decimals === 6) {
      supply = ethers.parseUnits(config.initialSupply, 6)
    } else if (config.decimals === 8) {
      supply = ethers.parseUnits(config.initialSupply, 8)
    } else {
      supply = ethers.parseEther(config.initialSupply)
    }

    const token = await MockERC20.deploy(
      config.name,
      config.symbol,
      config.decimals,
      supply
    )
    await token.waitForDeployment()
    const address = await token.getAddress()
    
    deployedTokens[config.symbol] = address
    tokensByCategory[config.category].push(config.symbol)
    
    console.log(`✅ ${config.symbol}: ${address}`)
    console.log(`   Supply: ${config.initialSupply} ${config.symbol}`)
    console.log(`   Category: ${config.category}\n`)
  }

  // ============================================
  // GUARDAR ADDRESSES
  // ============================================
  console.log('💾 Guardando addresses...\n')

  const addressesPath = path.join(__dirname, '../deployed-tokens.json')
  fs.writeFileSync(
    addressesPath,
    JSON.stringify(deployedTokens, null, 2)
  )

  // Guardar también categorizado
  const categoriesPath = path.join(__dirname, '../token-categories.json')
  fs.writeFileSync(
    categoriesPath,
    JSON.stringify(tokensByCategory, null, 2)
  )

  console.log(`✅ Addresses guardadas en: deployed-tokens.json`)
  console.log(`✅ Categorías guardadas en: token-categories.json\n`)

  // ============================================
  // RESUMEN
  // ============================================
  console.log('=' .repeat(70))
  console.log('🎉 TOKENS DEPLOYADOS - RESUMEN')
  console.log('=' .repeat(70))

  console.log('\n💵 STABLECOINS (8):')
  tokensByCategory.stablecoin.forEach(symbol => {
    console.log(`   ${symbol.padEnd(10)} ${deployedTokens[symbol]}`)
  })

  console.log('\n🪙 MAJOR CRYPTOS (4):')
  tokensByCategory.major.forEach(symbol => {
    console.log(`   ${symbol.padEnd(10)} ${deployedTokens[symbol]}`)
  })

  console.log('\n🚀 ALTCOINS (6):')
  tokensByCategory.altcoin.forEach(symbol => {
    console.log(`   ${symbol.padEnd(10)} ${deployedTokens[symbol]}`)
  })

  console.log('\n🏛️  GOVERNANCE (1):')
  tokensByCategory.governance.forEach(symbol => {
    console.log(`   ${symbol.padEnd(10)} ${deployedTokens[symbol]}`)
  })

  console.log('\n📊 TOTAL: ' + Object.keys(deployedTokens).length + ' tokens\n')

  // ============================================
  // INSTRUCCIONES
  // ============================================
  console.log('=' .repeat(70))
  console.log('📝 PRÓXIMOS PASOS')
  console.log('=' .repeat(70))

  console.log('\n1️⃣  Agregar al .env (opcional):')
  Object.entries(deployedTokens).forEach(([symbol, address]) => {
    console.log(`   TOKEN_${symbol}=${address}`)
  })

  console.log('\n2️⃣  Deploy contratos principales:')
  console.log('   npx hardhat run scripts/deploy.js --network bsctestnet')

  console.log('\n3️⃣  Configurar tokens en AssetManager:')
  console.log('   npx hardhat run scripts/configure-tokens.js --network bsctestnet')

  console.log('\n4️⃣  Configurar fiat currencies (off-chain):')
  console.log('   npx hardhat run scripts/configure-fiat.js --network bsctestnet')

  console.log('\n💡 FAUCET: Obtén tokens gratis')
  console.log('   await token.faucet(ethers.parseEther("1000"))')

  console.log('\n✅ Deployment completado!\n')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
