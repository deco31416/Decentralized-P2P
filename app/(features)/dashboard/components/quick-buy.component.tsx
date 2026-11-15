'use client'

import { useState } from 'react'
import { Button } from '@/app/components/ui/button'
import { Input } from '@/app/components/ui/input'
import { Label } from '@/app/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/app/components/ui/select'
import { ArrowRightLeft } from 'lucide-react'
import { useToast } from '@/app/hooks/use-toast'
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogFooter,
  AlertDialogTitle,
  AlertDialogTrigger,
  AlertDialogCancel,
  AlertDialogAction
} from '@/app/components/ui/alert-dialog'

export function QuickBuy(): JSX.Element {
  const [fromCurrency, setFromCurrency] = useState('USD')
  const [toCurrency, setToCurrency] = useState('USDT')
  const [amount, setAmount] = useState('')
  const [estimatedReceive, setEstimatedReceive] = useState('0')
  const [open, setOpen] = useState(false)
  const { toast } = useToast()

  const handleSwap = () => {
    setFromCurrency(toCurrency)
    setToCurrency(fromCurrency)
    toast({
      title: 'Monedas intercambiadas',
      description: `Has cambiado de ${fromCurrency} a ${toCurrency}.`,
      variant: 'default'
    })
  }

  const handleAmountChange = (value: string) => {
    const numValue = parseFloat(value)
    if (isNaN(numValue) || numValue <= 0) {
      setAmount('')
      setEstimatedReceive('0')
      return
    }
    setAmount(value)
    setEstimatedReceive((numValue * 0.99).toFixed(2))
  }

  const handleConfirmBuy = () => {
    setOpen(false)

    if (!amount || parseFloat(amount) <= 0) {
      toast({
        title: 'Error',
        description: 'Debes ingresar una cantidad válida para comprar.',
        variant: 'destructive'
      })
      return
    }

    toast({
      title: 'Compra en proceso',
      description: `Comprando ${amount} ${fromCurrency} en ${toCurrency}...`,
      variant: 'default'
    })

    setTimeout(() => {
      toast({
        title: 'Compra exitosa',
        description: `Has comprado ${amount} ${fromCurrency} y recibirás ${estimatedReceive} ${toCurrency}.`,
        variant: 'default'
      })
    }, 2000)
  }

  const handleCancelBuy = () => {
    setOpen(false)
    toast({
      title: 'Operación cancelada',
      description: 'Has cancelado la compra.',
      variant: 'destructive'
    })
  }

  return (
    <div className='space-y-4'>
      <div className='grid grid-cols-1 md:grid-cols-2 gap-4'>
        <div className='space-y-2'>
          <Label htmlFor='fromAmount'>Tú pagas</Label>
          <div className='flex space-x-2'>
            <Input
              id='fromAmount'
              type='number'
              placeholder='0.00'
              value={amount}
              onChange={e => handleAmountChange(e.target.value)}
              min='0'
            />
            <Select value={fromCurrency} onValueChange={setFromCurrency}>
              <SelectTrigger className='w-[100px]'>
                <SelectValue placeholder='Moneda' />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value='USD'>USD</SelectItem>
                <SelectItem value='EUR'>EUR</SelectItem>
                <SelectItem value='GBP'>GBP</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <div className='space-y-2'>
          <Label htmlFor='toAmount'>Recibes (estimado)</Label>
          <div className='flex space-x-2'>
            <Input id='toAmount' type='number' placeholder='0.00' value={estimatedReceive} readOnly />
            <Select value={toCurrency} onValueChange={setToCurrency}>
              <SelectTrigger className='w-[100px]'>
                <SelectValue placeholder='Moneda' />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value='USDT'>USDT</SelectItem>
                <SelectItem value='BTC'>BTC</SelectItem>
                <SelectItem value='ETH'>ETH</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
      </div>
      <div className='flex justify-center'>
        <Button variant='outline' size='icon' onClick={handleSwap}>
          <ArrowRightLeft className='h-4 w-4' />
        </Button>
      </div>

      <AlertDialog open={open} onOpenChange={setOpen}>
        <AlertDialogTrigger asChild>
          <Button className='w-full' disabled={!amount || parseFloat(amount) <= 0}>
            Comprar ahora
          </Button>
        </AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Confirmar compra</AlertDialogTitle>
            <p>
              ¿Estás seguro de que deseas comprar {amount} {fromCurrency} en {toCurrency}?
            </p>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={handleCancelBuy}>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleConfirmBuy}>Confirmar</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
