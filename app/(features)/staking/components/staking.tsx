'use client'

import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { Input } from '@/app/components/ui/input'
import { Label } from '@/app/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/app/components/ui/select'

export function Staking() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Staking</CardTitle>
      </CardHeader>
      <CardContent>
        <div className='grid grid-cols-1 md:grid-cols-2 gap-6'>
          <div>
            <h3 className='text-lg font-semibold mb-2'>Resumen de beneficios</h3>
            <ul className='list-disc list-inside space-y-1'>
              <li>Inversión mínima: $100 en tokens</li>
              <li>Duración del staking: 1 año</li>
              <li>Reducción progresiva de fees (hasta 0%)</li>
              <li>Recompensas acumuladas: $50</li>
              <li>Monto mínimo de retiro: $3</li>
            </ul>
          </div>
          <div>
            <h3 className='text-lg font-semibold mb-2'>Formulario de staking</h3>
            <form className='space-y-4'>
              <div>
                <Label htmlFor='stake-amount'>Cantidad a stakear</Label>
                <Input id='stake-amount' type='number' placeholder='0' />
              </div>
              <div>
                <Label htmlFor='stake-time'>Tiempo de staking</Label>
                <Select>
                  <SelectTrigger id='stake-time'>
                    <SelectValue placeholder='Selecciona duración' />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value='3'>3 meses</SelectItem>
                    <SelectItem value='6'>6 meses</SelectItem>
                    <SelectItem value='12'>1 año</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <Button className='w-full'>Confirmar staking con MetaMask</Button>
            </form>
          </div>
        </div>
        <div className='mt-6'>
          <h3 className='text-lg font-semibold mb-2'>Panel de recompensas</h3>
          <p>Saldo acumulado: $50</p>
          <p>Historial de ganancias: +$2 esta semana</p>
          <Button className='mt-2'>Retirar ganancias 💸</Button>
        </div>
        <div className='mt-6 text-center'>
          <p className='text-lg font-semibold mb-2'>🎯 Stakea más para reducir fees aún más</p>
          <Button variant='outline'>Aumentar staking</Button>
        </div>
      </CardContent>
    </Card>
  )
}
