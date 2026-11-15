'use client'

import { useState } from 'react'
import { uniqueFiatPayment } from '@/app/components/paymentMethods/fiat/FiatPaymentMethods/uniqueFiatPayment'
import { Card, CardHeader, CardContent } from '@/app/components/ui/card'
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from '@/app/components/ui/select'
import Image from 'next/image'
import { CreditCard } from 'lucide-react'
import Link from 'next/link'

const uniqueFiatSet = Array.from(new Map(uniqueFiatPayment.map(fiat => [fiat.id, fiat])).values())

export function FiatPaymentMethods(): JSX.Element {
  const [selectedFiat, setSelectedFiat] = useState(uniqueFiatSet[0])
  const [selectedMethod, setSelectedMethod] = useState<'all' | 'bankTransfers' | 'electronicPayments'>('all')

  const handleFiatChange = (id: string) => {
    const newFiat = uniqueFiatSet.find(fiat => fiat.id === id)
    if (newFiat) setSelectedFiat(newFiat)
  }

  const handleMethodChange = (method: 'all' | 'bankTransfers' | 'electronicPayments') => {
    setSelectedMethod(method)
  }

  const getFilteredMethods = () => {
    const methods =
      selectedMethod === 'all'
        ? [
            ...(selectedFiat.paymentMethods.bankTransfers || []),
            ...(selectedFiat.paymentMethods.electronicPayments || [])
          ]
        : selectedFiat.paymentMethods[selectedMethod] || []

    return methods.map(method => ({
      ...method,
      description: method.name || 'Método de pago disponible'
    }))
  }

  const generatePaymentUrl = (countryCode: string, methodType: string, methodId: string) => {
    return `/payments/${countryCode}/${methodType}/${methodId}`
  }

  return (
    <div className='p-4'>
      <Card className='shadow-md border-none w-full'>
        <CardHeader className='p-4 flex flex-col gap-4'>
          <div className='flex flex-wrap gap-4 items-center justify-between'>
            <Select onValueChange={handleFiatChange} defaultValue={selectedFiat.id}>
              <SelectTrigger className='w-64'>
                <SelectValue>{selectedFiat.name}</SelectValue>
              </SelectTrigger>
              <SelectContent className='max-h-64 overflow-y-auto'>
                {uniqueFiatSet.map(fiat => (
                  <SelectItem key={fiat.id} value={fiat.id}>
                    <div className='flex items-center gap-2'>
                      <Image src={fiat.icon} alt={fiat.name} width={20} height={20} className='rounded-full' />
                      {fiat.name}
                    </div>
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>

            <Select onValueChange={handleMethodChange} defaultValue='all'>
              <SelectTrigger className='w-64'>
                <SelectValue>Todos los métodos</SelectValue>
              </SelectTrigger>
              <SelectContent>
                <SelectItem value='all'>Todos los métodos</SelectItem>
                <SelectItem value='bankTransfers'>Transferencia Bancaria</SelectItem>
                <SelectItem value='electronicPayments'>Medios Electrónicos</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardHeader>

        <CardContent className='p-4'>
          <div className='grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-6 p-4'>
            {selectedMethod === 'all'
              ? [
                  ...(selectedFiat.paymentMethods.bankTransfers || []).map(method => (
                    <Link
                      key={`bank-${method.id}`}
                      href={generatePaymentUrl(selectedFiat.id, 'bankTransfers', method.id)}
                      passHref
                    >
                      <div className='flex flex-col items-center justify-center bg-white hover:bg-gray-50 active:scale-95 transition-all rounded-xl shadow-xl p-3 cursor-pointer min-w-[120px] max-w-[200px] w-full aspect-[16/9]'>
                        <div className='relative w-16 h-16'>
                          <Image
                            src={method.icon}
                            alt={method.name}
                            width={60}
                            height={60}
                            className='object-contain rounded-full'
                          />
                        </div>
                        <span className='text-xs font-medium text-gray-700 truncate mt-2 text-center w-full'>
                          {method.name}
                        </span>
                      </div>
                    </Link>
                  )),
                  ...(selectedFiat.paymentMethods.electronicPayments || []).map(method => (
                    <Link
                      key={`electronic-${method.id}`}
                      href={generatePaymentUrl(selectedFiat.id, 'electronicPayments', method.id)}
                      passHref
                    >
                      <div className='flex flex-col items-center justify-center bg-white hover:bg-gray-50 active:scale-95 transition-all rounded-xl shadow-xl p-3 cursor-pointer min-w-[120px] max-w-[200px] w-full aspect-[16/9]'>
                        <div className='relative w-16 h-16'>
                          <Image
                            src={method.icon}
                            alt={method.name}
                            width={60}
                            height={60}
                            className='object-contain rounded-full'
                          />
                        </div>
                        <span className='text-xs font-medium text-gray-700 truncate mt-2 text-center w-full'>
                          {method.name}
                        </span>
                      </div>
                    </Link>
                  ))
                ]
              : getFilteredMethods().map(method => (
                  <Link key={method.id} href={generatePaymentUrl(selectedFiat.id, selectedMethod, method.id)} passHref>
                    <div
                      key={method.id}
                      className='flex flex-col items-center justify-center bg-white hover:bg-gray-50 active:scale-95 transition-all rounded-xl shadow-xl p-3 cursor-pointer min-w-[120px] max-w-[200px] w-full aspect-[16/9]'
                    >
                      <div className='relative w-16 h-16'>
                        <Image
                          src={method.icon}
                          alt={method.name}
                          width={60}
                          height={60}
                          className='object-contain rounded-full'
                        />
                      </div>
                      <span className='text-xs font-medium text-gray-700 truncate mt-2 text-center w-full'>
                        {method.name}
                      </span>
                    </div>
                  </Link>
                ))}
          </div>

          <div className='mt-6 flex items-center gap-2 text-sm text-muted-foreground'>
            <CreditCard className='h-4 w-4' />
            <span>Todos los pagos son procesados de forma segura</span>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
