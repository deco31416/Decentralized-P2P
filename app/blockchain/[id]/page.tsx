import { uniqueBlockchains } from '@/app/components/paymentMethods/crypto/Blockchain/uniqueBlockchains'
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

export default async function BlockchainDetail({ params }: PageProps) {
  const { id } = await params
  const blockchain = (uniqueBlockchains.find(c => c.id === id) || null) as CryptoMethodArray | null

  if (!blockchain) {
    return (
      <div className='p-6 max-w-5xl mx-auto space-y-6 text-center'>
        <h1 className='text-2xl font-bold'>Blockchain no encontrada</h1>
        <p className='text-muted-foreground'>La blockchain que buscas no está disponible.</p>
      </div>
    )
  }

  return (
    <div className='p-6 max-w-5xl mx-auto space-y-6'>
      <StableCoinHeader
        icon={blockchain.icon}
        name={blockchain.name}
        price={String(blockchain.price) || 'N/A'}
        networks={blockchain.networks || []}
      />
      <DetailSectionsSlot name={blockchain.name} />
      <MarketInfo />
      <FAQSectionSlot name={blockchain.name} />
      <Disclaimer />
    </div>
  )
}
