'use client'

import type { ReactNode } from 'react'
import { useState } from 'react'
import Sidebar from './layout/sidebar'
import Header from './layout/header'
import { ScrollArea } from '@/app/components/ui/scroll-area'
import { Toaster } from '@/app/components/ui/toaster'

interface MainLayoutClientProps {
  children: ReactNode
}

export function MainLayoutClient({ children }: MainLayoutClientProps) {
  const [open, setOpen] = useState<boolean>(false)

  const handleToggle = () => setOpen(prev => !prev)

  return (
    <div className='flex min-h-screen bg-background'>
      <Sidebar isOpen={open} handleToggle={handleToggle} />
      <div className='flex-1 flex flex-col transition-all duration-300'>
        <Header isSidebarOpen={open} handleOpenSidebar={handleToggle} />
        <ScrollArea className='flex-1'>
          <main
            className={
              `flex-1 p-2 sm:p-4 md:p-6 transition-all duration-300 ` +
              (open ? 'lg:ml-72' : 'lg:ml-20')
            }
          >
            {children}
          </main>
        </ScrollArea>
      </div>

      <Toaster />
    </div>
  )
}
