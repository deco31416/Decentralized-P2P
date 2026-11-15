# Seguridad

Esta guía describe controles esperados para contribuir y desarrollar. **No es una certificación ni una auditoría del sistema.** El estado observado, límites y tareas abiertas están en [PROJECT_STATUS.md](../project/STATUS.md).

## Secretos y configuración

- No subas `.env`, `.env.local`, claves privadas, frases semilla, keystores, tokens de API ni credenciales de RPC.
- Usa `.env.example` solo con nombres de variables y valores ficticios claramente identificados.
- Toda variable `NEXT_PUBLIC_*` se incluye en código visible al navegador; nunca pongas allí secretos.
- No uses claves privadas de cuentas con fondos reales en desarrollo ni en testnet.
- Si una credencial real se compartió o llegó al repositorio, revócala y rótala de inmediato. Borrarla del último commit no elimina copias del historial, forks o clones.
- Antes del primer push y de cada release, inspecciona tanto el snapshot a publicar como el historial Git completo con herramientas de detección de secretos.

## Wallets y transacciones

- Muestra red, chain ID, activo, monto y destinatario antes de pedir una firma.
- No solicites ni almacenes frases semilla o claves privadas de usuarios.
- Trata balances, precios, RPC y respuestas de proveedores como datos no confiables; maneja fallos, datos obsoletos y redes equivocadas.
- Solicita únicamente permisos y aprobaciones necesarios, y explica su alcance en la interfaz.

## Contratos inteligentes

Antes de un despliegue real, se requiere como mínimo:

1. Revisión de control de acceso, cambios de estado, reentrancia, pausas, retiros, límites, precisión y dependencias.
2. Pruebas unitarias, de integración, casos límite y propiedades/invariantes relevantes.
3. Revisión de compilador, configuración, librerías y bytecode objetivo.
4. Despliegue en entorno local y testnet con parámetros documentados y verificación de resultados.
5. Auditoría independiente del bytecode y fuente final que se pretende desplegar.
6. Procedimiento para claves administrativas, actualización, pausa, incidentes y recuperación.

Los diagramas y nombres de módulos no establecen relaciones de confianza. Identifica en el código quién puede administrar, actualizar, pausar, retirar o resolver disputas.

## Datos personales y servicios off-chain

Documenta qué datos salen del navegador, qué terceros los reciben, cuánto se conservan y cómo se protegen. No supongas que KYC, pagos fiat, resolución de disputas, precios u otras operaciones ocurren en cadena: describe los pasos manuales y externos que confirme el código.

## Reporte de vulnerabilidades

No publiques detalles explotables en issues públicos. Contacta al mantenedor por un canal privado indicado en su perfil de GitHub (`deoc31416`) e incluye versión/commit afectado, impacto y pasos de reproducción seguros. No compartas secretos de usuarios ni fondos.

## Alcance de esta política

Una configuración segura, una compilación exitosa o una prueba aislada no hacen que el producto sea seguro para producción. Publica resultados con alcance, commit, herramienta y limitaciones; no uses “auditado” sin un informe independiente identificable.

