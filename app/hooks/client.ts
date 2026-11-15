import { createThirdwebClient } from 'thirdweb'

const clientId = process.env.NEXT_PUBLIC_THIRDWEB_CLIENT_ID

// Si no hay Client ID, crear un cliente con configuración mínima
// Esto permite que el dashboard funcione aunque Thirdweb no esté configurado
export const client = clientId
  ? createThirdwebClient({ clientId: clientId })
  : createThirdwebClient({ clientId: 'placeholder' }) // Fallback para que no falle la app
