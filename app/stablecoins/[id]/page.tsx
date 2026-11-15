import { stableCoins } from '@/app/components/paymentMethods/crypto/StableCoins/StableCoins'
import { StableCoinHeader } from '../StableCoinHeader'
import { MarketInfo } from '../MarketInfo'
import { FAQSection } from '../FAQSection'
import { Disclaimer } from '../Disclaimer'
import { DetailSections } from '@/app/stablecoins/DetailSections.client'

// Tipo correcto para `coin`
import type { CryptoMethodArray } from '@/app/components/paymentMethods/types'

interface PageProps {
  params: Promise<{
    id: string
  }>
}

export default async function StableCoinDetail({ params }: PageProps) {
  const { id } = await params
  const coin = (stableCoins.find(c => c.id === id) || null) as CryptoMethodArray | null

  // 📌 Si no encuentra la moneda, mostrar mensaje personalizado
  if (!coin) {
    return (
      <div className='p-6 max-w-5xl mx-auto space-y-6 text-center'>
        <h1 className='text-2xl font-bold'>Moneda no encontrada</h1>
        <p className='text-muted-foreground'>La stablecoin que buscas no está disponible.</p>
      </div>
    )
  }

  return (
    <div className='p-6 max-w-5xl mx-auto space-y-6'>
      {/* Componente con imagen, opinión y precio */}
      <StableCoinHeader
        icon={coin.icon}
        name={coin.name}
        price='1.00'
        networks={coin.networks?.map(net => ({ id: net.id, name: net.name })) || []}
      />
      <DetailSections name={coin.name} />
      <MarketInfo />
      <FAQSection name={coin.name} />
      <Disclaimer />
    </div>
  )
}
