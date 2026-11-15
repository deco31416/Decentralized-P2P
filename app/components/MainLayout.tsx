import type { ReactNode } from 'react'
import { MainLayoutClient } from './MainLayoutClient'

interface MainLayoutProps {
  children: ReactNode
}

export function MainLayout({ children }: MainLayoutProps) {
  return <MainLayoutClient>{children}</MainLayoutClient>
}
