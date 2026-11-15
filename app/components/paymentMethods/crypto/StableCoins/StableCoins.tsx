import { CryptoMethodArray } from '@/app/components/paymentMethods/types'
import { uniqueStableCoins } from './uniqueStableCoins'
import { stableCoinNetworks } from './stableCoinNetworks'

export const stableCoins: CryptoMethodArray[] = uniqueStableCoins.map(coin => ({
  ...coin,
  networks: stableCoinNetworks[coin.id as keyof typeof stableCoinNetworks] || [],
  price: 0
}))
