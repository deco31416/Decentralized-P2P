# Documentación

Esta carpeta contiene únicamente la documentación de referencia para entender y contribuir al proyecto. El código está en desarrollo; las páginas y contratos enumerados no implican que los flujos estén completos, desplegados o auditados.

## Empieza aquí

1. [README principal](../README.md) — propósito, tecnologías e inicio rápido.
2. [Estado del proyecto](project/STATUS.md) — qué se verificó y qué sigue pendiente.
3. [Rutas de la aplicación](project/ROUTES.md) — inventario de páginas presentes; integración por validar.
4. [Arquitectura](project/ARCHITECTURE.md) — capas y estructura observadas en el código.
5. [Contratos](contracts/CATALOG.md) — inventario de fuentes Solidity.
6. [Seguridad](security/POLICY.md) — credenciales, wallets y requisitos antes de despliegues.
7. [README de contratos](../contratos/README.md) — comandos y desarrollo con Hardhat.
8. [Contribuir](../CONTRIBUTING.md) — guía para cambios y pull requests.
9. [Ficha conceptual](project/OVERVIEW.html) — resumen visual del propósito y alcance.

## Estructura

```text
docs/
├── README.md
├── project/
│   ├── ARCHITECTURE.md
│   ├── OVERVIEW.html
│   ├── ROUTES.md
│   └── STATUS.md
├── contracts/
│   └── CATALOG.md
└── security/
    └── POLICY.md
```

## Criterio de documentación

- “Presente” significa que hay un archivo o ruta; no que funcione de extremo a extremo.
- “Verificado” requiere un comando, entorno, resultado y fecha reproducibles.
- Los despliegues solo se documentan con red, chain ID, dirección y transacción verificables.
- No se hacen afirmaciones de seguridad, cobertura, usuarios o disponibilidad sin evidencia.
