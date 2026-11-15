'use client'

import { PanelRightOpen, PanelsTopLeft, Bell, Moon, Sun, Globe, Menu } from 'lucide-react'
import { Button } from '@/app/components/ui/button'
import { useTheme } from 'next-themes'
import dynamic from 'next/dynamic'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger
} from '@/app/components/ui/dropdown-menu'
import { usePathname } from 'next/navigation'

const WalletConnect = dynamic(() => import('@/app/components/ConnectButton/WalletConnect.client'), {
  ssr: false,
  loading: () => (
    <Button variant='secondary' size='sm' disabled>
      Conectar
    </Button>
  )
})

interface HeaderProps {
  isSidebarOpen: boolean
  handleOpenSidebar: () => void
}

export default function Header({ handleOpenSidebar, isSidebarOpen }: HeaderProps) {
  const { resolvedTheme, setTheme } = useTheme()
  const pathname = usePathname()
  const title = pathname
    .split('/')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')

  return (
    <header
      className={`sticky top-0 z-30 bg-background border-b border-border transition-all duration-300 ml-0 ${
        isSidebarOpen ? 'lg:ml-72' : 'lg:ml-20'
      }`}
    >
      <div className='flex h-16 items-center px-2 sm:px-4 gap-2 sm:gap-4'>
        {/* Botón de menú para abrir/cerrar sidebar */}
        <Button variant='ghost' size='icon' onClick={handleOpenSidebar} className='z-50 transition-all'>
          <Menu className='h-5 w-5 lg:hidden' />
          {isSidebarOpen ? (
            <PanelRightOpen className='h-5 w-5 hidden lg:block' />
          ) : (
            <PanelsTopLeft className='h-5 w-5 hidden lg:block' />
          )}
        </Button>

        {/* Título alineado dinámicamente */}
        <div className='flex-1 overflow-hidden'>
          <h1 className='text-lg sm:text-xl font-semibold truncate'>{title}</h1>
        </div>

        {/* Botones de notificaciones, tema e idioma */}
        <div className='flex items-center gap-1 sm:gap-4'>
          {/* Notificaciones */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant='ghost' size='icon' className='relative'>
                <Bell className='h-5 w-5' />
                <span className='absolute top-1 right-1 w-2 h-2 bg-red-500 rounded-full' />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align='end'>
              <DropdownMenuLabel>Notificaciones</DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem>Nuevo pedido recibido</DropdownMenuItem>
              <DropdownMenuItem>Operación completada</DropdownMenuItem>
              <DropdownMenuItem>Disputa resuelta</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>

          {/* Botón de cambio de tema */}
          <Button
            variant='ghost'
            size='icon'
            onClick={() => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')}
            aria-label='Cambiar tema'
          >
            <Sun className='h-5 w-5 hidden dark:block' />
            <Moon className='h-5 w-5 block dark:hidden' />
          </Button>

          {/* Botón de cambio de idioma - Oculto en móviles muy pequeños */}
          <div className='hidden xs:block'>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant='ghost' size='icon'>
                  <Globe className='h-5 w-5' />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align='end'>
                <DropdownMenuItem onClick={() => changeLanguage('es')}>ES · Español</DropdownMenuItem>
                <DropdownMenuItem onClick={() => changeLanguage('en')}>EN · English</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>

          {/* Conexión a la Wallet con Thirdweb */}
          <WalletConnect />
        </div>
      </div>
    </header>
  )
}

/** 🔥 Función mejorada para cambiar idioma sin recargar la página */
function changeLanguage(lang: string) {
  try {
    if (typeof window === 'undefined') return

    localStorage.setItem('language', lang)
    window.dispatchEvent(new CustomEvent('languageChange', { detail: { lang } }))

    console.log(`Idioma cambiado a: ${lang}`)
  } catch (error) {
    console.error('Error cambiando idioma:', error)
  }
}
