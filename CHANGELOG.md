# 📌 Changelog - CambiaCripto Dashboard


> **Nota de vigencia:** este changelog conserva notas de desarrollo heredadas. Las versiones, fechas y funcionalidades descritas no se han verificado contra el estado actual; consulta el README y la documentación vigente antes de tomarlas como release notes.


Este archivo documenta los cambios realizados y las tareas pendientes en el desarrollo del Dashboard de CambiaCripto.

---

## [v1.2.0] - 8 de febrero de 2026

### Frontend (Next.js App Router)

- Performance: widgets del dashboard divididos por chunks con `next/dynamic` y skeletons.
- Layout: refactor a shell server + islas cliente (Sidebar/Header) para evitar bloqueos de render y mejorar TTFB percibido.
- Hydration: fix de mismatch en el boton de tema (render estable en SSR).
- Toasts: `Toaster` global para que los `toast()` funcionen en toda la app.
- Charts: removido Recharts y reemplazado por graficos ligeros SVG/HTML.

### Dev (Windows)

- Scripts: `dev:clean` para limpiar `.next` cuando queda corrupto.
- Recomendacion: no ejecutar `build` mientras corre `dev`.

## 🎉 **[v1.3.0] - 7 de enero de 2026**

### 📦 **Asset Management System**

#### ✅ **AssetManager.sol (850 líneas)**

**Sistema Centralizado de Gestión de Activos**

- ✅ Whitelist centralizada de tokens ERC20 (crypto + stablecoins)
- ✅ Registro de métodos de pago fiat con configuración completa
- ✅ Categorización de tokens: Cryptocurrency, Stablecoin, Utility, Synthetic
- ✅ Tipos de métodos fiat: BankTransfer, Cash, MobilePayment, OnlineWallet
- ✅ Límites configurables por token (min/max deposit/withdraw, límites diarios)
- ✅ Permisos granulares por token (canDeposit, canWithdraw, canTrade, canStake)
- ✅ Metadatos completos (logo, website, verificación)
- ✅ Indexación de métodos fiat por país, moneda y tipo
- ✅ Sistema de roles: ADMIN, ASSET_MANAGER, PAYMENT_MANAGER, OPERATOR

**Roles y Permisos**

```
ADMIN_ROLE: Puede gestionar TODO (tokens + métodos fiat)
ASSET_MANAGER_ROLE: Solo tokens crypto/stable
PAYMENT_MANAGER_ROLE: Solo métodos de pago fiat
OPERATOR_ROLE: Activar/desactivar temporalmente
```

**Funciones Principales**

- `addToken()` - Agregar nuevo token crypto/stablecoin
- `addFiatMethod()` - Agregar método de pago fiat
- `setTokenLimits()` - Configurar límites de depósito/retiro
- `updateTokenPermissions()` - Cambiar permisos (deposit, withdraw, trade, stake)
- `verifyToken()` - Marcar token como verificado
- `getActiveFiatMethods()` - Listar métodos de pago activos
- `getMethodsByCountry()` - Filtrar métodos por país
- `canTokenBeTraded()` - Verificar si token puede tradearse

#### 🔗 **Integraciones Realizadas**

**BalanceManager.sol**

- ✅ Consulta AssetManager antes de aceptar tokens
- ✅ Fallback a whitelist local si AssetManager no configurado
- ✅ Función `setAssetManager()` agregada

**P2PExchange.sol**

- ✅ Valida que tokens puedan ser tradeados antes de crear ofertas
- ✅ Verifica ambos tokens (offered y wanted) con `canTokenBeTraded()`
- ✅ Función `setAssetManager()` agregada

**DepositManager.sol**

- ✅ Valida con AssetManager antes de aceptar depósitos
- ✅ Verifica `canTokenBeDeposited()` y límites min/max
- ✅ Doble validación: TokenConfig local + AssetManager
- ✅ Referencia a AssetManager agregada

**WithdrawManager.sol**

- ✅ Valida con AssetManager antes de procesar retiros
- ✅ Verifica `canTokenBeWithdrawn()` y límites min/max
- ✅ Validación de límites diarios desde AssetManager
- ✅ Referencia a AssetManager agregada

**FiatToCryptoBridge.sol**

- ✅ Valida tokens crypto antes de crear ofertas
- ✅ Nota: Métodos de pago fiat se validan en frontend
- ✅ Referencia a AssetManager agregada

**IAssetManager.sol (Interface)**

- ✅ Interface completa para integración con otros contratos
- ✅ Structs: TokenInfo, FiatPaymentMethod
- ✅ Enums: TokenCategory, FiatPaymentType
- ✅ View functions para consultas

#### 📊 **Estadísticas Finales v1.3.0**

```
✅ 45/45 contratos implementados (100%)
✅ 35,863 líneas de código Solidity
✅ 11 fases completadas
✅ Sistema totalmente integrado
```

**Arquitectura Actualizada:**

