'use client'

import { useState } from 'react'
import { Settings, X } from 'lucide-react'
import { ScrollArea } from '@/app/components/ui/scroll-area'
import { Button } from '@/app/components/ui/button'
import { cn } from '@/lib/utils'
import { usePathname, useRouter } from 'next/navigation'
import { useNavigationItems } from '@/app/settings-config/navigation-items.setting'
import Image from 'next/image'

interface SidebarProps {
  isOpen: boolean
  handleToggle: () => void
}

export default function Sidebar({ isOpen, handleToggle }: SidebarProps) {
  const pathname = usePathname()
  const router = useRouter()
  const [isPinned] = useState(false)
  const navigationItems = useNavigationItems()
  const isNavigationLinkActive = (path: string) => pathname === path

  const isMobileViewport = () => {
    if (typeof window === 'undefined') return false
    return window.matchMedia('(max-width: 1024px)').matches
  }

  const handleRedirect = (path: string) => {
    router.push(`${path}`)
    if (isMobileViewport()) {
      handleToggle()
    }
  }

  return (
    <div
      className={cn(
        'fixed left-0 top-0 z-50 h-screen backdrop-blur-lg bg-card/80 border-r border-border shadow-lg transition-all duration-300 ease-in-out',
        isOpen ? 'w-full sm:w-72 lg:w-72' : 'w-0 -translate-x-full lg:w-20 lg:translate-x-0',
        isPinned && 'shadow-xl'
      )}
    >
      <div className='flex h-full flex-col'>
        {/* Logo y Título */}
        <div className='flex items-center justify-between gap-3 p-4 border-b border-border'>
          <div className='flex items-center gap-3'>
            <Image
              alt='Logo'
              width={32}
              height={32}
              src='/black.png'
              className='h-8 w-8 transition-all duration-300 block dark:hidden'
            />
            <Image
              src='/white.png'
              alt='Logo'
              width={32}
              height={32}
              className='h-8 w-8 transition-all duration-300 hidden dark:block'
            />
            {isOpen && <span className='text-lg font-semibold tracking-wide'>CambiaCripto</span>}
          </div>
          {isOpen && (
            <Button variant='ghost' size='icon' onClick={() => handleToggle()} className='lg:hidden'>
              <X className='h-5 w-5' />
            </Button>
          )}
        </div>

        {/* Menú de Navegación */}
        <ScrollArea className='flex-1 p-2 pr-6'>
          <nav className='space-y-1'>
            {navigationItems.map(item => (
              <Button
                key={item.path}
                variant={isNavigationLinkActive(item.path) ? 'secondary' : 'ghost'}
                className={cn(
                  'w-full flex items-center justify-start px-4 py-3 rounded-lg hover:bg-accent transition-all',
                  !isOpen && 'justify-center px-0'
                )}
                onClick={() => handleRedirect(item.path)}
              >
                <item.icon className='h-5 w-5' />
                {isOpen && <span className='ml-3 text-sm sm:text-base'>{item.text}</span>}
              </Button>
            ))}
          </nav>
        </ScrollArea>

        {/* Separador */}
        <div className='w-full h-0.5 bg-border my-2'></div>

        {/* Sección Inferior - Settings & Pin Sidebar */}
        <div className='w-full p-4 flex flex-col gap-3'>
          {/* Botón de Settings */}
          <Button
            variant='outline'
            size='icon'
            onClick={() => handleRedirect('/settings')}
            className={cn(
              'w-full flex items-center justify-start px-4 py-3 rounded-lg hover:bg-accent transition-all',
              !isOpen && 'justify-center px-0'
            )}
          >
            <Settings className='h-5 w-5' />
            {isOpen && <span className='ml-3 text-sm sm:text-base'>Settings</span>}
          </Button>
        </div>
      </div>
    </div>
  )
}
