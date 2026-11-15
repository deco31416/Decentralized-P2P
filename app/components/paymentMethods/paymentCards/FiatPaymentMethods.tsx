import { useState } from 'react'
import { uniqueFiatPayment } from '@/app/components/paymentMethods/fiat/FiatPaymentMethods/uniqueFiatPayment'
import { Card, CardHeader, CardContent } from '@/app/components/ui/card'
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from '@/app/components/ui/select'
import Image from 'next/image'
import Link from 'next/link'
import { CreditCard } from 'lucide-react'

// Eliminar duplicados en base al ID
const uniqueFiatSet = Array.from(new Map(uniqueFiatPayment.map(fiat => [fiat.id, fiat])).values())

export default function FiatPaymentMethods() {
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
    let methods = []

    if (selectedMethod === 'all') {
      methods = [
        ...(selectedFiat.paymentMethods.bankTransfers || []),
        ...(selectedFiat.paymentMethods.electronicPayments || [])
      ]
    } else {
      methods = selectedFiat.paymentMethods[selectedMethod] || []
    }
    console.log(methods)

    return methods.map(method => ({
      ...method,
      FiatPaymentIcons: <Image src={method.icon} alt={method.name} width={64} height={64} className='rounded-full' />,
      description: method.name || 'Método de pago disponible'
    }))
  }

  // Esta función genera la URL de cada método de pago
  const generatePaymentUrl = (countryCode: string, methodType: string, methodId: string) => {
    return `/payments/${countryCode}/${methodType}/${methodId}`
  }

  return (
    <div className='p-4'>
      <Card className='shadow-md border-none w-full'>
        <CardHeader className='p-4 flex flex-col gap-4'>
          {/* Selectores de moneda y método de pago */}
          <div className='flex flex-wrap gap-4 items-center justify-between'>
            {/* Selector de moneda */}
            <Select onValueChange={value => handleFiatChange(value)} defaultValue={selectedFiat.id}>
              <SelectTrigger className='w-64'>
                <SelectValue placeholder='Seleccionar Moneda Fiat'>
                  <div className='flex items-center gap-2'>
                    <Image
                      src={selectedFiat.icon}
                      alt={selectedFiat.name}
                      width={20}
                      height={20}
                      className='rounded-full'
                    />
                    <span>{selectedFiat.name}</span>
                  </div>
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
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

            {/* Selector de método de pago */}
            <Select
              onValueChange={value => handleMethodChange(value as 'all' | 'bankTransfers' | 'electronicPayments')}
              defaultValue='all'
            >
              <SelectTrigger className='w-64'>
                <SelectValue placeholder='Seleccionar Método de Pago'>Todos los métodos</SelectValue>
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
          {/* Renderizar métodos de pago en horizontal */}
          <div className='grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4'>
            {getFilteredMethods().map(method => (
              <Link
                key={method.id}
                href={generatePaymentUrl('usd', 'bankTransfers', method.id)} // Aquí generamos la URL
                passHref // Asegura que el enlace sea correcto
              >
                <Card className='border hover:shadow-md transition-all cursor-pointer bg-white flex flex-col items-center justify-center p-4 aspect-square'>
                  <div className='w-full h-full flex flex-col items-center justify-center'>
                    <div className='w-12 h-12 relative'>
                      <Image src={method.icon} alt={method.name} fill className='object-contain rounded-full' />
                    </div>
                    <h3 className='text-sm font-semibold text-gray-700 text-center mt-2'>{method.name}</h3>
                  </div>
                </Card>
              </Link>
            ))}
          </div>

          {/* Información de seguridad */}
          <div className='mt-6 flex items-center gap-2 text-sm text-muted-foreground'>
            <CreditCard className='h-4 w-4' />
            <span>Todos los pagos son procesados de forma segura</span>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
