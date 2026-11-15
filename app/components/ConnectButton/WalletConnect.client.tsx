'use client'

import { ThirdwebProvider, ChainProvider } from 'thirdweb/react'
import CustomConnectButton from '@/app/components/ConnectButton/ConnectButton'
import { DEFAULT_CHAIN } from '@/app/hooks/chain'
import useInactivityLogout from '@/app/hooks/useInactivityLogout'

export default function WalletConnect() {
  return (
    <ThirdwebProvider>
      <ChainProvider chain={DEFAULT_CHAIN}>
        <WalletConnectInner />
      </ChainProvider>
    </ThirdwebProvider>
  )
}

function WalletConnectInner() {
  useInactivityLogout()
  return <CustomConnectButton />
}
