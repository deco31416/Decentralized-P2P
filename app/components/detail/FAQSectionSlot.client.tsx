'use client'

import dynamic from 'next/dynamic'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Skeleton } from '@/app/components/ui/skeleton'

const FAQSection = dynamic(() => import('@/app/stablecoins/FAQSection').then(m => m.FAQSection), {
  ssr: false,
  loading: () => (
    <Card>
      <CardHeader>
        <CardTitle>Preguntas frecuentes</CardTitle>
      </CardHeader>
      <CardContent className='space-y-3'>
        <Skeleton className='h-5 w-5/6' />
        <Skeleton className='h-5 w-4/5' />
        <Skeleton className='h-5 w-3/4' />
      </CardContent>
    </Card>
  )
})

export function FAQSectionSlot({ name }: { name: string }): JSX.Element {
  return <FAQSection name={name} />
}
