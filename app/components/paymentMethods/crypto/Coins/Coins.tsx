import { CryptoMethodArray } from '@/app/components/paymentMethods/types'
import { uniqueCoins } from './uniqueCoins'
import { coinNetworks } from './coinNetworks'

export const ecosystemCoins: CryptoMethodArray[] = uniqueCoins.map(coin => ({
  ...coin,
  networks: coinNetworks[coin.id as keyof typeof coinNetworks] || [],
  price: 0
}))
