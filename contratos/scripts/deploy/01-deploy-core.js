const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

/**
 * FASE 1: CORE INFRASTRUCTURE
 * 
 * Contratos a deployar:
 * 1. TokenManager (CAMBIO token)
 * 2. Treasury
 * 3. UserRegistry
 * 4. KYCManager
 * 5. FeeCalculator
 * 6. NotificationManager
 * 7. AuditLogger
 */

async function main() {
  console.log("\n🚀 FASE 1: Deploying Core Infrastructure...\n");

  const [deployer, operator, admin] = await hre.ethers.getSigners();
  
  console.log("📍 Deploying from:", deployer.address);
  console.log("💰 Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "BNB\n");

  const deployedContracts = {};

  // 1. Deploy CAMBIO Token
  console.log("1️⃣  Deploying TokenManager (CAMBIO)...");
  const TokenManager = await hre.ethers.getContractFactory("TokenManager");
  const tokenManager = await TokenManager.deploy(
    "Cambio Token",
    "CAMBIO",
    process.env.INITIAL_SUPPLY || "1000000000000000000000000000" // 1B tokens
  );
  await tokenManager.waitForDeployment();
  deployedContracts.TokenManager = await tokenManager.getAddress();
  console.log("✅ TokenManager deployed:", deployedContracts.TokenManager, "\n");

  // 2. Deploy Treasury
  console.log("2️⃣  Deploying Treasury...");
  const Treasury = await hre.ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy(
    deployedContracts.TokenManager,
    deployer.address
  );
  await treasury.waitForDeployment();
  deployedContracts.Treasury = await treasury.getAddress();
  console.log("✅ Treasury deployed:", deployedContracts.Treasury, "\n");

  // 3. Deploy UserRegistry
  console.log("3️⃣  Deploying UserRegistry...");
  const UserRegistry = await hre.ethers.getContractFactory("UserRegistry");
  const userRegistry = await UserRegistry.deploy(deployer.address);
  await userRegistry.waitForDeployment();
  deployedContracts.UserRegistry = await userRegistry.getAddress();
  console.log("✅ UserRegistry deployed:", deployedContracts.UserRegistry, "\n");

  // 4. Deploy KYCManager
  console.log("4️⃣  Deploying KYCManager...");
  const KYCManager = await hre.ethers.getContractFactory("KYCManager");
  const kycManager = await KYCManager.deploy(
    deployedContracts.UserRegistry,
    deployer.address
  );
  await kycManager.waitForDeployment();
  deployedContracts.KYCManager = await kycManager.getAddress();
  console.log("✅ KYCManager deployed:", deployedContracts.KYCManager, "\n");

  // 5. Deploy FeeCalculator
  console.log("5️⃣  Deploying FeeCalculator...");
  const FeeCalculator = await hre.ethers.getContractFactory("FeeCalculator");
  const feeCalculator = await FeeCalculator.deploy(
    deployedContracts.Treasury,
    deployer.address
  );
  await feeCalculator.waitForDeployment();
  deployedContracts.FeeCalculator = await feeCalculator.getAddress();
  console.log("✅ FeeCalculator deployed:", deployedContracts.FeeCalculator, "\n");

  // 6. Deploy NotificationManager
  console.log("6️⃣  Deploying NotificationManager...");
  const NotificationManager = await hre.ethers.getContractFactory("NotificationManager");
  const notificationManager = await NotificationManager.deploy(deployer.address);
  await notificationManager.waitForDeployment();
  deployedContracts.NotificationManager = await notificationManager.getAddress();
  console.log("✅ NotificationManager deployed:", deployedContracts.NotificationManager, "\n");

  // 7. Deploy AuditLogger
  console.log("7️⃣  Deploying AuditLogger...");
  const AuditLogger = await hre.ethers.getContractFactory("AuditLogger");
  const auditLogger = await AuditLogger.deploy(deployer.address);
  await auditLogger.waitForDeployment();
  deployedContracts.AuditLogger = await auditLogger.getAddress();
  console.log("✅ AuditLogger deployed:", deployedContracts.AuditLogger, "\n");

  // Save deployment addresses
  const networkName = hre.network.name;
  const deploymentsDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  const deploymentFile = path.join(deploymentsDir, `${networkName}-core.json`);
  fs.writeFileSync(
    deploymentFile,
    JSON.stringify({
      network: networkName,
      chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      contracts: deployedContracts
    }, null, 2)
  );

  console.log("✅ FASE 1 completed!");
  console.log("📄 Deployment addresses saved to:", deploymentFile);
  console.log("\n📋 Summary:");
  console.log(JSON.stringify(deployedContracts, null, 2));
  console.log("\n🔄 Next step: Run deploy:exchange:testnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
