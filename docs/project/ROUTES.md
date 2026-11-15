# Matriz de rutas de la aplicación

**Revisión estática:** 14 de noviembre de 2026. Esta matriz se generó a partir de los `page.tsx` presentes en `app/`. Indica que existe una página fuente para la ruta; **no confirma que el flujo esté conectado, sea correcto o esté listo para producción**.

Las carpetas de grupo de Next.js entre paréntesis no forman parte de la URL. Los segmentos entre corchetes son parámetros dinámicos.

| URL | Archivo fuente | Estado comprobado |
| --- | --- | --- |
| `/` | `app/page.tsx` | Página presente; comportamiento no evaluado. |
| `/dashboard` | `app/(features)/dashboard/page.tsx` | Página presente; datos/integración no evaluados. |
| `/deposit` | `app/(features)/deposit/page.tsx` | Página presente; flujo no evaluado. |
| `/extras` | `app/(features)/extras/page.tsx` | Página presente; contenido no evaluado. |
| `/ido` | `app/(features)/ido/page.tsx` | Página presente; flujo no evaluado. |
| `/p2p/appeals` | `app/(features)/p2p/appeals/page.tsx` | Página presente; flujo de disputas no evaluado. |
| `/p2p/exchange` | `app/(features)/p2p/exchange/page.tsx` | Página presente; transacciones no evaluadas. |
| `/p2p/market` | `app/(features)/p2p/market/page.tsx` | Página presente; ofertas/datos no evaluados. |
| `/p2p/ongoing-operations` | `app/(features)/p2p/ongoing-operations/page.tsx` | Página presente; estado de operaciones no evaluado. |
| `/p2p/orders` | `app/(features)/p2p/orders/page.tsx` | Página presente; órdenes no evaluadas. |
| `/p2p/trades` | `app/(features)/p2p/trades/page.tsx` | Página presente; historial no evaluado. |
| `/rewards/referral` | `app/(features)/rewards/referral/page.tsx` | Página presente; recompensas no evaluadas. |
| `/rewards/socialfi` | `app/(features)/rewards/socialfi/page.tsx` | Página presente; recompensas no evaluadas. |
| `/settings` | `app/(features)/settings/page.tsx` | Página presente; persistencia no evaluada. |
| `/staking` | `app/(features)/staking/page.tsx` | Página presente; transacciones no evaluadas. |
| `/withdraw` | `app/(features)/withdraw/page.tsx` | Página presente; flujo no evaluado. |
| `/altcoins/:id` | `app/altcoins/[id]/page.tsx` | Página dinámica presente; datos no evaluados. |
| `/blockchain/:id` | `app/blockchain/[id]/page.tsx` | Página dinámica presente; datos no evaluados. |
| `/fiat/:id` | `app/fiat/[id]/page.tsx` | Página dinámica presente; datos no evaluados. |
| `/payments/:countryCode` | `app/payments/[countryCode]/page.tsx` | Página dinámica presente; cobertura/función no evaluada. |
| `/payments/:countryCode/:methodType` | `app/payments/[countryCode]/[methodType]/page.tsx` | Página dinámica presente; cobertura/función no evaluada. |
| `/payments/:countryCode/:methodType/:methodId` | `app/payments/[countryCode]/[methodType]/[methodId]/page.tsx` | Página dinámica presente; cobertura/función no evaluada. |
| `/stablecoins/:id` | `app/stablecoins/[id]/page.tsx` | Página dinámica presente; datos no evaluados. |

## Cómo completar el estado funcional

Para cada ruta, inspecciona el componente y registra por separado:

1. Fuente de datos y comportamiento con datos vacíos o fallidos.
2. Si usa datos mock, caché, API, RPC o eventos de contrato.
3. Acciones que requieren wallet, firma, aprobación o pago externo.
4. Validaciones, errores y comportamiento en red incorrecta.
5. Pruebas automatizadas asociadas y último resultado reproducible.
6. Limitaciones visibles para el usuario y requisitos de privacidad.

Usa estados **presente**, **parcial**, **propuesto**, **pendiente** y **verificado** con evidencia; no marques “verificado” solo porque la ruta compile o renderice.
