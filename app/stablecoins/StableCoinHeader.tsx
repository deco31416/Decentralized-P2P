import Image from 'next/image'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'

interface StableCoinHeaderProps {
  icon: string
  name: string
  price: string
  networks: { id: string; name: string }[]
}

export function StableCoinHeader({ icon, name, price, networks }: StableCoinHeaderProps) {
  return (
    <div className='space-y-6'>
      {/* Bloque con imagen y nombre - sin bordes */}
      <div className='flex items-center gap-4'>
        <Image src={icon} alt={name} width={80} height={80} className='rounded-full' />
        <h1 className='text-2xl font-bold'>{name}</h1>
      </div>

      {/* Grid horizontal con Descripción y Precio */}
      <div className='grid md:grid-cols-2 gap-6'>
        {/* Card de Descripción */}
        <Card className='flex-1'>
          <CardHeader>
            <CardTitle>Descripción</CardTitle>
          </CardHeader>
          <CardContent>
            <p className='text-sm text-muted-foreground'>
              {name} es una stablecoin segura y respaldada en USD.
              {networks.length > 0 ? (
                <>
                  {' '}
                  Disponible en las siguientes redes:{' '}
                  <span className='font-semibold'>{networks.map(net => net.name).join(', ')}</span>.
                </>
              ) : (
                ' No hay información de redes disponibles.'
              )}
            </p>
          </CardContent>
        </Card>

        {/* Card de Precio */}
        <Card className='flex-1'>
          <CardHeader>
            <CardTitle>Precio de {name} hoy</CardTitle>
          </CardHeader>
          <CardContent>
            <div className='text-4xl font-bold'>${price}</div>
            <p className='text-muted-foreground text-sm'>Actualizado hace 5 minutos</p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
