'use client'

import { ThumbsDown, ThumbsUp } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { Progress } from '@/app/components/ui/progress'
import { useState } from 'react'

function buildPolylinePoints(values: number[], width: number, height: number, padding: number): string {
  if (values.length === 0) return ''

  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = Math.max(0.000001, max - min)
  const innerWidth = Math.max(1, width - padding * 2)
  const innerHeight = Math.max(1, height - padding * 2)

  return values
    .map((value, index) => {
      const x = padding + (innerWidth * index) / Math.max(1, values.length - 1)
      const normalized = (value - min) / range
      const y = padding + innerHeight * (1 - normalized)
      return `${x.toFixed(2)},${y.toFixed(2)}`
    })
    .join(' ')
}

export function CryptoSentiment({ name }: { name: string }) {
  // Estado de votos
  const [goodVotes, setGoodVotes] = useState(21)
  const [badVotes, setBadVotes] = useState(7)
  const totalVotes = goodVotes + badVotes
  const goodPercentage = totalVotes > 0 ? (goodVotes / totalVotes) * 100 : 50
  const badPercentage = totalVotes > 0 ? (badVotes / totalVotes) * 100 : 50

  // Simulación de estadísticas de uso
  const usageData = [
    { day: 'Lun', usage: 10 },
    { day: 'Mar', usage: 15 },
    { day: 'Mié', usage: 12 },
    { day: 'Jue', usage: 18 },
    { day: 'Vie', usage: 25 },
    { day: 'Sáb', usage: 30 },
    { day: 'Dom', usage: 20 }
  ]

  const width = 600
  const height = 160
  const padding = 16
  const points = buildPolylinePoints(
    usageData.map(d => d.usage),
    width,
    height,
    padding
  )

  return (
    <div className='grid grid-cols-1 md:grid-cols-2 gap-6'>
      {/* Card de Votaciones con Barra de Progreso */}
      <Card className='flex-1'>
        <CardHeader>
          <CardTitle>¿Qué opinas de {name} hoy?</CardTitle>
        </CardHeader>
        <CardContent className='space-y-4'>
          {/* Botones con mejor interacción */}
          <div className='flex justify-center gap-4'>
            <Button
              variant='outline'
              className='flex items-center gap-2 px-6 py-3 hover:bg-green-500/20'
              onClick={() => setGoodVotes(prev => prev + 1)}
            >
              <ThumbsUp className='h-5 w-5 text-green-500' />
              <span>Bien</span>
            </Button>

            <Button
              variant='outline'
              className='flex items-center gap-2 px-6 py-3 hover:bg-red-500/20'
              onClick={() => setBadVotes(prev => prev + 1)}
            >
              <ThumbsDown className='h-5 w-5 text-red-500' />
              <span>Mal</span>
            </Button>
          </div>

          {/* Barra de Progreso Visual */}
          <div className='space-y-2'>
            <div className='flex justify-between text-sm'>
              <span className='text-green-500'>Bien ({goodVotes})</span>
              <span className='text-muted-foreground'>{goodPercentage.toFixed(1)}%</span>
            </div>
            <Progress value={goodPercentage} className='h-2 bg-green-500/30' />

            <div className='flex justify-between text-sm mt-2'>
              <span className='text-red-500'>Mal ({badVotes})</span>
              <span className='text-muted-foreground'>{badPercentage.toFixed(1)}%</span>
            </div>
            <Progress value={badPercentage} className='h-2 bg-red-500/30' />
          </div>

          {/* Total de votos */}
          <p className='text-center text-sm text-muted-foreground'>
            Total de votos: <span className='font-semibold'>{totalVotes}</span>
          </p>
        </CardContent>
      </Card>

      {/* Card de Estadísticas con Gráfico */}
      <Card className='flex-1'>
        <CardHeader>
          <CardTitle>Estadísticas de uso</CardTitle>
        </CardHeader>
        <CardContent>
          <div className='grid grid-cols-3 gap-4 text-center'>
            <div>
              <p className='text-2xl font-bold'>{usageData[6].usage}</p>
              <p className='text-sm text-muted-foreground'>Uso hoy</p>
            </div>
            <div>
              <p className='text-2xl font-bold'>80</p>
              <p className='text-sm text-muted-foreground'>Uso esta semana</p>
            </div>
            <div>
              <p className='text-2xl font-bold'>900</p>
              <p className='text-sm text-muted-foreground'>Uso este mes</p>
            </div>
          </div>

          {/* Gráfico de Línea */}
          <div className='mt-4 h-40'>
            <svg
              viewBox={`0 0 ${width} ${height}`}
              role='img'
              aria-label='Estadísticas de uso'
              className='h-full w-full'
            >
              <rect x='0' y='0' width={width} height={height} fill='transparent' />
              <line x1={padding} y1={height - padding} x2={width - padding} y2={height - padding} className='stroke-border' strokeWidth='1' />
              <line x1={padding} y1={padding} x2={padding} y2={height - padding} className='stroke-border' strokeWidth='1' />

              <g className='text-primary'>
                <polyline points={points} fill='none' stroke='currentColor' strokeWidth='3' strokeLinejoin='round' strokeLinecap='round' />
              </g>
            </svg>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
