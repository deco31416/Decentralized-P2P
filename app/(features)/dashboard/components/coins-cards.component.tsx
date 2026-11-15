'use client'

import { ecosystemCoins } from '@/app/components/paymentMethods/crypto/Coins/Coins'
import Image from 'next/image'
import Link from 'next/link'

export function CoinsCards(): JSX.Element {
  return (
    <div className='grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-6 p-4'>
      {ecosystemCoins.map(coin => (
        <Link key={coin.id} href={`/blockchain/${coin.id}`}>
          <div className='flex flex-col items-center justify-center bg-white hover:bg-gray-50 active:scale-95 transition-all rounded-xl shadow-xl p-3 cursor-pointer min-w-[120px] max-w-[200px] w-full aspect-[16/9]'>
            <div className='relative w-10 h-10'>
              <Image
                src={coin.icon}
                alt={coin.name}
                fill
                sizes='40px'
                className='object-contain rounded-full'
              />
            </div>
            <span className='text-xs font-medium text-gray-700 truncate mt-2 text-center w-full'>
              {coin.name.split(' ')[0]}
            </span>
          </div>
        </Link>
      ))}
    </div>
  )
}
