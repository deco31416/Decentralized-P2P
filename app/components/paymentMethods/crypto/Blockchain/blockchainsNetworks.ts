import { ecosystemCoinNetworks } from '../ecosystemCoinNetworks'

export const blockchainsNetworks = {
  ethereum: [ecosystemCoinNetworks.mainnets.ethereum, ecosystemCoinNetworks.testnets.ethereum],
  bsc: [ecosystemCoinNetworks.mainnets.binance, ecosystemCoinNetworks.testnets.binance],
  wld: [ecosystemCoinNetworks.mainnets.worldcoin],
  solana: [ecosystemCoinNetworks.mainnets.solana],
  tron: [ecosystemCoinNetworks.mainnets.tron],
  polygon: [ecosystemCoinNetworks.mainnets.polygon],
  gnosis: [ecosystemCoinNetworks.mainnets.gnosis],
  toncoin: [ecosystemCoinNetworks.mainnets.ton],
  polkadot: [ecosystemCoinNetworks.mainnets.polkadot]
}
