// ============================================
// 💵 CONFIGURACIÓN DE FIAT CURRENCIES
// Para P2P Fiat Exchange (off-chain)
// ============================================

const { ethers } = require('hardhat')

/**
 * FIAT NO van en blockchain como tokens.
 * Se configuran como FiatPaymentMethod en AssetManager.
 * 
 * Estructura:
 * - name: Nombre del método de pago
 * - code: Código de la moneda (USD, EUR, etc.)
 * - paymentType: BankTransfer, Cash, MobileMoney, etc.
 * - supportedCountries: Array de códigos de país
 * - supportedCurrencies: Array de monedas soportadas
 */

const FIAT_CURRENCIES = [
  // ============================================
  // AMÉRICA
  // ============================================
  {
    name: 'US Dollar',
    code: 'USD',
    countries: ['US'],
    paymentTypes: ['BankTransfer', 'Zelle', 'Venmo', 'CashApp', 'Cash'],
    minAmount: '10',
    maxAmount: '100000',
    processingTime: 3600, // 1 hora
    fee: 30 // 0.3%
  },
  {
    name: 'Canadian Dollar',
    code: 'CAD',
    countries: ['CA'],
    paymentTypes: ['BankTransfer', 'Interac', 'Cash'],
    minAmount: '10',
    maxAmount: '100000',
    processingTime: 3600,
    fee: 30
  },
  {
    name: 'Mexican Peso',
    code: 'MXN',
    countries: ['MX'],
    paymentTypes: ['BankTransfer', 'SPEI', 'Oxxo', 'Cash'],
    minAmount: '200',
    maxAmount: '2000000',
    processingTime: 1800,
    fee: 30
  },
  {
    name: 'Brazilian Real',
    code: 'BRL',
    countries: ['BR'],
    paymentTypes: ['BankTransfer', 'PIX', 'Cash'],
    minAmount: '50',
    maxAmount: '500000',
    processingTime: 1800,
    fee: 30
  },
  {
    name: 'Argentine Peso',
    code: 'ARS',
    countries: ['AR'],
    paymentTypes: ['BankTransfer', 'MercadoPago', 'Cash'],
    minAmount: '1000',
    maxAmount: '10000000',
    processingTime: 3600,
    fee: 50 // Mayor fee por volatilidad
  },
  {
    name: 'Chilean Peso',
    code: 'CLP',
    countries: ['CL'],
    paymentTypes: ['BankTransfer', 'Cash'],
    minAmount: '10000',
    maxAmount: '100000000',
    processingTime: 3600,
    fee: 30
  },
  {
    name: 'Colombian Peso',
    code: 'COP',
    countries: ['CO'],
    paymentTypes: ['BankTransfer', 'Nequi', 'Daviplata', 'Cash'],
    minAmount: '50000',
    maxAmount: '500000000',
    processingTime: 1800,
    fee: 30
  },
  {
    name: 'Peruvian Sol',
    code: 'PEN',
    countries: ['PE'],
    paymentTypes: ['BankTransfer', 'Yape', 'Plin', 'Cash'],
    minAmount: '40',
    maxAmount: '400000',
    processingTime: 1800,
    fee: 30
  },
  {
    name: 'Venezuelan Bolívar',
    code: 'VES',
    countries: ['VE'],
    paymentTypes: ['BankTransfer', 'MobilePay', 'Cash'],
    minAmount: '100',
    maxAmount: '10000000',
    processingTime: 7200, // 2 horas (volatilidad)
    fee: 100 // 1% por alta volatilidad
  },
  {
    name: 'Dominican Peso',
    code: 'DOP',
    countries: ['DO'],
    paymentTypes: ['BankTransfer', 'Cash'],
    minAmount: '500',
    maxAmount: '5000000',
    processingTime: 3600,
    fee: 30
  },
  {
    name: 'Salvadoran Colón',
    code: 'SVC',
    countries: ['SV'],
    paymentTypes: ['BankTransfer', 'Cash'],
    minAmount: '10',
    maxAmount: '100000',
    processingTime: 3600,
    fee: 30
  },
  {
    name: 'Aruban Florin',
    code: 'AWG',
    countries: ['AW'],
    paymentTypes: ['BankTransfer', 'Cash'],
    minAmount: '20',
    maxAmount: '200000',
    processingTime: 3600,
    fee: 30
  },

  // ============================================
  // EUROPA
  // ============================================
  {
    name: 'Euro',
    code: 'EUR',
    countries: ['ES', 'FR', 'DE', 'IT', 'PT', 'NL', 'BE', 'AT', 'IE', 'GR'],
    paymentTypes: ['BankTransfer', 'SEPA', 'Cash'],
    minAmount: '10',
    maxAmount: '100000',
    processingTime: 3600,
    fee: 30
  }
]

