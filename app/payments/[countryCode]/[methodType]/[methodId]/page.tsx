import Image from 'next/image'
import { FiatPaymentMethods } from '@/app/components/paymentMethods/fiat/FiatPaymentMethods/FiatPaymentMethods'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'

interface PageProps {
  params: Promise<{
    countryCode: string
    methodType: string
    methodId: string
  }>
}

export default async function PaymentMethodDetail({ params }: PageProps) {
  const { countryCode, methodType, methodId } = await params

  if (methodType !== 'bankTransfers' && methodType !== 'electronicPayments') {
    return (
      <div className='p-6 max-w-5xl mx-auto space-y-6 text-center'>
        <h1 className='text-2xl font-bold'>Tipo de método inválido</h1>
        <p className='text-muted-foreground'>El tipo de método debe ser bankTransfers o electronicPayments.</p>
      </div>
    )
  }

  const country = FiatPaymentMethods[countryCode]
  const methodList = country?.paymentMethods?.[methodType] || []
  const paymentMethod = methodList.find(m => m.id === methodId) || null

  if (!paymentMethod) {
    return (
      <div className='p-6 max-w-5xl mx-auto space-y-6 text-center'>
        <h1 className='text-2xl font-bold'>Método de pago no encontrado</h1>
        <p className='text-muted-foreground'>El método de pago que buscas no está disponible.</p>
      </div>
    )
  }

  return (
    <div className='p-6 max-w-5xl mx-auto space-y-6'>
      <div className='flex items-center gap-4'>
        <Image src={paymentMethod.icon} alt={paymentMethod.name} width={64} height={64} className='rounded-md' />
        <div>
          <h1 className='text-2xl font-bold'>{paymentMethod.name}</h1>
          <p className='text-sm text-muted-foreground'>
            {countryCode.toUpperCase()} · {methodType} · {paymentMethod.id}
          </p>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Detalle</CardTitle>
        </CardHeader>
        <CardContent>
          <div className='text-sm text-muted-foreground'>
            Este método de pago está disponible para el país seleccionado. Esta vista se mantiene ligera para mejorar la
            velocidad de carga.
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
