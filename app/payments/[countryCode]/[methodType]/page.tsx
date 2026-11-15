import { FiatPaymentMethods } from '@/app/components/paymentMethods/fiat/FiatPaymentMethods/FiatPaymentMethods'
import Link from 'next/link'
import Image from 'next/image'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { ChevronLeft, ChevronRight } from 'lucide-react'

interface PageProps {
  params: Promise<{
    countryCode: string
    methodType: string
  }>
  searchParams?: Promise<{
    page?: string
  }>
}

const PAGE_SIZE = 12

export default async function PaymentMethodsByTypePage({ params, searchParams }: PageProps) {
  const { countryCode, methodType } = await params
  const resolvedSearchParams = (await searchParams) ?? undefined
  const page = Math.max(1, Number(resolvedSearchParams?.page ?? '1') || 1)

  if (methodType !== 'bankTransfers' && methodType !== 'electronicPayments') {
    return (
      <div className='p-6 max-w-5xl mx-auto space-y-2 text-center'>
        <h1 className='text-2xl font-bold'>Tipo de método inválido</h1>
        <p className='text-muted-foreground'>El tipo debe ser bankTransfers o electronicPayments.</p>
      </div>
    )
  }

  const country = FiatPaymentMethods[countryCode]
  if (!country) {
    return (
      <div className='p-6 max-w-5xl mx-auto space-y-2 text-center'>
        <h1 className='text-2xl font-bold'>País no encontrado</h1>
        <p className='text-muted-foreground'>Verifica el código del país.</p>
      </div>
    )
  }

  const methods = country.paymentMethods?.[methodType] || []
  const totalPages = Math.max(1, Math.ceil(methods.length / PAGE_SIZE))
  const safePage = Math.min(page, totalPages)
  const start = (safePage - 1) * PAGE_SIZE
  const items = methods.slice(start, start + PAGE_SIZE)

  const title = methodType === 'bankTransfers' ? 'Transferencias bancarias' : 'Pagos electrónicos'

  return (
    <div className='p-6 max-w-5xl mx-auto space-y-6'>
      <div className='flex items-end justify-between gap-4'>
        <div>
          <h1 className='text-2xl font-bold'>{title}</h1>
          <p className='text-sm text-muted-foreground'>
            {countryCode.toUpperCase()} · {methods.length} métodos
          </p>
        </div>

        <div className='flex items-center gap-2'>
          <Button asChild variant='outline' disabled={safePage <= 1}>
            <Link href={`/payments/${countryCode}/${methodType}?page=${Math.max(1, safePage - 1)}`} aria-disabled={safePage <= 1}>
              <ChevronLeft className='h-4 w-4 mr-1' />
              Anterior
            </Link>
          </Button>

          <div className='text-sm text-muted-foreground tabular-nums'>
            Página {safePage} / {totalPages}
          </div>

          <Button asChild variant='outline' disabled={safePage >= totalPages}>
            <Link
              href={`/payments/${countryCode}/${methodType}?page=${Math.min(totalPages, safePage + 1)}`}
              aria-disabled={safePage >= totalPages}
            >
              Siguiente
              <ChevronRight className='h-4 w-4 ml-1' />
            </Link>
          </Button>
        </div>
      </div>

      <div className='grid grid-cols-[repeat(auto-fill,minmax(180px,1fr))] gap-4'>
        {items.map(method => (
          <Link key={method.id} href={`/payments/${countryCode}/${methodType}/${method.id}`} className='contents'>
            <Card className='cursor-pointer hover:bg-accent/30 transition-colors'>
              <CardHeader className='pb-2'>
                <CardTitle className='text-sm'>{method.name}</CardTitle>
              </CardHeader>
              <CardContent className='flex items-center gap-3'>
                {method.icon ? (
                  <Image src={method.icon} alt={method.name} width={36} height={36} className='rounded-md' />
                ) : (
                  <div className='h-9 w-9 rounded-md bg-muted' />
                )}
                <div className='text-xs text-muted-foreground truncate'>{method.id}</div>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  )
}

