// CustomConnectButton.js
'use client'

import { ConnectButton } from 'thirdweb/react'
import { client } from '@/app/hooks/client' // Asegúrate de que 'client' esté correctamente definido
import { inAppWallet, createWallet } from 'thirdweb/wallets'
import './styles.css' // Importa la hoja de estilos

// Definición de las opciones de wallets
const wallets = [
  inAppWallet({
    auth: {
      options: ['google', 'discord', 'telegram', 'email', 'x', 'passkey', 'phone', 'apple', 'facebook']
    }
  }),
  createWallet('io.metamask'),
  createWallet('com.trustwallet.app'),
  createWallet('com.coinbase.wallet'),
  createWallet('me.rainbow'),
  createWallet('app.walletnow'),
  createWallet('us.binance')
]

export default function CustomConnectButton() {
  return (
    <ConnectButton
      client={client}
      wallets={wallets}
      connectButton={{
        label: 'Conectar Wallet',
        className: 'custom-connect-button' // Aplica la clase personalizada
        // Otras opciones de personalización
      }}
    />
  )
}
