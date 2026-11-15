import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Skeleton } from '@/app/components/ui/skeleton'

export default function Loading() {
  return (
    <div className='p-6 max-w-5xl mx-auto space-y-6'>
      <div className='flex items-center gap-4'>
        <Skeleton className='h-20 w-20 rounded-full' />
        <Skeleton className='h-8 w-64' />
      </div>

      <div className='grid md:grid-cols-2 gap-6'>
        <Card>
          <CardHeader>
            <CardTitle>Descripción</CardTitle>
          </CardHeader>
          <CardContent>
            <Skeleton className='h-4 w-full' />
            <Skeleton className='h-4 w-5/6 mt-2' />
            <Skeleton className='h-4 w-2/3 mt-2' />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Precio</CardTitle>
          </CardHeader>
          <CardContent>
            <Skeleton className='h-10 w-40' />
            <Skeleton className='h-4 w-48 mt-2' />
          </CardContent>
        </Card>
      </div>

      <div className='grid grid-cols-1 md:grid-cols-2 gap-6'>
        <Skeleton className='h-[260px] w-full' />
        <Skeleton className='h-[260px] w-full' />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Cargando contenido</CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className='h-[300px] w-full' />
        </CardContent>
      </Card>
    </div>
  )
}
