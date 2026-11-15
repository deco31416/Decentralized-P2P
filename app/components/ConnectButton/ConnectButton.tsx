'use client'

import { useTheme } from 'next-themes'
import { ConnectButton } from 'thirdweb/react'
import { lightTheme, darkTheme } from 'thirdweb/react'
import { inAppWallet, createWallet } from 'thirdweb/wallets'
import { client } from '@/app/hooks/client'
import { DEFAULT_CHAIN } from '@/app/hooks/chain'

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
  const { theme } = useTheme()

  const thirdwebTheme = theme === 'light' ? lightTheme() : darkTheme()

  return (
    <ConnectButton
      client={client} // Usamos el cliente importado
      wallets={wallets}
      chain={DEFAULT_CHAIN}
      theme={thirdwebTheme}
      connectModal={{ size: 'compact' }}
      connectButton={{
        label: 'Login'
      }}
    />
  )
}
