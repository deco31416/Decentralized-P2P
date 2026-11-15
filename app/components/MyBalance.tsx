'use client'

import { Card, CardContent } from '@/app/components/ui/card'
import { InfoIcon } from 'lucide-react'
import Image from 'next/image'
import { useTheme } from 'next-themes'

interface MyBalanceProps {
  showSecondary?: boolean
}

export default function MyBalance({ showSecondary = false }: MyBalanceProps) {
  const { resolvedTheme } = useTheme()
  // Datos mockeados (sin conexión a Web3)
  const userAddress = '0x23...03E2' // Simulamos dirección de wallet
  const mainBalance = '0.00 SDFT' // Simulamos balance principal
  const mockBalances = {
    USDT: '1,234.56',
    ETH: '0.547',
    orders: '23'
  }

  return (
    <Card className='bg-primary text-primary-foreground'>
      <CardContent className='p-6'>
        <div className='flex items-center gap-4'>
          <div className='rounded-full bg-primary-foreground/20 p-2'>
            <Image
              src={resolvedTheme === 'dark' ? '/black.png' : '/white.png'}
              alt='Logo'
              width={40}
              height={40}
              priority
            />
          </div>
          <div className='flex flex-col'>
            <div className='text-sm opacity-80'>Hola {userAddress}, tu balance es:</div>
            <div className='flex items-center gap-2 mt-1'>
              <span className='text-2xl font-medium'>{mainBalance}</span>
              <InfoIcon className='h-4 w-4 opacity-80' />
            </div>
          </div>
        </div>

        {/* Sección de balances secundarios (Mockeados) */}
        {showSecondary && (
          <div className='mt-4 grid grid-cols-1 sm:grid-cols-3 gap-4'>
            <div className='bg-primary-foreground/10 p-3 rounded-lg'>
              <div className='text-sm opacity-80'>USDT Balance</div>
              <div className='text-lg font-semibold'>{mockBalances.USDT}</div>
            </div>
            <div className='bg-primary-foreground/10 p-3 rounded-lg'>
              <div className='text-sm opacity-80'>ETH Balance</div>
              <div className='text-lg font-semibold'>{mockBalances.ETH}</div>
            </div>
            <div className='bg-primary-foreground/10 p-3 rounded-lg'>
              <div className='text-sm opacity-80'>Total Orders</div>
              <div className='text-lg font-semibold'>{mockBalances.orders}</div>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
