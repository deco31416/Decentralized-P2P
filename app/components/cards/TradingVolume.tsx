import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem
} from '@/app/components/ui/dropdown-menu'
import { Button } from '@/app/components/ui/button'
import { CalendarDays, CalendarRange, ChevronDown, Calendar } from 'lucide-react'

export default function TradingVolume() {
  const [timeFrame, setTimeFrame] = useState('Weekly')

  // Datos para cada intervalo de tiempo
  const dataByDay = [
    { name: '00:00', volume: 40 },
    { name: '06:00', volume: 100 },
    { name: '12:00', volume: 160 },
    { name: '18:00', volume: 120 },
    { name: '23:59', volume: 80 }
  ]

  const dataByWeek = [
    { name: 'Lun', volume: 300 },
    { name: 'Mar', volume: 350 },
    { name: 'Mié', volume: 200 },
    { name: 'Jue', volume: 500 },
    { name: 'Vie', volume: 400 },
    { name: 'Sáb', volume: 450 },
    { name: 'Dom', volume: 320 }
  ]

  const dataByMonth = [
    { name: 'Semana 1', volume: 1200 },
    { name: 'Semana 2', volume: 1400 },
    { name: 'Semana 3', volume: 1100 },
    { name: 'Semana 4', volume: 1700 }
  ]

  // Selección de datos según el periodo
  const chartData = timeFrame === 'Daily' ? dataByDay : timeFrame === 'Weekly' ? dataByWeek : dataByMonth
  const maxVolume = Math.max(...chartData.map(d => d.volume), 1)

  return (
    <Card className='shadow-lg border border-border'>
      <CardHeader className='flex justify-start items-start gap-x-4'>
        {/* Título también alineado a la izquierda */}
        <CardTitle className='mb-4'>Trading Volume</CardTitle>
        {/* Dropdown Menu alineado a la izquierda */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant='outline' className='flex items-start gap-2 w-32'>
              {timeFrame} <ChevronDown className='h-4 w-4' />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align='start'>
            <DropdownMenuItem onClick={() => setTimeFrame('Daily')}>
              <CalendarDays className='h-4 w-4 mr-2' />
              Día
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setTimeFrame('Weekly')}>
              <CalendarRange className='h-4 w-4 mr-2' />
              Semana
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setTimeFrame('Monthly')}>
              <Calendar className='h-4 w-4 mr-2' />
              Mes
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </CardHeader>

      <CardContent className='p-4'>
        <div className='h-[300px] w-full flex items-end gap-2'>
          {chartData.map(point => {
            const heightPct = Math.max(2, Math.round((point.volume / maxVolume) * 100))
            return (
              <div key={point.name} className='flex-1 flex flex-col items-center justify-end gap-2'>
                <div className='w-full flex items-end justify-center'>
                  <div
                    title={`${point.name}: ${point.volume.toLocaleString()}`}
                    className='w-full max-w-10 bg-primary/80 rounded-t-md transition-[height]'
                    style={{ height: `${heightPct}%` }}
                  />
                </div>
                <div className='text-xs text-muted-foreground truncate w-full text-center'>{point.name}</div>
              </div>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}
