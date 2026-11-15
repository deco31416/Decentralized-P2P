// components/paymentMethods/crypto/AltCoins/AltCoins.tsx
import { CryptoMethodArray } from '@/app/components/paymentMethods/types'
import { uniqueAltCoins } from './uniqueAltCoins'
import { altCoinsNetworks } from './altCoinsNetworks'

export const altCoins: CryptoMethodArray[] = uniqueAltCoins.map(coin => ({
  ...coin,
  networks: altCoinsNetworks[coin.id as keyof typeof altCoinsNetworks] || [],
  price: coin.price || 'N/A'
}))
