'use client'

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/app/components/ui/card'

const data = [
  { date: '2024-01', price: 1.002 },
  { date: '2024-02', price: 0.998 },
  { date: '2024-03', price: 1.001 },
  { date: '2024-04', price: 0.999 },
  { date: '2024-05', price: 1.003 },
  { date: '2024-06', price: 1.0 }
]

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

export function PriceChart() {
  const values = data.map(d => d.price)
  const width = 600
  const height = 300
  const padding = 16
  const points = buildPolylinePoints(values, width, height, padding)

  return (
    <Card>
      <CardHeader>
        <CardTitle>Precio histórico</CardTitle>
        <CardDescription>Últimos 6 meses</CardDescription>
      </CardHeader>
      <CardContent className='pb-4'>
        <div className='h-[300px] w-full'>
          <svg
            viewBox={`0 0 ${width} ${height}`}
            role='img'
            aria-label='Precio histórico'
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
  )
}
