'use client'

import dynamic from 'next/dynamic'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Skeleton } from '@/app/components/ui/skeleton'

const CurrencyConversion = dynamic(
  () => import('./CurrencyConversion').then(m => m.CurrencyConversion),
  {
    ssr: false,
    loading: () => (
      <Card>
        <CardHeader>
          <CardTitle>Conversión a divisas locales</CardTitle>
        </CardHeader>
        <CardContent>
          <div className='grid grid-cols-2 sm:grid-cols-4 gap-3'>
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className='h-20 w-full' />
            ))}
          </div>
        </CardContent>
      </Card>
    )
  }
)

const PriceChart = dynamic(
  () => import('./PriceChart').then(m => m.PriceChart),
  {
    ssr: false,
    loading: () => (
      <Card>
        <CardHeader>
          <CardTitle>Precio histórico</CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className='h-[300px] w-full' />
        </CardContent>
      </Card>
    )
  }
)

const CryptoSentiment = dynamic(
  () => import('./CryptoSentiment').then(m => m.CryptoSentiment),
  {
    ssr: false,
    loading: () => (
      <div className='grid grid-cols-1 md:grid-cols-2 gap-6'>
        <Skeleton className='h-[260px] w-full' />
        <Skeleton className='h-[260px] w-full' />
      </div>
    )
  }
)

export function DetailSections({ name }: { name: string }) {
  return (
    <>
      <CryptoSentiment name={name} />
      <CurrencyConversion />
      <PriceChart />
    </>
  )
}
