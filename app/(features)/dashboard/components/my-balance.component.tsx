'use client'

import { Card, CardContent } from '@/app/components/ui/card'
import { InfoIcon } from 'lucide-react'
import Image from 'next/image'

interface MyBalanceProps {
  showSecondary?: boolean
}

export function MyBalance({ showSecondary = false }: MyBalanceProps): JSX.Element {
  // Mock data (without Web3 connection)
  const userAddress = '0x23...03E2' // Simulated wallet address
  const mainBalance = '0.00 SDFT' // Simulated main balance
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
              src='/white.png'
              alt='Logo'
              width={40}
              height={40}
              priority
              className='block dark:hidden'
            />
            <Image
              src='/black.png'
              alt='Logo'
              width={40}
              height={40}
              priority
              className='hidden dark:block'
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

        {/* Secondary balances section (Mocked) */}
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