```
Core: 7 | Exchange: 4 | Bridges: 5 | Managers: 8 ⭐
Features: 10 | Oracles: 1 | Interfaces: 1 ⭐ | Helpers: 3
Mocks: 3 | Storage: 6
```

#### 📝 **Documentación**

- ✅ `ASSET_MANAGEMENT.md` - Guía completa del sistema
- ✅ Ejemplos de uso para cada rol
- ✅ Casos de uso detallados
- ✅ Guía de deployment
- ✅ Integraciones documentadas

---

## 🎉 **[v1.2.0] - 7 de enero de 2026**

### 🔐 **Smart Contracts - Sistema Completo**

#### ✅ **Contratos Finales Implementados**

**KYCManager.sol (742 líneas)**

- ✅ Sistema de verificación KYC con 3 tiers
- ✅ Tier 0: Sin KYC - Límites $1,000/día, $5,000/mes
- ✅ Tier 1: KYC Básico - Límites $10,000/día, $100,000/mes
- ✅ Tier 2: KYC Completo - Sin límites, puede ser intermediario
- ✅ IPFS para almacenar documentos cifrados
- ✅ Tracking de volumen diario/mensual automático
- ✅ Expiración automática después de 1 año
- ✅ Cooldown de 7 días entre resubmisiones
- ✅ Fee configurable (0.01 BNB por defecto)
- ✅ Roles: KYC_VERIFIER, OPERATOR, PAUSER

**ChainlinkPriceOracle.sol (875 líneas)**

- ✅ Integración con Chainlink Data Feeds BSC
- ✅ Precios REFERENCIALES para UI (no para ejecución)
- ✅ Actualización configurable por admin
- ✅ Intervalos configurables: updateInterval, heartbeat, maxPriceAge
- ✅ TWAP (Time-Weighted Average Price) anti-manipulación
- ✅ Fallback robusto: Chainlink → Manual → Último conocido
- ✅ Detección de precios obsoletos (stale)
- ✅ Alertas de desviación >10% entre actualizaciones
- ✅ Historial de últimos 100 precios por token
- ✅ Batch updates para múltiples tokens
- ✅ Normalización automática a 18 decimales
- ✅ Soporte para precios inversos

#### 📊 **Estadísticas Finales**

```
✅ 44/44 contratos implementados (100%)
✅ 35,013 líneas de código Solidity
✅ 10 fases completadas
✅ Sistema 100% funcional
```

**Arquitectura Completa:**

- Core: 7 contratos
- Exchange: 4 contratos
- Bridges: 5 contratos
- Managers: 7 contratos (+ KYCManager)
- Features: 10 contratos
- Oracles: 1 contrato (ChainlinkPriceOracle)
- Storage: 6 contratos
- Helpers: 3 contratos
- Mocks: 3 contratos (testing)

#### 🎯 **Funcionalidades Clave**

**P2P Descentralizado:**

- ✅ 3 tipos: Crypto-Crypto, Crypto-Fiat, Fiat-Fiat
- ✅ Usuarios fijan sus propios precios (mercado libre)
- ✅ Order book on-chain público
- ✅ Atomic swaps con escrow automático
- ✅ Sin intermediarios en crypto-crypto

**Sistema de Límites:**

- ✅ Límites configurables por tier KYC
- ✅ Tracking automático de volumen
- ✅ Restricciones por día y por mes
- ✅ Integración con todos los managers

**Precios Referenciales:**

- ✅ Chainlink para mostrar precios de mercado en UI
- ✅ NO afecta precios de ejecución (usuarios fijan)
- ✅ Actualización automática configurable
- ✅ TWAP para prevenir manipulación

#### 📝 **Documentación Actualizada**

- ✅ EVALUACION_ESTADO_ACTUAL.md - Estado completo del sistema
- ✅ ACLARACION_PRECIOS_P2P.md - Cómo funcionan los precios
- ✅ ANALISIS_ARQUITECTURA.md - Análisis arquitectónico completo
- ✅ flujo_ecosistema_ascii.md - Diagramas visuales
- ✅ README.md actualizado con 44 contratos

#### 🐛 **Correcciones Frontend**

**Keys Duplicadas:**

- ✅ Corregidas keys duplicadas en fiat-payment-methods (revolut, n26, wise)
- ✅ Añadidos prefijos únicos: `bank-${id}` y `electronic-${id}`

**Imágenes SVG:**

- ✅ Creadas 11 carpetas de monedas fiat
- ✅ 113 archivos SVG placeholder generados
- ✅ Cobertura: MXN, DOP, CAD, VES, COP, PEN, CLP, SVC, AWG, EUR, BRL, ARS
- ✅ Bancos de 12 países latinoamericanos

---

## ✅ **[v1.1.0] - 6 de enero de 2026**

### 🏗️ **Refactorización Mayor - App Router + pnpm**

#### 📁 **Reorganización de Estructura**

