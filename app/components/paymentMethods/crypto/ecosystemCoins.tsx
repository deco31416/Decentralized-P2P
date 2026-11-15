import { CryptoMethod } from '../types'
import { ecosystemCoinNetworks } from './ecosystemCoinNetworks'
import { paymentIcons } from '../icons/icons'

export const ecosystemCoins: CryptoMethod[] = [
  {
    id: 'bnb',
    name: 'Binance Coin (BNB)',
    icon: paymentIcons.crypto.binance,
    network: ecosystemCoinNetworks.mainnets.binance
  },
  {
    id: 'trx',
    name: 'TRON (TRX)',
    icon: paymentIcons.crypto.tron,
    network: ecosystemCoinNetworks.mainnets.tron
  },
  {
    id: 'matic',
    name: 'Polygon (MATIC)',
    icon: paymentIcons.crypto.polygon,
    network: ecosystemCoinNetworks.mainnets.polygon
  },
  {
    id: 'sol',
    name: 'Solana (SOL)',
    icon: paymentIcons.crypto.solana,
    network: ecosystemCoinNetworks.mainnets.solana
  },
  {
    id: 'gnosis',
    name: 'Gnosis (xDAI)',
    icon: paymentIcons.crypto.xdai,
    network: ecosystemCoinNetworks.mainnets.gnosis
  },
  {
    id: 'ton',
    name: 'Toncoin (TON)',
    icon: paymentIcons.crypto.toncoin,
    network: ecosystemCoinNetworks.mainnets.ton
  },
  {
    id: 'op',
    name: 'Optimism (OP)',
    icon: paymentIcons.crypto.optimism,
    network: ecosystemCoinNetworks.mainnets.optimism
  },
  {
    id: 'dot',
    name: 'Polkadot (DOT)',
    icon: paymentIcons.crypto.polkadot,
    network: ecosystemCoinNetworks.mainnets.polkadot
  },
  {
    id: 'wld',
    name: 'Worldcoin (WLD)',
    icon: paymentIcons.crypto.worldcoin,
    network: ecosystemCoinNetworks.mainnets.worldchain
  },
  {
    id: 'eth',
    name: 'Ethereum (ETH)',
    icon: paymentIcons.crypto.ethereum,
    network: ecosystemCoinNetworks.mainnets.ethereum
  },
  {
    id: 'bsc-testnet',
    name: 'Binance Testnet (tBNB)',
    icon: paymentIcons.crypto.binance,
    network: ecosystemCoinNetworks.testnets.binance
  }
]
