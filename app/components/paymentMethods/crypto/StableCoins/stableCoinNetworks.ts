// components/paymentMethods/crypto/stableCoinNetworks.ts
import { ecosystemCoinNetworks } from "../ecosystemCoinNetworks";

export const stableCoinNetworks = {
  usdt: [
    ecosystemCoinNetworks.mainnets.ethereum,
    ecosystemCoinNetworks.mainnets.binance,
    ecosystemCoinNetworks.mainnets.tron,
    ecosystemCoinNetworks.mainnets.polygon,
    ecosystemCoinNetworks.mainnets.solana,
  ],
  usdc: [
    ecosystemCoinNetworks.mainnets.ethereum,
    ecosystemCoinNetworks.mainnets.binance,
    ecosystemCoinNetworks.mainnets.tron,
    ecosystemCoinNetworks.mainnets.polygon,
    ecosystemCoinNetworks.mainnets.solana,
  ],
  dai: [
    ecosystemCoinNetworks.mainnets.ethereum,
    ecosystemCoinNetworks.mainnets.polygon,
  ],
  fdusd: [ecosystemCoinNetworks.mainnets.binance],
  pax: [ecosystemCoinNetworks.mainnets.ethereum],
  gusd: [ecosystemCoinNetworks.mainnets.ethereum],
  pyusd: [ecosystemCoinNetworks.mainnets.ethereum],
  ousd: [ecosystemCoinNetworks.mainnets.ethereum],
  xaut: [ecosystemCoinNetworks.mainnets.ethereum],
  xdai: [ecosystemCoinNetworks.mainnets.gnosis],
};
