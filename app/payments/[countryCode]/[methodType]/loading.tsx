import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Skeleton } from '@/app/components/ui/skeleton'

export default function Loading() {
  return (
    <div className='p-6 max-w-5xl mx-auto space-y-6'>
      <div className='flex items-end justify-between gap-4'>
        <div className='space-y-2'>
          <Skeleton className='h-7 w-64' />
          <Skeleton className='h-4 w-40' />
        </div>
        <div className='flex items-center gap-2'>
          <Skeleton className='h-9 w-28' />
          <Skeleton className='h-4 w-28' />
          <Skeleton className='h-9 w-28' />
        </div>
      </div>

      <div className='grid grid-cols-[repeat(auto-fill,minmax(180px,1fr))] gap-4'>
        {Array.from({ length: 12 }).map((_, i) => (
          <Card key={i}>
            <CardHeader className='pb-2'>
              <CardTitle className='text-sm'>
                <Skeleton className='h-4 w-3/4' />
              </CardTitle>
            </CardHeader>
            <CardContent className='flex items-center gap-3'>
              <Skeleton className='h-9 w-9 rounded-md' />
              <Skeleton className='h-3 w-24' />
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
