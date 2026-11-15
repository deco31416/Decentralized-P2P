import { bsc, bscTestnet, polygon } from 'thirdweb/chains'

function parseChainId(value: string | undefined): number | null {
  if (!value) return null
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

/**
 * Cadena por defecto controlada por variables de entorno.
 * - BSC Testnet (97) por defecto.
 * - BSC Mainnet (56) para producción.
 * - Polygon (137) soportado si lo necesitas.
 */
export const DEFAULT_CHAIN = (() => {
  const chainId = parseChainId(process.env.NEXT_PUBLIC_CHAIN_ID) ?? 97

  switch (chainId) {
    case 97:
      return bscTestnet
    case 56:
      return bsc
    case 137:
      return polygon
    default:
      return bscTestnet
  }
})()
