import { useEffect, useRef } from 'react'
import { useActiveWallet, useDisconnect } from 'thirdweb/react'
import { useToast } from '@/app/hooks/use-toast'

const useInactivityLogout = (timeout = 1800000) => {
  const wallet = useActiveWallet()
  const { disconnect } = useDisconnect()
  const { toast } = useToast()
  const activityTimeout = useRef<ReturnType<typeof setTimeout> | null>(null)
  const warningTimeout = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    const showWarning = () => {
      toast({
        title: 'Inactividad detectada',
        description: 'Serás desconectado en 60 segundos. Mueve el mouse para continuar.',
        duration: 60000,
        variant: 'destructive'
      })
    }

    const performLogout = () => {
      if (wallet) {
        disconnect(wallet)
        toast({
          title: 'Sesión cerrada',
          description: 'Has sido desconectado por inactividad.',
          variant: 'destructive'
        })
      }
    }

    const resetTimeout = () => {
      if (activityTimeout.current) clearTimeout(activityTimeout.current)
      if (warningTimeout.current) clearTimeout(warningTimeout.current)

      if (wallet) {
        warningTimeout.current = setTimeout(showWarning, timeout - 60000)
        activityTimeout.current = setTimeout(performLogout, timeout)
      }
    }

    const handleActivity = () => {
      resetTimeout()
    }

    const events = ['mousemove', 'keydown', 'scroll', 'click', 'touchstart']
    events.forEach(event => {
      window.addEventListener(event, handleActivity)
    })

    resetTimeout()

    return () => {
      events.forEach(event => {
        window.removeEventListener(event, handleActivity)
      })
      if (activityTimeout.current) clearTimeout(activityTimeout.current)
      if (warningTimeout.current) clearTimeout(warningTimeout.current)
    }
  }, [wallet, disconnect, timeout, toast])

  return null
}

export default useInactivityLogout