- ✅ Movido `components/` → `app/components/`
- ✅ Movido `hooks/` → `app/hooks/`
- ✅ Movido `settings/` → `app/settings/`
- ✅ Eliminada carpeta `layouts/` (redundante con Next.js 15 App Router)
- ✅ Estructura ahora sigue convenciones de Next.js 15

#### 🔄 **Limpieza de Código**

- ✅ Eliminados 15 componentes duplicados (Dashboard, Exchange, Staking, etc.)
- ✅ Eliminados archivos Web3 vacíos (useAuth.ts, useContract.ts, interactions.ts)
- ✅ Eliminada carpeta `components/web3/` completa
- ✅ Consolidada lógica Web3 en `lib/web3/`
- ✅ 83 archivos actualizados con nuevos imports

#### 📦 **Migración a pnpm**

- ✅ Cambiado de npm a pnpm 9.15.0
- ✅ Eliminado `package-lock.json`
- ✅ Generado `pnpm-lock.yaml`
- ✅ 1019 paquetes instalados correctamente
- ✅ Actualizado `package.json` con `packageManager` field

#### 🔧 **Configuración**

- ✅ Actualizado `tsconfig.json` con nuevos paths
- ✅ Mejorado `.gitignore` para carpeta `contratos/`
- ✅ Actualizado `.env.example` con todas las variables necesarias

#### 📚 **Documentación Nueva**

- ✅ Creado `ARCHITECTURE.md` - Documentación completa de arquitectura
- ✅ Creado `CONTRIBUTING.md` - Guía de contribución
- ✅ Creado `SECURITY.md` - Prácticas de seguridad Web3
- ✅ Creado `AUDIT_PLAN.md` - Plan de auditoría y optimización
- ✅ Creado `MIGRATION_THIRDWEB.md` - Guía de migración a Thirdweb

#### 🎯 **Optimizaciones de Git**

- ✅ Mejorado `.gitignore` para evitar archivos grandes
- ✅ Excluidos `package-lock.json`, PDFs, y archivos temporales de contratos
- ✅ Reducido tamaño de repositorio considerablemente

#### 🚀 **Actualizaciones de Dependencias**

- ✅ Next.js 14 → 15.1.11
- ✅ Thirdweb v4 → v5.116.1
- ✅ TypeScript 5.8.2
- ✅ TailwindCSS 3.4.1

---

## 🚀 **[Próxima Versión] - Cambios por Implementar (TODO)**

### 🔧 **Mejoras y Modificaciones**

- [ ] **Modificar el Modal de Disclaimer**

  - El usuario debe ver el **disclaimer** antes de acceder a la plataforma.
  - Agregar la opción de **"Conectar Wallet"** o **"Acceder sin conexión"**.

- [ ] **Mejorar la conexión del usuario a la página**

  - La opción de conexión debe integrarse con el disclaimer.
  - Permitir navegación sin conexión, pero con limitaciones.

- [ ] **Ajustar la sección de Open Finance para precios de tokens**

  - Organizar mejor los datos del mercado.
  - Integrar datos en tiempo real (CoinGecko, Binance API).

- [ ] **Optimizar el Sidebar**

  - Asegurar que la navegación entre secciones funcione correctamente.
  - Permitir un comportamiento **colapsable en dispositivos móviles**.

- [ ] **Modificar el layout del Sidebar**

  - Mejorar la UI/UX para versiones de escritorio y móviles.
  - Hacer que las secciones sean accesibles con mejor fluidez.

- [ ] **Renombrar `Header` a `NavBar` y mejorar su funcionalidad**

  - Cambiar la estructura del código para reflejar el nuevo nombre.
  - Integrar una mejor navegación y compatibilidad con el Sidebar.

- [ ] **Optimizar el layout para diferentes dispositivos**

  - Ajustar correctamente en **TV, Laptop, Tablet y Móvil**.
  - Mejorar diseño responsive para evitar errores en pantallas pequeñas.

- [ ] **Crear un contrato inteligente de Faucet**
  - Desplegar un contrato de **faucet** en la testnet.
  - Permitir que los usuarios **reclamen tokens de prueba** fácilmente.
  - Integrar con la UI de CambiaCripto.

---

## ✅ **[Versión Anterior] - Últimos cambios realizados**

### 🛠 **Mejoras y Fixes**

- ✅ **Se agregó la sección de `StableCoins` con Sidebar y NavBar.**
- ✅ **Se implementó `FAQSection.tsx` para cada StableCoin.**
- ✅ **Se mejoró la UI de `StableCoinDetail.tsx` con gráficos y datos de mercado.**
- ✅ **Se integró `shadcn/ui` para mejorar la experiencia visual del Dashboard.**
- ✅ **Se modularizaron los componentes de `PriceChart`, `MarketInfo`, `Disclaimer`.**

---

## 📝 **Notas**

- Para probar la integración con el contrato de Faucet, será necesario un RPC de testnet.
- La nueva UI del `NavBar` y `Sidebar` debe funcionar de forma fluida en pantallas táctiles.

