import { useEffect, useState } from 'react'

export const SCREEN_BREAKPOINTS = Object.freeze({
    xs: 0,
    sm: 640,
    md: 768,
    lg: 1024,
    xl: 1280,
    "2xl": 1400,
})

export function useMediaQuery(mq: keyof typeof SCREEN_BREAKPOINTS) {
  const [matches, setMatches] = useState(false)

  useEffect(() => {
    if (typeof window === 'undefined') return
    const textMediaQuey = `(max-width: ${SCREEN_BREAKPOINTS[mq]}px)`
    const mediaQuery = window.matchMedia(textMediaQuey)
    setMatches(mediaQuery.matches)

    const handler = (e: MediaQueryListEvent) => setMatches(e.matches)
    mediaQuery.addEventListener('change', handler)

    return () => mediaQuery.removeEventListener('change', handler)
  }, [mq])

  return matches
}