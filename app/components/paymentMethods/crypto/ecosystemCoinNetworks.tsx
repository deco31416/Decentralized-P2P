export interface Network {
  id: string
  name: string
  icon: string
  chainId: number
  rpc: string
  explorer: string
  symbol: string
}

export const ecosystemCoinNetworks: { mainnets: Record<string, Network>; testnets: Record<string, Network> } = {
  mainnets: {
    binance: {
      id: 'bsc',
      name: 'Binance Smart Chain',
      icon: '/icons/networks/bsc.svg',
      chainId: 56,
      rpc: 'https://bsc-dataseed.binance.org/',
      explorer: 'https://bscscan.com/',
      symbol: 'BNB'
    },
    tron: {
      id: 'tron',
      name: 'TRON',
      icon: '/icons/networks/tron.svg',
      chainId: 11111,
      rpc: 'https://api.trongrid.io',
      explorer: 'https://tronscan.org',
      symbol: 'TRX'
    },
    polygon: {
      id: 'polygon',
      name: 'Polygon',
      icon: '/icons/networks/polygon.svg',
      chainId: 137,
      rpc: 'https://polygon-rpc.com',
      explorer: 'https://polygonscan.com/',
      symbol: 'MATIC'
    },
    solana: {
      id: 'solana',
      name: 'Solana',
      icon: '/icons/networks/solana.svg',
      chainId: 1,
      rpc: 'https://api.mainnet-beta.solana.com',
      explorer: 'https://solscan.io/',
      symbol: 'SOL'
    },
    gnosis: {
      id: 'gnosis',
      name: 'Gnosis Chain',
      icon: '/icons/networks/gnosis.svg',
      chainId: 100,
      rpc: 'https://rpc.gnosischain.com/',
      explorer: 'https://gnosisscan.io/',
      symbol: 'xDAI'
    },
    ton: {
      id: 'ton',
      name: 'TON Blockchain',
      icon: '/icons/networks/ton.svg',
      chainId: 1234,
      rpc: 'https://toncenter.com/api/v2/jsonRPC',
      explorer: 'https://tonscan.org/',
      symbol: 'TON'
    },
    optimism: {
      id: 'optimism',
      name: 'Optimism',
      icon: '/icons/networks/optimism.svg',
      chainId: 10,
      rpc: 'https://mainnet.optimism.io',
      explorer: 'https://optimistic.etherscan.io/',
      symbol: 'OP'
    },
    polkadot: {
      id: 'polkadot',
      name: 'Polkadot',
      icon: '/icons/networks/polkadot.svg',
      chainId: 9999,
      rpc: 'https://rpc.polkadot.io',
      explorer: 'https://polkadot.subscan.io/',
      symbol: 'DOT'
    },
    worldchain: {
      id: 'worldchain',
      name: 'World Chain',
      icon: '/icons/networks/worldchain.svg',
      chainId: 5252,
      rpc: 'https://rpc.worldchain.com',
      explorer: 'https://worldscan.com/',
      symbol: 'WLD'
    },
    ethereum: {
      id: 'ethereum',
      name: 'Ethereum',
      icon: '/icons/networks/ethereum.svg',
      chainId: 1,
      rpc: 'https://mainnet.infura.io/',
      explorer: 'https://etherscan.io/',
      symbol: 'ETH'
    }
  },
  testnets: {
    binance: {
      id: 'bsc-testnet',
      name: 'Binance Testnet',
      icon: '/icons/networks/bsc-testnet.svg',
      chainId: 97,
      rpc: 'https://data-seed-prebsc-1-s1.binance.org:8545/',
      explorer: 'https://testnet.bscscan.com/',
      symbol: 'tBNB'
    },
    optimism: {
      id: 'optimism',
      name: 'Optimism',
      icon: '/icons/networks/optimism.svg',
      chainId: 10,
      rpc: 'https://mainnet.optimism.io',
      explorer: 'https://optimistic.etherscan.io/',
      symbol: 'OP'
    }
  }
}
