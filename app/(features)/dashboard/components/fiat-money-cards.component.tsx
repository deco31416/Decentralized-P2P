'use client'

import { fiatCurrencies } from '@/app/components/paymentMethods/fiat/FiatMoney/Fiat'
import Image from 'next/image'
import Link from 'next/link'

export function FiatMoneyCards(): JSX.Element {
  return (
    <div className='grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-6 p-4'>
      {fiatCurrencies.map(fiat => (
        <Link key={fiat.id} href={`/fiat/${fiat.id}`} className='contents'>
          <div className='flex flex-col items-center justify-center bg-white hover:bg-gray-50 active:scale-95 transition-all rounded-xl shadow-xl p-3 cursor-pointer min-w-[120px] max-w-[200px] w-full aspect-[16/9]'>
            <div className='relative w-10 h-10'>
              <Image src={fiat.icon} alt={fiat.name} width={40} height={40} className='object-contain rounded-full' />
            </div>
            <span className='text-xs font-medium text-gray-700 truncate mt-2 text-center w-full'>{fiat.name}</span>
          </div>
        </Link>
      ))}
    </div>
  )
}
