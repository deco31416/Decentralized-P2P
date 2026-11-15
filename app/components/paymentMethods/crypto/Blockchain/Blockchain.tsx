import { uniqueBlockchains } from './uniqueBlockchains'
import Image from 'next/image'
import Link from 'next/link'

export function BlockchainCards(): JSX.Element {
  return (
    <div className='grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-6 p-4'>
      {uniqueBlockchains.map(blockchain => (
        <Link
          key={blockchain.id}
          href={`/blockchains/${blockchain.id}`}
          className='flex flex-col items-center justify-center bg-white hover:bg-gray-50 active:scale-95 transition-all rounded-xl shadow-xl p-2 cursor-pointer'
          style={{ width: '160px', height: '100px' }}
        >
          <div className='relative w-8 h-8'>
            <Image
              src={blockchain.icon}
              alt={blockchain.name}
              width={40}
              height={40}
              className='object-contain rounded-full'
            />
          </div>
          <span className='text-xs font-medium text-gray-700 truncate mt-1.5 text-center w-full'>
            {blockchain.name.split(' ')[0]}
          </span>
          <span className='text-xs font-medium text-gray-500 mt-1'>${blockchain.price ?? 1}</span>
        </Link>
      ))}
    </div>
  )
}
