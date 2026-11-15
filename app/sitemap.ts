import { MetadataRoute } from 'next'

export default function sitemap(): MetadataRoute.Sitemap {
  const baseUrl = 'https://cambiacripto.com'
  const currentDate = new Date()

  // Páginas estáticas principales
  const staticPages = [
    {
      url: baseUrl,
      lastModified: currentDate,
      changeFrequency: 'daily' as const,
      priority: 1.0
    },
    {
      url: `${baseUrl}/dashboard`,
      lastModified: currentDate,
      changeFrequency: 'hourly' as const,
      priority: 0.9
    },
    {
      url: `${baseUrl}/p2p/market`,
      lastModified: currentDate,
      changeFrequency: 'hourly' as const,
      priority: 0.9
    },
    {
      url: `${baseUrl}/p2p/exchange`,
      lastModified: currentDate,
      changeFrequency: 'hourly' as const,
      priority: 0.9
    },
    {
      url: `${baseUrl}/p2p/orders`,
      lastModified: currentDate,
      changeFrequency: 'daily' as const,
      priority: 0.8
    },
    {
      url: `${baseUrl}/p2p/trades`,
      lastModified: currentDate,
      changeFrequency: 'daily' as const,
      priority: 0.8
    },
    {
      url: `${baseUrl}/p2p/ongoing-operations`,
      lastModified: currentDate,
      changeFrequency: 'daily' as const,
      priority: 0.7
    },
    {
      url: `${baseUrl}/p2p/appeals`,
      lastModified: currentDate,
      changeFrequency: 'weekly' as const,
      priority: 0.6
    },
    {
      url: `${baseUrl}/exchange`,
      lastModified: currentDate,
      changeFrequency: 'hourly' as const,
      priority: 0.9
    },
    {
      url: `${baseUrl}/deposit`,
      lastModified: currentDate,
      changeFrequency: 'daily' as const,
      priority: 0.8
    },
    {
      url: `${baseUrl}/withdraw`,
      lastModified: currentDate,
      changeFrequency: 'daily' as const,
      priority: 0.8
    },
    {
      url: `${baseUrl}/staking`,
      lastModified: currentDate,
      changeFrequency: 'daily' as const,
      priority: 0.8
    },
    {
      url: `${baseUrl}/ido`,
      lastModified: currentDate,
      changeFrequency: 'weekly' as const,
      priority: 0.7
    },
    {
      url: `${baseUrl}/rewards/referral`,
      lastModified: currentDate,
      changeFrequency: 'weekly' as const,
      priority: 0.7
    },
    {
      url: `${baseUrl}/rewards/socialfi`,
      lastModified: currentDate,
      changeFrequency: 'weekly' as const,
      priority: 0.7
    },
    {
      url: `${baseUrl}/payment-methods`,
      lastModified: currentDate,
      changeFrequency: 'monthly' as const,
      priority: 0.8
    },
    {
      url: `${baseUrl}/settings`,
      lastModified: currentDate,
      changeFrequency: 'monthly' as const,
      priority: 0.6
    },
    {
      url: `${baseUrl}/extras`,
      lastModified: currentDate,
      changeFrequency: 'monthly' as const,
      priority: 0.5
    }
  ]

  // Stablecoins principales
  const stablecoins = ['usdt', 'usdc', 'dai', 'busd']
  const stablecoinPages = stablecoins.map(coin => ({
    url: `${baseUrl}/stablecoins/${coin}`,
    lastModified: currentDate,
    changeFrequency: 'daily' as const,
    priority: 0.8
  }))

  // Altcoins principales
  const altcoins = ['bitcoin', 'ethereum', 'bnb', 'cardano', 'solana', 'polkadot']
  const altcoinPages = altcoins.map(coin => ({
    url: `${baseUrl}/altcoins/${coin}`,
    lastModified: currentDate,
    changeFrequency: 'daily' as const,
    priority: 0.8
  }))

  // Blockchains principales
  const blockchains = ['ethereum', 'binance-smart-chain', 'polygon', 'avalanche', 'solana']
  const blockchainPages = blockchains.map(chain => ({
    url: `${baseUrl}/blockchain/${chain}`,
    lastModified: currentDate,
    changeFrequency: 'weekly' as const,
    priority: 0.7
  }))

  // Monedas fiat principales
  const fiatCurrencies = ['usd', 'eur', 'cop', 'mxn', 'ars']
  const fiatPages = fiatCurrencies.map(currency => ({
    url: `${baseUrl}/fiat/${currency}`,
    lastModified: currentDate,
    changeFrequency: 'daily' as const,
    priority: 0.7
  }))

  // Métodos de pago por país
  const paymentMethods = [
    { country: 'usa', type: 'bankTransfers' },
    { country: 'usa', type: 'electronicPayments' },
    { country: 'colombia', type: 'bankTransfers' },
    { country: 'colombia', type: 'electronicPayments' },
    { country: 'mexico', type: 'bankTransfers' },
    { country: 'mexico', type: 'electronicPayments' }
  ]
  const paymentPages = paymentMethods.map(({ country, type }) => ({
    url: `${baseUrl}/payments/${country}/${type}`,
    lastModified: currentDate,
    changeFrequency: 'monthly' as const,
    priority: 0.6
  }))

  return [...staticPages, ...stablecoinPages, ...altcoinPages, ...blockchainPages, ...fiatPages, ...paymentPages]
}
