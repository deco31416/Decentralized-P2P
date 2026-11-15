#!/bin/bash

# 🚀 QUICK START - CambiaCripto Beta
# Ejecuta este script para comenzar el Día 1

echo "🚀 CambiaCripto Beta - Quick Start Script"
echo "=========================================="
echo ""

# Check si estamos en el directorio correcto
if [ ! -f "package.json" ]; then
    echo "❌ Error: Ejecuta este script desde la raíz del proyecto"
    exit 1
fi

echo "📦 Paso 1/5: Instalando dependencias de testing..."
cd contratos || exit 1
npm install --save-dev @nomicfoundation/hardhat-chai-matchers chai
echo "✅ Dependencias instaladas"
echo ""

echo "📁 Paso 2/5: Creando estructura de tests..."
mkdir -p test
mkdir -p deployments
echo "✅ Carpetas creadas"
echo ""

echo "📝 Paso 3/5: Creando archivo de test básico..."
cat > test/P2PExchange.basic.test.js << 'EOF'
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("P2PExchange - Tests Básicos", function () {
  let p2pExchange, assetManager, tokenA, tokenB;
  let owner, maker, taker;

  beforeEach(async function () {
    [owner, maker, taker] = await ethers.getSigners();
    
    console.log("  Deploying test contracts...");
    
    // Deploy AssetManager
    const AssetManager = await ethers.getContractFactory("AssetManager");
    assetManager = await AssetManager.deploy();
    await assetManager.waitForDeployment();
    
    // Deploy mock tokens
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    tokenA = await MockERC20.deploy("Token A", "TKA", ethers.parseEther("1000000"));
    await tokenA.waitForDeployment();
    
    tokenB = await MockERC20.deploy("Token B", "TKB", ethers.parseEther("1000000"));
    await tokenB.waitForDeployment();
    
    console.log("  ✅ Test contracts deployed");
  });

  describe("Deployment", function () {
    it("Debe deployar correctamente", async function () {
      expect(await assetManager.getAddress()).to.be.properAddress;
      expect(await tokenA.getAddress()).to.be.properAddress;
      expect(await tokenB.getAddress()).to.be.properAddress;
    });
  });

  describe("AssetManager", function () {
    it("Debe tener roles configurados", async function () {
      const DEFAULT_ADMIN_ROLE = await assetManager.DEFAULT_ADMIN_ROLE();
      const hasRole = await assetManager.hasRole(DEFAULT_ADMIN_ROLE, owner.address);
      expect(hasRole).to.be.true;
    });
  });

  // TODO: Agregar más tests siguiendo los ejemplos en EJEMPLOS_CODIGO_SOLUCIONES.md
});
EOF
echo "✅ Archivo de test creado: test/P2PExchange.basic.test.js"
echo ""

echo "🔧 Paso 4/5: Verificando configuración de Hardhat..."
if npx hardhat compile > /dev/null 2>&1; then
    echo "✅ Compilación exitosa"
else
    echo "⚠️  Warning: Hay errores de compilación. Revisa los contratos."
fi
echo ""

echo "🧪 Paso 5/5: Ejecutando tests de prueba..."
echo ""
npx hardhat test
echo ""

echo "=================================================="
echo "✅ Setup completado!"
echo ""
echo "📋 Próximos pasos (Día 1):"
echo "1. Revisar test/P2PExchange.basic.test.js"
echo "2. Agregar más tests desde EJEMPLOS_CODIGO_SOLUCIONES.md"
echo "3. Ejecutar: npx hardhat test"
echo "4. Target: 50% coverage en P2PExchange"
echo ""
echo "📖 Sigue el plan completo en: PLAN_2_SEMANAS_BETA.md"
echo "=================================================="
