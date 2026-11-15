/**
 * @title Script de Aprobación de Intermediarios
 * @notice Aprueba intermediarios y les permite configurar sus comisiones
 * @dev Requiere deployments.json con direcciones de contratos
 *
 * Uso:
 *   node scripts/approve-intermediaries.js <network> <intermediary_address> [entry_fee%] [exit_fee%]
 *
 * Ejemplos:
 *   node scripts/approve-intermediaries.js bscTestnet 0x123... 5 8
 *   node scripts/approve-intermediaries.js bsc 0x456... 4 7
 */

const hre = require('hardhat')
const fs = require('fs')
const path = require('path')

async function main() {
  const [admin] = await hre.ethers.getSigners()
  const network = process.argv[2] || hre.network.name
  const intermediaryAddress = process.argv[3]
  const entryFeeUSD = process.argv[4] || 5 // Default 5%
  const exitFeeCOP = process.argv[5] || 8 // Default 8%

  if (!intermediaryAddress) {
    console.error('❌ Error: Intermediary address required')
    console.log('\nUsage:')
    console.log('  node scripts/approve-intermediaries.js <network> <intermediary_address> [entry_fee%] [exit_fee%]')
    console.log('\nExample:')
    console.log('  node scripts/approve-intermediaries.js bscTestnet 0x1234567890123456789012345678901234567890 5 8')
    process.exit(1)
  }

  console.log('🔐 Approving Intermediary...')
  console.log('📍 Network:', network)
  console.log('👤 Admin:', admin.address)
  console.log('🏦 Intermediary:', intermediaryAddress)
  console.log('💵 Entry Fee (USD):', entryFeeUSD + '%')
  console.log('💵 Exit Fee (COP):', exitFeeCOP + '%\n')

  // Cargar deployments
  const deploymentsPath = path.join(__dirname, '../deployments.json')
  if (!fs.existsSync(deploymentsPath)) {
    console.error('❌ deployments.json not found. Run deploy-fiat-p2p.js first.')
    process.exit(1)
  }

  const allDeployments = JSON.parse(fs.readFileSync(deploymentsPath, 'utf8'))
  const deployment = allDeployments[network]

  if (!deployment) {
    console.error(`❌ No deployment found for network: ${network}`)
    process.exit(1)
  }

  // Cargar contratos
  const FiatFeeManager = await hre.ethers.getContractFactory('FiatFeeManager')
  const fiatFeeManager = FiatFeeManager.attach(deployment.contracts.FiatFeeManager)

  // ==============================================
  // 1️⃣ APROBAR INTERMEDIARIO (KYC)
  // ==============================================
  console.log('✅ Step 1: Approving intermediary...')
  let tx = await fiatFeeManager.approveIntermediary(intermediaryAddress)
  await tx.wait()
  console.log('✅ Intermediary approved (KYC passed)\n')

  // ==============================================
  // 2️⃣ CONFIGURAR COMISIONES DEL INTERMEDIARIO
  // ==============================================
  console.log('💸 Step 2: Setting intermediary fees...')

  // Configurar comisión entrada (USD)
  console.log(`  Setting USD entry fee: ${entryFeeUSD}%`)
  tx = await fiatFeeManager.setIntermediaryFee(intermediaryAddress, 'USD', entryFeeUSD)
  await tx.wait()

  // Configurar comisión salida (COP)
  console.log(`  Setting COP exit fee: ${exitFeeCOP}%`)
  tx = await fiatFeeManager.setIntermediaryFee(intermediaryAddress, 'COP', exitFeeCOP)
  await tx.wait()

  console.log('✅ Intermediary fees configured\n')

  // ==============================================
  // 3️⃣ VERIFICAR CONFIGURACIÓN
  // ==============================================
  console.log('🔍 Step 3: Verifying configuration...')

  const isApproved = await fiatFeeManager.isApprovedIntermediary(intermediaryAddress)
  const maxUSDFee = await fiatFeeManager.getMaxFiatFee('USD')
  const maxCOPFee = await fiatFeeManager.getMaxFiatFee('COP')
  const intermediaryUSDFee = await fiatFeeManager.getIntermediaryFee(intermediaryAddress, 'USD')
  const intermediaryCOPFee = await fiatFeeManager.getIntermediaryFee(intermediaryAddress, 'COP')

  console.log('\n' + '='.repeat(60))
  console.log('✅ INTERMEDIARY APPROVED SUCCESSFULLY!')
  console.log('='.repeat(60))
  console.log('\n📊 Configuration Summary:')
  console.log('  Intermediary:', intermediaryAddress)
  console.log('  Approved:', isApproved ? '✅ YES' : '❌ NO')
  console.log('\n  USD Fees:')
  console.log('    Max allowed:', maxUSDFee + '%')
  console.log('    Intermediary:', intermediaryUSDFee + '% (entrada)')
  console.log('\n  COP Fees:')
  console.log('    Max allowed:', maxCOPFee + '%')
  console.log('    Intermediary:', intermediaryCOPFee + '% (salida)')

  // Calcular ejemplo
  const testAmount = 1000 // $1000 USD
  console.log('\n💰 Fee Calculation Example ($1000 USD → COP):')
  console.log('  1. Usuario envía: $1000 USD')
  console.log(`  2. Comisión entrada (${intermediaryUSDFee}%): $${(testAmount * intermediaryUSDFee) / 100} USD`)
  console.log(`  3. USDT después de entrada: $${testAmount - (testAmount * intermediaryUSDFee) / 100} USDT`)
  const afterEntry = testAmount - (testAmount * intermediaryUSDFee) / 100
  console.log(`  4. Comisión salida (${intermediaryCOPFee}%): $${(afterEntry * intermediaryCOPFee) / 100} USDT`)
  const totalFees = (testAmount * intermediaryUSDFee) / 100 + (afterEntry * intermediaryCOPFee) / 100
  console.log(`  5. ✅ Total fees: $${totalFees} USDT`)
  console.log(`  6. ✅ Net to intermediary: $${testAmount - totalFees} USDT\n`)

  console.log('🎉 Intermediary can now accept orders!')
  console.log('='.repeat(60) + '\n')
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Error:', error)
    process.exit(1)
  })
