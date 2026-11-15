import { altCoins } from '@/app/components/paymentMethods/crypto/AltCoins/AltCoins'
import { StableCoinHeader } from '../../stablecoins/StableCoinHeader'
import { MarketInfo } from '../../stablecoins/MarketInfo'
import { Disclaimer } from '../../stablecoins/Disclaimer'
import { DetailSectionsSlot } from '@/app/components/detail/DetailSectionsSlot.client'
import { FAQSectionSlot } from '@/app/components/detail/FAQSectionSlot.client'

import type { CryptoMethodArray } from '@/app/components/paymentMethods/types'

interface PageProps {
  params: Promise<{
    id: string
  }>
}

export default async function AltCoinDetail({ params }: PageProps) {
  const { id } = await params
  const coin = (altCoins.find(c => c.id === id) || null) as CryptoMethodArray | null

  if (!coin) {
    return (
      <div className='p-6 max-w-5xl mx-auto space-y-6 text-center'>
        <h1 className='text-2xl font-bold'>Moneda no encontrada</h1>
        <p className='text-muted-foreground'>La altcoin que buscas no está disponible.</p>
      </div>
    )
  }

  return (
    <div className='p-6 max-w-5xl mx-auto space-y-6'>
      <StableCoinHeader
        icon={coin.icon}
        name={coin.name}
        price={String(coin.price) || 'N/A'}
        networks={coin.networks || []}
      />
      <DetailSectionsSlot name={coin.name} />
      <MarketInfo />
      <FAQSectionSlot name={coin.name} />
      <Disclaimer />
    </div>
  )
}
