'use client'

import { useTheme } from 'next-themes'
import { ConnectButton } from 'thirdweb/react'
import { client } from '@/app/hooks/client'
import { lightTheme, darkTheme } from 'thirdweb/react'
import { inAppWallet, createWallet } from 'thirdweb/wallets'
import './styles.css'

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
  createWallet('us.binance'),
]

export default function CustomConnectButton() {
  const { theme } = useTheme()

  const thirdwebTheme = theme === 'light' ? lightTheme() : darkTheme()

  return (
    <ConnectButton
      client={client}
      wallets={wallets}
      theme={thirdwebTheme}
      connectButton={{
        label: 'Login to DApp',
        className: 'custom-large-button'
      }}
    />
  )
}
