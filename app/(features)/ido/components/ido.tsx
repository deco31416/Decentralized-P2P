'use client'

import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { Input } from '@/app/components/ui/input'
import { Label } from '@/app/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/app/components/ui/select'
import { Progress } from '@/app/components/ui/progress'

export function IDO() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>IDO - Compra de Tokens</CardTitle>
      </CardHeader>
      <CardContent>
        <div className='grid grid-cols-1 md:grid-cols-2 gap-6'>
          <div>
            <h3 className='text-lg font-semibold mb-2'>Resumen del Token</h3>
            <p>Precio actual: $0.1 📈</p>
            <p>Circulante: 1,000,000 🪙</p>
            <p>Fondo recaudado: $100,000 💰</p>
            <p>Monedas aceptadas: BNB, ETH, USDT, USDC, DAI, XDAI</p>
          </div>
          <div>
            <h3 className='text-lg font-semibold mb-2'>Compra de Tokens</h3>
            <form className='space-y-4'>
              <div>
                <Label htmlFor='payment-method'>Método de pago</Label>
                <Select>
                  <SelectTrigger id='payment-method'>
                    <SelectValue placeholder='Selecciona moneda' />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value='bnb'>BNB</SelectItem>
                    <SelectItem value='eth'>ETH</SelectItem>
                    <SelectItem value='usdt'>USDT</SelectItem>
                    <SelectItem value='usdc'>USDC</SelectItem>
                    <SelectItem value='dai'>DAI</SelectItem>
                    <SelectItem value='xdai'>XDAI</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label htmlFor='amount'>Cantidad a comprar</Label>
                <Input id='amount' type='number' placeholder='0' />
              </div>
              <Button className='w-full'>Confirmar compra con MetaMask</Button>
            </form>
          </div>
        </div>
        <div className='mt-6'>
          <h3 className='text-lg font-semibold mb-2'>Progreso de la venta</h3>
          <Progress value={60} className='mb-2' />
          <p className='text-sm text-muted-foreground'>60% vendido</p>
        </div>
        <div className='mt-6 text-center'>
          <p className='text-lg font-semibold mb-2'>🎯 Stakea tu token y no pagues fees</p>
          <Button variant='outline'>Ir a Staking</Button>
        </div>
      </CardContent>
    </Card>
  )
}
