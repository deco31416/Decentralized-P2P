'use client'

import { Loader2 } from 'lucide-react'

export function PageLoader() {
  return (
    <div className='fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm'>
      <div className='flex items-center gap-3 rounded-lg border bg-card px-4 py-3 shadow-sm'>
        <Loader2 className='h-5 w-5 animate-spin text-primary' />
        <div className='text-sm font-medium'>Cargando...</div>
      </div>
    </div>
  )
}
