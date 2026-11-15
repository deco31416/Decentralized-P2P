# 🚀 CambiaCripto Beta - Quick Start Script (Windows)
# Ejecuta este script para comenzar el Día 1

Write-Host "🚀 CambiaCripto Beta - Quick Start Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check si estamos en el directorio correcto
if (-not (Test-Path "package.json")) {
    Write-Host "❌ Error: Ejecuta este script desde la raíz del proyecto" -ForegroundColor Red
    exit 1
}

Write-Host "📦 Paso 1/5: Instalando dependencias de testing..." -ForegroundColor Yellow
Set-Location contratos
npm install --save-dev @nomicfoundation/hardhat-chai-matchers chai
Write-Host "✅ Dependencias instaladas" -ForegroundColor Green
Write-Host ""

Write-Host "📁 Paso 2/5: Creando estructura de tests..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path test | Out-Null
New-Item -ItemType Directory -Force -Path deployments | Out-Null
Write-Host "✅ Carpetas creadas" -ForegroundColor Green
Write-Host ""

Write-Host "📝 Paso 3/5: Creando archivo de test básico..." -ForegroundColor Yellow
$testContent = @'
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
    
    console.log("  ✅ Test contracts deployed");
  });

  describe("Deployment", function () {
    it("Debe deployar correctamente", async function () {
      expect(await assetManager.getAddress()).to.be.properAddress;
    });
  });

  describe("AssetManager", function () {
    it("Debe tener roles configurados", async function () {
      const DEFAULT_ADMIN_ROLE = await assetManager.DEFAULT_ADMIN_ROLE();
      const hasRole = await assetManager.hasRole(DEFAULT_ADMIN_ROLE, owner.address);
      expect(hasRole).to.be.true;
    });
  });

  // TODO: Agregar más tests siguiendo EJEMPLOS_CODIGO_SOLUCIONES.md
});
'@
Set-Content -Path "test/P2PExchange.basic.test.js" -Value $testContent
Write-Host "✅ Archivo de test creado: test/P2PExchange.basic.test.js" -ForegroundColor Green
Write-Host ""

Write-Host "🔧 Paso 4/5: Verificando configuración de Hardhat..." -ForegroundColor Yellow
try {
    npx hardhat compile 2>&1 | Out-Null
    Write-Host "✅ Compilación exitosa" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Warning: Hay errores de compilación. Revisa los contratos." -ForegroundColor Yellow
}
Write-Host ""

Write-Host "🧪 Paso 5/5: Ejecutando tests de prueba..." -ForegroundColor Yellow
Write-Host ""
npx hardhat test
Write-Host ""

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "✅ Setup completado!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Próximos pasos (Día 1):" -ForegroundColor Yellow
Write-Host "1. Revisar test/P2PExchange.basic.test.js"
Write-Host "2. Agregar más tests desde EJEMPLOS_CODIGO_SOLUCIONES.md"
Write-Host "3. Ejecutar: npx hardhat test"
Write-Host "4. Target: 50% coverage en P2PExchange"
Write-Host ""
Write-Host "📖 Sigue el plan completo en: PLAN_2_SEMANAS_BETA.md" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

Set-Location ..
