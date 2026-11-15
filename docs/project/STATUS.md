# Estado del proyecto

**Última revisión estática del árbol:** 14 de noviembre de 2026.  
**Método:** inspección de nombres de archivos, configuración y documentación; no se ejecutaron compilaciones, pruebas, despliegues ni análisis dinámicos.  
**Alcance:** describe lo que se encontró en esta copia local; no certifica el estado de producción ni el historial Git.

## Resumen verificable

| Área | Evidencia en esta copia | Estado documental |
| --- | --- | --- |
| Aplicación web | Next.js 15.1.11, React 18, TypeScript 5.8; rutas de funcionalidades bajo `app/(features)/`. | Código presente; comportamiento no validado en ejecución. |
| Integración Web3 | Dependencias Thirdweb y ethers, configuración y utilidades en la aplicación. | Integración presente; no se verificaron transacciones reales. |
| Contratos | Solidity 0.8.20 organizado en `contratos/contracts/` por dominios. | Fuentes presentes; no se compilaron ni revisaron exhaustivamente en esta pasada. |
| Pruebas web | No hay script de pruebas de frontend en el `package.json` raíz. | Suite no identificada en esta copia. |
| Pruebas de contratos | `contratos/package.json` declara `npm test`, pero no se encontró carpeta `contratos/test/`. | Cobertura no acreditada; agregar tests y registrar resultados. |
| Redes | `contratos/hardhat.config.js` define `hardhat`, `localhost`, `bsctestnet` y `bscmainnet`. | Configuración presente; no implica despliegue ni direcciones propias verificadas. |
| Despliegues | Hay scripts bajo `contratos/scripts/`. | No se verificó una red, contrato desplegado ni transacción de deployment. |
| Dependencias bloqueadas | Hay `pnpm-lock.yaml` en la raíz. No se encontró lockfile de npm dentro de `contratos/`. | Reproducibilidad parcial; definir y documentar estrategia de lockfile para contratos. |
| Git | Esta carpeta no contiene `.git`. | No fue posible revisar ramas, historial, archivos staged ni secretos previamente comprometidos. |

## Rutas de funcionalidades detectadas

La lista exacta de rutas fuente observadas, incluidas rutas dinámicas y subrutas, está en la [matriz de rutas](ROUTES.md). La presencia de `page.tsx` **no confirma** que la función esté conectada, completa o lista para usuarios. Cada ruta requiere verificación de pantalla, datos, firma/transacción, contrato relacionado, errores y pruebas.

## Riesgos y límites conocidos

- No hay pruebas de contratos encontradas en `contratos/test/`; el comando `npm test` por sí solo no demuestra cobertura.
- Los documentos históricos contienen nombres de redes, direcciones, cifras, planes y afirmaciones que pueden no corresponder al árbol actual.
- No se debe inferir que los flujos fiat se liquidan en blockchain; documentar qué pasos son externos, manuales o dependen de un tercero.
- No se han verificado despliegues, permisos efectivos, addresses de contratos del proyecto, exploradores, servicios externos ni gestión operativa de claves.
- Esta revisión documental y estática no constituye auditoría de seguridad del frontend o de Solidity.

## Próximos pasos documentales y técnicos

### 1. Inventario funcional

Crear una matriz por ruta que enlace UI, hooks/utilidades, APIs o RPC, contrato, estado de implementación, limitaciones y prueba asociada. No asignar porcentajes subjetivos.

### 2. Catálogo de contratos

Para cada contrato: propósito real según el código, roles, funciones externas, eventos, dependencias, riesgos de confianza, parámetros de despliegue, pruebas y estado de verificación. Distinguir contratos desplegados de fuentes locales.

### 3. Pruebas reproducibles

Añadir pruebas unitarias y de integración de contratos; añadir pruebas de UI para flujos críticos. Documentar versiones de herramientas, comandos, resultados y límites. No publicar un badge de passing/coverage hasta tener evidencia automatizada.

### 4. Despliegue seguro

Definir redes admitidas, RPC, direcciones verificadas, responsables y pasos de reversión. Usar cuentas de testnet desechables; proteger claves con un gestor de secretos. La guía debe advertir y confirmar red/chain ID antes de cualquier despliegue.

### 5. Modelo de amenazas y datos

Documentar wallet, firma, permisos, custodia, disputas, oráculos, integraciones externas, datos personales/KYC y componentes off-chain. Indicar qué no cubre la cadena y quién puede pausar, actualizar o administrar cada contrato.

### 6. Liberación

Antes de etiquetar una versión: CI verde, lockfiles comprometidos, licencia y atribución revisadas, escaneo de secretos en el snapshot e historial, SBOM/dependencias revisadas, auditoría externa publicada si existe y notas de versión con limitaciones.

## Criterio de actualización

Cada cambio que afecte rutas, redes, contratos, comandos, variables de entorno o estado de pruebas debe actualizar este documento y los README relacionados en el mismo cambio. Sustituye afirmaciones de estado solo con evidencia reproducible.


