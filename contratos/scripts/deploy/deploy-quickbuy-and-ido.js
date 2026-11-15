// scripts/deploy/deploy-quickbuy-and-ido.js

const hre = require("hardhat");

/**
 * Script de deployment para QuickBuyManager e IDOManager
 * 
 * QuickBuyManager: Sistema de liquidez de la plataforma con usuarios preferenciales
 * IDOManager: Sistema completo de Initial DEX Offerings
 * 
 * Versión: v2.2.0
 * Chain: BSC Mainnet/Testnet
 */

async function main() {
  console.log("\n📦 ========================================");
  console.log("🚀 DEPLOYMENT: QuickBuy + IDO System v2.2.0");
  console.log("📦 ========================================\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("🔑 Deploying contracts with account:", deployer.address);
  console.log("💰 Account balance:", (await deployer.getBalance()).toString(), "\n");

  // ============================================
  // CONFIGURACIÓN
  // ============================================

  // Direcciones de contratos existentes (actualizar según red)
  const BALANCE_MANAGER = process.env.BALANCE_MANAGER_ADDRESS || "0x0000000000000000000000000000000000000000";
  
  // Wallet de la plataforma (market maker)
  const PLATFORM_WALLET = process.env.PLATFORM_WALLET || deployer.address;
  
  // Fee collector para IDO
  const FEE_COLLECTOR = process.env.FEE_COLLECTOR || deployer.address;

  // Verificar configuración
  if (BALANCE_MANAGER === "0x0000000000000000000000000000000000000000") {
    console.log("⚠️  WARNING: BALANCE_MANAGER not configured, using zero address");
  }

  console.log("📋 Configuration:");
  console.log("   Platform Wallet:", PLATFORM_WALLET);
  console.log("   Fee Collector:", FEE_COLLECTOR);
  console.log("   Balance Manager:", BALANCE_MANAGER);
  console.log("");

  // ============================================
  // 1. DEPLOY QUICKBUY MANAGER
  // ============================================

  console.log("📦 [1/2] Deploying QuickBuyManager...");
  const QuickBuyManager = await hre.ethers.getContractFactory("QuickBuyManager");
  const quickBuyManager = await QuickBuyManager.deploy(
    deployer.address,  // admin
    PLATFORM_WALLET,   // platformWallet
    BALANCE_MANAGER    // balanceManager
  );
  await quickBuyManager.deployed();
  console.log("✅ QuickBuyManager deployed to:", quickBuyManager.address);
  console.log("");

  // ============================================
  // 2. DEPLOY IDO MANAGER
  // ============================================

  console.log("📦 [2/2] Deploying IDOManager...");
  const IDOManager = await hre.ethers.getContractFactory("IDOManager");
  const idoManager = await IDOManager.deploy(
    deployer.address,  // admin
    FEE_COLLECTOR      // feeCollector
  );
  await idoManager.deployed();
  console.log("✅ IDOManager deployed to:", idoManager.address);
  console.log("");

  // ============================================
  // 3. CONFIGURACIÓN INICIAL
  // ============================================

  console.log("⚙️  Initial Configuration...\n");

  // QuickBuy: Crear ofertas de liquidez de ejemplo
  console.log("📝 [3/3] Creating sample platform offers...");
  
  // Dirección de tokens (actualizar según red)
  const USDT = "0x55d398326f99059fF775485246999027B3197955"; // BSC Mainnet USDT
  const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"; // BSC Mainnet BUSD
  
  try {
    // Oferta 1: USDT → BUSD (1:1 con 0.5% spread)
    const tx1 = await quickBuyManager.createPlatformOffer(
      USDT,                       // tokenSell
      BUSD,                       // tokenBuy
      hre.ethers.utils.parseEther("1"),    // rate (1:1)
      50,                         // spreadBps (0.5%)
      hre.ethers.utils.parseEther("100"),  // minAmount ($100)
      hre.ethers.utils.parseEther("10000"), // maxAmount ($10,000)
      hre.ethers.utils.parseEther("100000") // dailyLimit ($100,000)
    );
    await tx1.wait();
    console.log("   ✅ Offer 1: USDT → BUSD created");

    // Oferta 2: BUSD → USDT (1:1 con 0.5% spread)
    const tx2 = await quickBuyManager.createPlatformOffer(
      BUSD,                       // tokenSell
      USDT,                       // tokenBuy
      hre.ethers.utils.parseEther("1"),    // rate (1:1)
      50,                         // spreadBps (0.5%)
      hre.ethers.utils.parseEther("100"),  // minAmount ($100)
      hre.ethers.utils.parseEther("10000"), // maxAmount ($10,000)
      hre.ethers.utils.parseEther("100000") // dailyLimit ($100,000)
    );
    await tx2.wait();
    console.log("   ✅ Offer 2: BUSD → USDT created");

    console.log("   ✅ Sample offers created successfully");
  } catch (error) {
    console.log("   ⚠️  Could not create sample offers (update token addresses for your network)");
  }

  console.log("");

  // ============================================
  // 4. RESUMEN
  // ============================================

  console.log("\n✅ ========================================");
  console.log("🎉 DEPLOYMENT SUCCESSFUL!");
  console.log("✅ ========================================\n");

  console.log("📋 Deployed Contracts:");
  console.log("┌────────────────────────────────────────────────┐");
  console.log("│ QuickBuyManager                                 │");
  console.log("│ Address:", quickBuyManager.address.padEnd(37), "│");
  console.log("├────────────────────────────────────────────────┤");
  console.log("│ IDOManager                                      │");
  console.log("│ Address:", idoManager.address.padEnd(37), "│");
  console.log("└────────────────────────────────────────────────┘");
  console.log("");

  console.log("📝 Configuration Summary:");
  console.log("   QuickBuy - Platform Wallet:", PLATFORM_WALLET);
  console.log("   QuickBuy - Balance Manager:", BALANCE_MANAGER);
  console.log("   IDO - Fee Collector:", FEE_COLLECTOR);
  console.log("   IDO - Platform Fee:", "3% (300 bps)");
  console.log("");

  console.log("🔧 Next Steps:");
  console.log("   1. Verify contracts on BSCScan");
  console.log("   2. Grant roles to operators");
  console.log("   3. Add preferred users to QuickBuy whitelist");
  console.log("   4. Configure tier caps and staking requirements");
  console.log("   5. Create first IDO pool");
  console.log("   6. Update frontend with new contract addresses");
  console.log("");

  console.log("📚 Verification Commands:");
  console.log(`   npx hardhat verify --network bscMainnet ${quickBuyManager.address} "${deployer.address}" "${PLATFORM_WALLET}" "${BALANCE_MANAGER}"`);
  console.log(`   npx hardhat verify --network bscMainnet ${idoManager.address} "${deployer.address}" "${FEE_COLLECTOR}"`);
  console.log("");

  // Guardar direcciones en archivo
  const fs = require("fs");
  const deploymentInfo = {
    network: hre.network.name,
    timestamp: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      QuickBuyManager: {
        address: quickBuyManager.address,
        platformWallet: PLATFORM_WALLET,
        balanceManager: BALANCE_MANAGER
      },
      IDOManager: {
        address: idoManager.address,
        feeCollector: FEE_COLLECTOR,
        platformFeeBps: 300
      }
    }
  };

  fs.writeFileSync(
    `deployments/quickbuy-ido-${hre.network.name}-${Date.now()}.json`,
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log("💾 Deployment info saved to deployments/ folder");
  console.log("");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
