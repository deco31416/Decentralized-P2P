'use client'

import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { QuickBuy } from '@/app/(features)/dashboard/components/quick-buy.component'

export default function QuickExchange() {
  return (
    <Card className='sm:col-span-2'>
      <CardHeader>
        <CardTitle>Quick Exchange</CardTitle>
      </CardHeader>
      <CardContent>
        <QuickBuy />
      </CardContent>
    </Card>
  )
}
