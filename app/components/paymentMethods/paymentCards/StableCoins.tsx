import { stableCoins } from '@/app/components/paymentMethods/crypto/StableCoins/StableCoins'
import { Card, CardHeader } from '@/app/components/ui/card'
import Image from 'next/image'
import Link from 'next/link'

export default function StableCoinsCards() {
  return (
    <div className='p-4'>
      <div className='grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4'>
        {stableCoins.map(coin => (
          <Link key={coin.id} href={`/stablecoins/${coin.id}`} passHref>
            <Card className='hover:shadow-lg transition-all border-none cursor-pointer aspect-square'>
              <CardHeader className='flex flex-col items-center justify-center p-3 bg-white shadow-sm rounded-xl transition-all duration-200 h-full'>
                <div className='w-12 h-12 relative'>
                  <Image src={coin.icon} alt={coin.name} fill className='object-contain rounded-full' />
                </div>
                <div className='text-center mt-2'>
                  <h3 className='text-sm font-semibold text-gray-700'>{coin.name}</h3>
                </div>
              </CardHeader>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  )
}
