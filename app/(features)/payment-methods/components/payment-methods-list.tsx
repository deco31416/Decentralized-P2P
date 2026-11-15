'use client'

import Image from 'next/image'
import { ScrollArea, ScrollBar } from '@/app/components/ui/scroll-area'
import { Badge } from '@/app/components/ui/badge'
import { Card } from '@/app/components/ui/card'
import { FiatPaymentIcons } from '@/app/components/paymentMethods/icons/FiatPaymentIcons'

export type PaymentMethod = {
  id: string
  name: string
  icon: string
  type: 'bankTransfers' | 'electronicPayments'
  isAvailable?: boolean
  country?: string
}

const paymentMethods: PaymentMethod[] = [
  {
    id: 'zelle',
    name: 'Zelle',
    icon: FiatPaymentIcons.zelle,
    type: 'electronicPayments',
    isAvailable: true,
    country: 'usd'
  },
  {
    id: 'paypal',
    name: 'PayPal',
    icon: FiatPaymentIcons.paypal,
    type: 'electronicPayments',
    isAvailable: true
  },
  {
    id: 'bancolombia',
    name: 'Bancolombia',
    icon: FiatPaymentIcons.bancolombia,
    type: 'bankTransfers',
    isAvailable: true,
    country: 'cop'
  },
  {
    id: 'nequi',
    name: 'Nequi',
    icon: FiatPaymentIcons.nequi,
    type: 'electronicPayments',
    isAvailable: true,
    country: 'cop'
  },
  {
    id: 'bank',
    name: 'Bank Transfer',
    icon: 'https://cdn-icons-png.flaticon.com/256/2057/2057748.png',
    type: 'bankTransfers',
    isAvailable: true
  }
]

interface PaymentMethodsListProps {
  onSelect?: (method: PaymentMethod) => void
  selectedId?: string
}

export function PaymentMethodsList({ onSelect, selectedId }: PaymentMethodsListProps) {
  return (
    <ScrollArea className='w-full'>
      <div className='flex gap-4 pb-4'>
        {paymentMethods.map(method => (
          <Card
            key={method.id}
            className={`
              flex flex-col items-center p-4 min-w-[140px] cursor-pointer
              hover:bg-muted/50 transition-all
              ${!method.isAvailable ? 'opacity-60' : ''}
              ${selectedId === method.id ? 'border-primary' : ''}
            `}
            onClick={() => method.isAvailable && onSelect?.(method)}
          >
            <div className='w-12 h-12 relative mb-2'>
              <Image src={method.icon} alt={method.name} fill className='object-contain' />
            </div>
            <div className='text-sm font-medium mb-2'>{method.name}</div>
            <div className='flex gap-2 flex-wrap justify-center'>
              <Badge variant='outline' className='text-xs'>
                {method.type}
              </Badge>
              {!method.isAvailable && (
                <Badge variant='secondary' className='text-xs'>
                  Coming soon
                </Badge>
              )}
            </div>
          </Card>
        ))}
      </div>
      <ScrollBar orientation='horizontal' />
    </ScrollArea>
  )
}
