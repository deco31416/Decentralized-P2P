'use client'

import { useState, useEffect } from 'react'
import { useToast } from '@/app/hooks/use-toast'
import { LegalDisclaimer } from './components/legal-disclaimer.component'
import { LoadingScreen } from './components/loading-screen.component'

export default function DashboardLayout({ children }: { children: React.ReactNode }): JSX.Element {
  const [showDisclaimer, setShowDisclaimer] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const { toast } = useToast()

  useEffect(() => {
    if (typeof window === 'undefined') return

    try {
      const hasAcceptedDisclaimer = localStorage.getItem('disclaimerAccepted') === 'true'
      if (!hasAcceptedDisclaimer) {
        setShowDisclaimer(true)
      }
    } catch (error) {
      console.error('Error accessing localStorage:', error)
      setShowDisclaimer(true)
    } finally {
      setIsLoading(false)
    }
  }, [])

  if (isLoading) {
    return <LoadingScreen />
  }

  return (
    <>
      {showDisclaimer && (
        <LegalDisclaimer
          onAccept={() => {
            setShowDisclaimer(false)
            toast({
              title: 'Bienvenido',
              description: 'Has aceptado los términos y condiciones.',
              variant: 'default'
            })
          }}
        />
      )}

      <div className='relative'>{children}</div>
    </>
  )
}