async function main() {
  console.log('💵 Configurando fiat currencies en BSC Testnet...\n')

  const [deployer] = await ethers.getSigners()
  console.log(`Deployer: ${deployer.address}\n`)

  // Obtener AssetManager
  const assetManager = await ethers.getContract('AssetManager')
  console.log(`AssetManager: ${await assetManager.getAddress()}\n`)

  // ============================================
  // CONFIGURAR CADA FIAT CURRENCY
  // ============================================
  console.log('Configurando fiat payment methods...\n')

  for (let i = 0; i < FIAT_CURRENCIES.length; i++) {
    const fiat = FIAT_CURRENCIES[i]
    const num = i + 1

    console.log(`${num}. Configurando ${fiat.code} (${fiat.name})...`)

    // Convertir amounts a formato correcto
    const minAmount = ethers.parseEther(fiat.minAmount)
    const maxAmount = ethers.parseEther(fiat.maxAmount)

    // Por cada tipo de pago
    for (const paymentType of fiat.paymentTypes) {
      const methodName = `${fiat.code}-${paymentType}`
      
      try {
        await assetManager.addFiatPaymentMethod(
          methodName,
          fiat.code,
          paymentType,
          fiat.countries,
          [fiat.code], // supportedCurrencies
          minAmount,
          maxAmount,
          fiat.processingTime,
          fiat.fee,
          true // isActive
        )
        console.log(`   ✅ ${methodName}`)
      } catch (error) {
        console.log(`   ⚠️  ${methodName} - ${error.message}`)
      }
    }
    console.log()
  }

  // ============================================
  // RESUMEN
  // ============================================
  console.log('=' .repeat(70))
  console.log('✅ FIAT CURRENCIES CONFIGURADAS')
  console.log('=' .repeat(70))

  console.log('\n🌎 AMÉRICA (12):')
  console.log('   USD (US Dollar) - 5 métodos')
  console.log('   CAD (Canadian Dollar) - 3 métodos')
  console.log('   MXN (Mexican Peso) - 4 métodos')
  console.log('   BRL (Brazilian Real) - 3 métodos')
  console.log('   ARS (Argentine Peso) - 3 métodos')
  console.log('   CLP (Chilean Peso) - 2 métodos')
  console.log('   COP (Colombian Peso) - 4 métodos')
  console.log('   PEN (Peruvian Sol) - 4 métodos')
  console.log('   VES (Venezuelan Bolívar) - 3 métodos')
  console.log('   DOP (Dominican Peso) - 2 métodos')
  console.log('   SVC (Salvadoran Colón) - 2 métodos')
  console.log('   AWG (Aruban Florin) - 2 métodos')

  console.log('\n🇪🇺 EUROPA (1):')
  console.log('   EUR (Euro) - 3 métodos - 10 países')

  console.log('\n📊 TOTAL: 13 fiat currencies')
  console.log('📊 MÉTODOS DE PAGO: ~40 combinaciones\n')

  console.log('=' .repeat(70))
  console.log('📝 NOTA IMPORTANTE')
  console.log('=' .repeat(70))
  console.log('\n⚠️  FIAT es OFF-CHAIN:')
  console.log('   - NO son tokens en blockchain')
  console.log('   - NO se pueden transferir con transfer()')
  console.log('   - Se manejan a través de P2PFiatExchange')
  console.log('   - Requieren intermediarios para validar pagos')

  console.log('\n💡 CÓMO FUNCIONA:')
  console.log('   1. Usuario crea oferta P2P fiat')
  console.log('   2. Comprador acepta oferta')
  console.log('   3. Comprador paga con método configurado (Zelle, SPEI, etc.)')
  console.log('   4. Intermediario valida pago off-chain')
  console.log('   5. Smart contract libera crypto al comprador')

  console.log('\n🔄 PARA AGREGAR MÁS FIAT:')
  console.log('   await assetManager.addFiatPaymentMethod(...)')

  console.log('\n✅ Configuración completada!\n')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
