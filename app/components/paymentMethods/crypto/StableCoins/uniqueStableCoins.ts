// components/paymentMethods/crypto/uniqueStableCoins.ts
import { cryptoIcons } from '../../icons/cryptoIcons' // Importar íconos centralizados

export const uniqueStableCoins = [
  { id: 'usdt', name: 'Tether USD (USDT)', icon: cryptoIcons.usd_tether },
  { id: 'usdc', name: 'USD Coin (USDC)', icon: cryptoIcons.usd_coin },
  { id: 'dai', name: 'Dai (DAI)', icon: cryptoIcons.dai },
  { id: 'fdusd', name: 'First (FDUSD)', icon: cryptoIcons.fdusd },
  { id: 'usdd', name: 'Decentrl (USDD)', icon: cryptoIcons.usdd },
  { id: 'pyusd', name: 'PayPal (PYUSD)', icon: cryptoIcons.paypal_stablecoin },
  { id: 'ousd', name: 'Origin (OUSD)', icon: cryptoIcons.origin_dollar },
  { id: 'tusd', name: 'TrueUSD (TUSD)', icon: cryptoIcons.tusd }
]
