import { ecosystemCoinNetworks, Network } from "../ecosystemCoinNetworks";

// Definimos que `coinNetworks` es un Record<string, Network[]>
export const coinNetworks: Record<string, Network[]> = {
  bnb: [ecosystemCoinNetworks.mainnets.binance],
  trx: [ecosystemCoinNetworks.mainnets.tron],
  matic: [ecosystemCoinNetworks.mainnets.polygon],
  sol: [ecosystemCoinNetworks.mainnets.solana],
  gnosis: [ecosystemCoinNetworks.mainnets.gnosis],
  ton: [ecosystemCoinNetworks.mainnets.ton],
  op: [ecosystemCoinNetworks.mainnets.optimism],
  dot: [ecosystemCoinNetworks.mainnets.polkadot],
  world: [ecosystemCoinNetworks.mainnets.worldchain],
  eth: [ecosystemCoinNetworks.mainnets.ethereum],
  "bsc-testnet": [ecosystemCoinNetworks.testnets.binance],
};
