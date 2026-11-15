import { FiatPaymentMethods } from '@/app/components/paymentMethods/fiat/FiatPaymentMethods/FiatPaymentMethods'
import Link from 'next/link'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { Building2, CreditCard } from 'lucide-react'

interface PageProps {
  params: Promise<{
    countryCode: string
  }>
}

export default async function CountryPaymentMethodsPage({ params }: PageProps) {
  const { countryCode } = await params

  if (!countryCode) {
    return (
      <div className='p-6 max-w-4xl mx-auto text-center'>
        <h1 className='text-2xl font-bold'>Código de país inválido</h1>
        <p>Verifica que el código del país sea correcto.</p>
      </div>
    )
  }

  const countryData = FiatPaymentMethods[countryCode]

  if (!countryData) {
    return (
      <div className='p-6 max-w-4xl mx-auto text-center'>
        <h1 className='text-2xl font-bold'>Datos del país no encontrados</h1>
        <p>Verifica que el código del país sea correcto.</p>
      </div>
    )
  }

  return (
    <div className='p-6 max-w-4xl mx-auto'>
      <h1 className='text-3xl font-bold mb-4'>Métodos de Pago para {countryCode.toUpperCase()}</h1>

      <div className='grid grid-cols-1 sm:grid-cols-2 gap-4'>
        <Card>
          <CardHeader>
            <CardTitle className='flex items-center gap-2'>
              <Building2 className='h-5 w-5' />
              Transferencias bancarias
            </CardTitle>
          </CardHeader>
          <CardContent>
            <Button asChild className='w-full'>
              <Link href={`/payments/${countryCode}/bankTransfers`}>Ver métodos</Link>
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className='flex items-center gap-2'>
              <CreditCard className='h-5 w-5' />
              Pagos electrónicos
            </CardTitle>
          </CardHeader>
          <CardContent>
            <Button asChild className='w-full' variant='secondary'>
              <Link href={`/payments/${countryCode}/electronicPayments`}>Ver métodos</Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
