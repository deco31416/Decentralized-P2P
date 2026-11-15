'use client'

import { useState } from 'react'
import { Search, SlidersHorizontal } from 'lucide-react'
import { Button } from '@/app/components/ui/button'
import { Input } from '@/app/components/ui/input'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/app/components/ui/select'

const PAYMENT_METHODS = ['All Payments', 'Bank Transfer', 'Cash App', 'PayPal', 'Wise', 'Revolut']
const CURRENCIES_FIAT = ['COP', 'USD', 'VES', 'EUR', 'MXN']
const CURRENCIES = ['USDT', 'BTC', 'ETH', 'BNB', 'BUSD']

export function P2PMarket() {
  const [activeTab, setActiveTab] = useState<'buy' | 'sell'>('buy')
  const [selectedCurrencyfiat, setSelectedCurrencyfiat] = useState('USD')
  const [selectedCurrency, setSelectedCurrency] = useState('USDT')
  const [selectedPayment, setSelectedPayment] = useState('All Payments')
  const [showFilters, setShowFilters] = useState(false)

  return (
    <Card>
      <CardHeader className='p-3 sm:p-6'>
        <CardTitle className='text-base sm:text-lg'>P2P Market</CardTitle>
      </CardHeader>
      <CardContent className='p-3 sm:p-6 pt-0 sm:pt-0'>
        <div className='space-y-4'>
          {/* Tabs and Filters */}
          <div className='flex flex-col gap-4'>
            <div className='flex flex-wrap gap-2'>
              <Button
                variant={activeTab === 'buy' ? 'default' : 'outline'}
                onClick={() => setActiveTab('buy')}
                className='flex-1 sm:flex-none'
              >
                Buy
              </Button>
              <Button
                variant={activeTab === 'sell' ? 'default' : 'outline'}
                onClick={() => setActiveTab('sell')}
                className='flex-1 sm:flex-none'
              >
                Sell
              </Button>

              <Select value={selectedCurrency} onValueChange={setSelectedCurrency}>
                <SelectTrigger className='w-[90px] sm:w-[100px]'>
                  <SelectValue placeholder='Currency' />
                </SelectTrigger>
                <SelectContent>
                  {CURRENCIES.map(currency => (
                    <SelectItem key={currency} value={currency}>
                      {currency}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>

              {/* Botón para mostrar/ocultar filtros en móvil */}
              <Button
                variant='outline'
                size='icon'
                className='ml-auto sm:hidden'
                onClick={() => setShowFilters(!showFilters)}
              >
                <SlidersHorizontal className='h-4 w-4' />
              </Button>
            </div>

            {/* Filtros para escritorio */}
            <div className='hidden sm:flex flex-wrap gap-2'>
              <Select value={selectedCurrencyfiat} onValueChange={setSelectedCurrencyfiat}>
                <SelectTrigger className='w-[100px]'>
                  <SelectValue placeholder='Currency fiat' />
                </SelectTrigger>
                <SelectContent>
                  {CURRENCIES_FIAT.map(currencyfiat => (
                    <SelectItem key={currencyfiat} value={currencyfiat}>
                      {currencyfiat}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>

              <Select value={selectedPayment} onValueChange={setSelectedPayment}>
                <SelectTrigger className='w-[150px]'>
                  <SelectValue placeholder='Payment Method' />
                </SelectTrigger>
                <SelectContent>
                  {PAYMENT_METHODS.map(method => (
                    <SelectItem key={method} value={method}>
                      {method}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>

              <div className='relative'>
                <Search className='absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground' />
                <Input type='search' placeholder='Search...' className='pl-9 w-[200px]' />
              </div>

              <Button variant='outline' size='icon'>
                <SlidersHorizontal className='h-4 w-4' />
              </Button>
            </div>

            {/* Filtros para móvil (colapsables) */}
            {showFilters && (
              <div className='flex flex-col sm:hidden space-y-2 pt-2 border-t'>
                <Select value={selectedCurrencyfiat} onValueChange={setSelectedCurrencyfiat}>
                  <SelectTrigger className='w-full'>
                    <SelectValue placeholder='Currency fiat' />
                  </SelectTrigger>
                  <SelectContent>
                    {CURRENCIES_FIAT.map(currencyfiat => (
                      <SelectItem key={currencyfiat} value={currencyfiat}>
                        {currencyfiat}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                <Select value={selectedPayment} onValueChange={setSelectedPayment}>
                  <SelectTrigger className='w-full'>
                    <SelectValue placeholder='Payment Method' />
                  </SelectTrigger>
                  <SelectContent>
                    {PAYMENT_METHODS.map(method => (
                      <SelectItem key={method} value={method}>
                        {method}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                <div className='relative'>
                  <Search className='absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground' />
                  <Input type='search' placeholder='Search...' className='pl-9 w-full' />
                </div>
              </div>
            )}
          </div>

          {/* Orders Table */}
          <div className='relative overflow-x-auto'>
            <table className='w-full text-sm'>
              <thead>
                <tr className='border-b'>
                  <th className='text-left py-3 px-2 sm:px-4'>Advertiser</th>
                  <th className='text-left py-3 px-2 sm:px-4'>Price</th>
                  <th className='hidden sm:table-cell text-left py-3 px-4'>Limit/Available</th>
                  <th className='hidden sm:table-cell text-left py-3 px-4'>Payment</th>
                  <th className='text-right py-3 px-2 sm:px-4'>Trade</th>
                </tr>
              </thead>
              <tbody>
                {/* Sample Order Row */}
                <tr className='border-b'>
                  <td className='py-4 px-2 sm:px-4'>
                    <div className='flex items-center gap-2'>
                      <div className='w-6 h-6 sm:w-8 sm:h-8 rounded-full bg-primary/10 flex items-center justify-center text-xs sm:text-sm'>
                        JD
                      </div>
                      <div>
                        <div className='font-medium text-xs sm:text-sm'>JohnDoe</div>
                        <div className='text-xs text-muted-foreground hidden xs:block'>98.5% • 100+</div>
                      </div>
                    </div>
                  </td>
                  <td className='py-4 px-2 sm:px-4'>
                    <div className='font-medium text-xs sm:text-sm'>$1.01</div>
                  </td>
                  <td className='hidden sm:table-cell py-4 px-4'>
                    <div>Available: 1,000 USDT</div>
                    <div className='text-xs text-muted-foreground'>Limit: $100 - $1,000</div>
                  </td>
                  <td className='hidden sm:table-cell py-4 px-4'>
                    <div className='flex gap-1'>
                      <span className='px-2 py-1 bg-primary/10 rounded-md text-xs'>Bank Transfer</span>
                    </div>
                  </td>
                  <td className='py-4 px-2 sm:px-4 text-right'>
                    <Button size='sm' className='text-xs sm:text-sm px-2 sm:px-4'>
                      {activeTab === 'buy' ? 'Buy' : 'Sell'}
                    </Button>
                  </td>
                </tr>

                {/* Versión móvil de la información oculta */}
                <tr className='border-b sm:hidden'>
                  <td colSpan={3} className='py-2 px-2 text-xs'>
                    <div className='flex justify-between'>
                      <div>
                        <span className='text-muted-foreground'>Available:</span> 1,000 USDT
                      </div>
                      <div>
                        <span className='text-muted-foreground'>Limit:</span> $100 - $1,000
                      </div>
                    </div>
                    <div className='mt-1'>
                      <span className='px-2 py-1 bg-primary/10 rounded-md text-xs'>Bank Transfer</span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
