'use client'

import dynamic from 'next/dynamic'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Skeleton } from '@/app/components/ui/skeleton'
import { MyBalance } from './my-balance.component'
import { FiatMoneyCards } from './fiat-money-cards.component'

function QuickBuySkeleton(): JSX.Element {
  return (
    <div className='space-y-3'>
      <Skeleton className='h-10 w-full' />
      <div className='grid grid-cols-2 gap-3'>
        <Skeleton className='h-10 w-full' />
        <Skeleton className='h-10 w-full' />
      </div>
      <Skeleton className='h-10 w-full' />
      <Skeleton className='h-9 w-32' />
    </div>
  )
}

function RecentTransactionsSkeleton(): JSX.Element {
  return (
    <div className='space-y-2'>
      <Skeleton className='h-8 w-40' />
      <div className='space-y-2'>
        <Skeleton className='h-10 w-full' />
        <Skeleton className='h-10 w-full' />
        <Skeleton className='h-10 w-full' />
        <Skeleton className='h-10 w-full' />
      </div>
    </div>
  )
}

function FiatPaymentMethodsSkeleton(): JSX.Element {
  return (
    <div className='p-4'>
      <div className='space-y-4'>
        <div className='flex flex-wrap gap-4 items-center justify-between'>
          <Skeleton className='h-10 w-64' />
          <Skeleton className='h-10 w-64' />
        </div>
        <div className='grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-6'>
          <Skeleton className='h-[90px] w-full rounded-xl' />
          <Skeleton className='h-[90px] w-full rounded-xl' />
          <Skeleton className='h-[90px] w-full rounded-xl' />
          <Skeleton className='h-[90px] w-full rounded-xl' />
          <Skeleton className='h-[90px] w-full rounded-xl' />
          <Skeleton className='h-[90px] w-full rounded-xl' />
        </div>
      </div>
    </div>
  )
}

function AcceptedCardsSkeleton(): JSX.Element {
  return (
    <div className='grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-6 p-4'>
      <Skeleton className='h-[90px] w-full rounded-xl' />
      <Skeleton className='h-[90px] w-full rounded-xl' />
      <Skeleton className='h-[90px] w-full rounded-xl' />
      <Skeleton className='h-[90px] w-full rounded-xl' />
      <Skeleton className='h-[90px] w-full rounded-xl' />
      <Skeleton className='h-[90px] w-full rounded-xl' />
    </div>
  )
}

const QuickBuy = dynamic(() => import('./quick-buy.component').then(m => m.QuickBuy), {
  ssr: false,
  loading: () => <QuickBuySkeleton />
})

const RecentTransactions = dynamic(() => import('./recent-transactions.component').then(m => m.RecentTransactions), {
  ssr: false,
  loading: () => <RecentTransactionsSkeleton />
})

const FiatPaymentMethods = dynamic(() => import('./fiat-payment-methods.component').then(m => m.FiatPaymentMethods), {
  ssr: false,
  loading: () => <FiatPaymentMethodsSkeleton />
})

const CoinsCards = dynamic(() => import('./coins-cards.component').then(m => m.CoinsCards), {
  ssr: false,
  loading: () => <AcceptedCardsSkeleton />
})

const AltCoinsCards = dynamic(() => import('./alt-coins-cards.component').then(m => m.AltCoinsCards), {
  ssr: false,
  loading: () => <AcceptedCardsSkeleton />
})

const StableCoinsCards = dynamic(() => import('./stable-coins-cards.component').then(m => m.StableCoinsCards), {
  ssr: false,
  loading: () => <AcceptedCardsSkeleton />
})

export function DashboardOverview(): JSX.Element {
  return (
    <div className='space-y-2'>
      <MyBalance showSecondary={true} />

      <div className='grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6'>
        <Card className='sm:col-span-2'>
          <CardHeader className='p-3 sm:p-6'>
            <CardTitle className='text-base sm:text-lg'>Quick Exchange</CardTitle>
          </CardHeader>
          <CardContent className='p-3 sm:p-6 pt-0 sm:pt-0'>
            <QuickBuy />
          </CardContent>
        </Card>

        <Card>
          <CardHeader className='p-3 sm:p-6'>
            <CardTitle className='text-base sm:text-lg'>Your Stats</CardTitle>
          </CardHeader>
          <CardContent className='p-3 sm:p-6 pt-0 sm:pt-0'>
            <div className='space-y-4'>
              <div>
                <div className='text-sm text-muted-foreground'>Completion Rate</div>
                <div className='text-xl sm:text-2xl font-bold'>98.5%</div>
              </div>
              <div>
                <div className='text-sm text-muted-foreground'>Average Response</div>
                <div className='text-xl sm:text-2xl font-bold'>5 min</div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className='p-3 sm:p-6'>
          <CardTitle className='text-base sm:text-lg'>Recent Transactions</CardTitle>
        </CardHeader>
        <CardContent className='p-3 sm:p-6 pt-0 sm:pt-0'>
          <RecentTransactions />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className='p-3 sm:p-6'>
          <CardTitle className='text-base sm:text-lg'>Blockchain Accepted</CardTitle>
        </CardHeader>
        <CardContent className='p-0'>
          <CoinsCards />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className='p-3 sm:p-6'>
          <CardTitle className='text-base sm:text-lg'>AltCoins Accepted</CardTitle>
        </CardHeader>
        <CardContent className='p-0'>
          <AltCoinsCards />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className='p-3 sm:p-6'>
          <CardTitle className='text-base sm:text-lg'>StableCoins Accepted</CardTitle>
        </CardHeader>
        <CardContent className='p-0'>
          <StableCoinsCards />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className='p-3 sm:p-6'>
          <CardTitle className='text-base sm:text-lg'>Fiat Accepted</CardTitle>
        </CardHeader>
        <CardContent className='p-0'>
          <FiatMoneyCards />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className='p-3 sm:p-6'>
          <CardTitle className='text-base sm:text-lg'>Payment Methods Accepted</CardTitle>
        </CardHeader>
        <CardContent className='p-0'>
          <FiatPaymentMethods />
        </CardContent>
      </Card>
    </div>
  )
}
