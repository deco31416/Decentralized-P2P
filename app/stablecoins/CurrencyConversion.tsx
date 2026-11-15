'use client'

import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Carousel, CarouselContent, CarouselItem, CarouselNext, CarouselPrevious } from '@/app/components/ui/carousel'
import Image from 'next/image'
import { fiatCurrencies } from '@/app/components/paymentMethods/fiat/FiatMoney/Fiat'

export function CurrencyConversion() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Conversión a divisas locales</CardTitle>
      </CardHeader>
      <CardContent>
        <Carousel className='w-full'>
          <CarouselContent className='-ml-2'>
            {fiatCurrencies.map(currency => (
              <CarouselItem key={currency.id} className='basis-1/2 sm:basis-1/3 md:basis-1/4 pl-2'>
                <Card className='p-4 flex flex-col items-center justify-center border shadow-sm hover:shadow-md transition-all'>
                  <Image
                    src={currency.icon}
                    alt={currency.name}
                    width={40}
                    height={30}
                    className='rounded-md mb-2'
                  />
                  <div className='text-sm text-muted-foreground'>{currency.id.toUpperCase()}</div>
                  <div className='text-lg font-semibold'>1.00</div>
                </Card>
              </CarouselItem>
            ))}
          </CarouselContent>
          <CarouselPrevious />
          <CarouselNext />
        </Carousel>
      </CardContent>
    </Card>
  )
}
