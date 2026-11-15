import { fiatCurrencies, FiatCurrency } from '@/app/components/paymentMethods/fiat/FiatMoney/Fiat'
import { StableCoinHeader } from '../../stablecoins/StableCoinHeader'
import { MarketInfo } from '../../stablecoins/MarketInfo'
import { FAQSection } from '../../stablecoins/FAQSection'
import { Disclaimer } from '../../stablecoins/Disclaimer'
import { DetailSections } from '@/app/stablecoins/DetailSections.client'

interface PageProps {
  params: Promise<{
    id: string
  }>
}

export default async function FiatDetailPage({ params }: PageProps) {
  const { id } = await params
  const currency = (fiatCurrencies.find(f => f.id === id) || null) as FiatCurrency | null

  if (!currency) {
    return (
      <div className='p-6 max-w-5xl mx-auto space-y-6 text-center'>
        <h1 className='text-2xl font-bold'>Moneda no encontrada</h1>
        <p className='text-muted-foreground'>La moneda fiat que buscas no está disponible.</p>
      </div>
    )
  }

  return (
    <div className='p-6 max-w-5xl mx-auto space-y-6'>
      <StableCoinHeader icon={currency.icon} name={currency.name} price={'N/A'} networks={[]} />
      <DetailSections name={currency.name} />
      <MarketInfo />
      <FAQSection name={currency.name} />
      <Disclaimer />
    </div>
  )
}
