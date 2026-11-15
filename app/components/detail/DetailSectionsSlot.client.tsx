'use client'

import dynamic from 'next/dynamic'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Skeleton } from '@/app/components/ui/skeleton'

const DetailSections = dynamic(() => import('@/app/stablecoins/DetailSections.client').then(m => m.DetailSections), {
  ssr: false,
  loading: () => (
    <>
      <div className='grid grid-cols-1 md:grid-cols-2 gap-6'>
        <Skeleton className='h-[260px] w-full' />
        <Skeleton className='h-[260px] w-full' />
      </div>

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

      <Card>
        <CardHeader>
          <CardTitle>Precio histórico</CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className='h-[300px] w-full' />
        </CardContent>
      </Card>
    </>
  )
})

export function DetailSectionsSlot({ name }: { name: string }): JSX.Element {
  return <DetailSections name={name} />
}
