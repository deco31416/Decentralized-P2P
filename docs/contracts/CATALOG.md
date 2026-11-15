# Inventario de contratos Solidity

**Revisión estática:** 14 de noviembre de 2026. Inventario de archivos `.sol` en `contratos/contracts/`; las descripciones indican área organizativa por carpeta y nombre, no una afirmación de seguridad, despliegue, integración o completitud.

Usa el [README de contratos](../../contratos/README.md) para instalar herramientas y consultar comandos. Para el estado de pruebas y despliegues, consulta [PROJECT_STATUS.md](../project/STATUS.md).

## Bridges

- `bridges/CryptoToFiatBridge.sol`
- `bridges/FiatToCryptoBridge.sol`
- `bridges/FiatToFiatBridge.sol`

## Core

- `core/CambioToken.sol`
- `core/CircuitBreaker.sol`
- `core/SystemMetrics.sol`
- `core/TradeEscrow.sol`

## Exchange

- `exchange/FiatDisputeResolver.sol`
- `exchange/FiatFeeManager.sol`
- `exchange/P2PExchange.sol`
- `exchange/P2PFiatExchange.sol`
- `exchange/P2POrderBook.sol`
- `exchange/SwapRouter.sol`

## Features

- `features/AntiRugPull.sol`
- `features/AppealManager.sol`
- `features/DepositManager.sol`
- `features/DepositReceiptNFT.sol`
- `features/IDOManager.sol`
- `features/LiquidityPool.sol`
- `features/MultiTokenVault.sol`
- `features/QuickBuyManager.sol`
- `features/RandomnessOracle.sol`
- `features/ReferralManager.sol`
- `features/SocialFiRewards.sol`
- `features/TopPerformersTracker.sol`
- `features/VestingManager.sol`
- `features/WithdrawManager.sol`
- `features/WithdrawQueue.sol`

## Interfaces

- `interfaces/IAssetManager.sol`
- `interfaces/IBalanceManager.sol`
- `interfaces/ICircuitBreaker.sol`
- `interfaces/IFeeManager.sol`
- `interfaces/IFiatDisputeResolver.sol`
- `interfaces/IFiatFeeManager.sol`
- `interfaces/ILiquidityEngine.sol`
- `interfaces/IP2PFiatExchange.sol`
- `interfaces/IPancakePair.sol`
- `interfaces/IPancakeRouter.sol`
- `interfaces/IPriceOracle.sol`
- `interfaces/IReputationManager.sol`
- `interfaces/IStakingManager.sol`

También existe una subcarpeta `interfaces/interfaces/` con archivos de nombres solapados. Verifica su contenido e imports antes de deduplicar o asumir que ambas rutas son equivalentes:

- `interfaces/interfaces/IAssetManager.sol`
- `interfaces/interfaces/ICircuitBreaker.sol`
- `interfaces/interfaces/IFeeManager.sol`
- `interfaces/interfaces/ILiquidityEngine.sol`
- `interfaces/interfaces/IPancakePair.sol`
- `interfaces/interfaces/IPancakeRouter.sol`
- `interfaces/interfaces/IPriceOracle.sol`
- `interfaces/interfaces/IReputationManager.sol`
- `interfaces/interfaces/IStakingManager.sol`

## Managers

- `managers/AssetManager.sol`
- `managers/BalanceManager.sol`
- `managers/CollateralManager.sol`
- `managers/DisputeManager.sol`
- `managers/FeeManager.sol`
- `managers/GovernanceManager.sol`
- `managers/IntermediaryManager.sol`
- `managers/KYCManager.sol`
- `managers/LiquidityEngine.sol`
- `managers/ReputationManager.sol`
- `managers/StakingManager.sol`
- `managers/TreasuryManager.sol`

## Mocks

- `mocks/MockERC20.sol`
- `mocks/MockWBNB.sol`

## Oracles

- `oracles/PancakeTwapOracle.sol`

## Información que falta por contrato

Para que este inventario se convierta en documentación operativa, añade por contrato: propósito confirmado leyendo el código; funciones externas y eventos; roles y permisos; constructor/initializer; dependencias y llamadas entre contratos; supuestos sobre terceros; riesgos y límites; pruebas; versión/compiler settings; direcciones y red con enlaces de verificación cuando exista despliegue. No inventes direcciones ni marques despliegues como activos sin transacción verificable.


