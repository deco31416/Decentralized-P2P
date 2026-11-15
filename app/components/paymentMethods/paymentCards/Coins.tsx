// components/paymentMethods/paymentCards/Coins.tsx
import { ecosystemCoins } from '@/app/components/paymentMethods/crypto/Coins/Coins'
import { Card, CardHeader } from '@/app/components/ui/card'
import Image from 'next/image'

export default function CoinsCards() {
  return (
    <div className='p-4'>
      {/* <h2 className="text-xl font-semibold text-gray-800 mb-4">Ecosystem Coins</h2> */}

      {/* Grid responsivo con ShadCN y Tailwind */}
      <div className='grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4'>
        {ecosystemCoins.map(coin => (
          <Card key={coin.id} className='hover:shadow-lg transition-all border-none aspect-square'>
            <CardHeader className='flex flex-col items-center justify-center p-3 bg-white shadow-sm rounded-xl transition-all duration-200 h-full'>
              <div className='w-12 h-12 relative'>
                <Image src={coin.icon} alt={coin.name} fill className='object-contain rounded-full' />
              </div>
              <div className='text-center mt-2'>
                <h3 className='text-sm font-semibold text-gray-700'>{coin.name}</h3>
              </div>
            </CardHeader>
          </Card>
        ))}
      </div>
    </div>
  )
}
