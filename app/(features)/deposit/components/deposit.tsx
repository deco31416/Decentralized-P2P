'use client'

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { Input } from '@/app/components/ui/input'
import { Label } from '@/app/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/app/components/ui/select'

export function Deposit() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Deposit</CardTitle>
        <CardDescription>Add funds to your account</CardDescription>
      </CardHeader>
      <CardContent>
        <form className='space-y-4'>
          <div className='space-y-2'>
            <Label htmlFor='amount'>Amount</Label>
            <Input id='amount' type='number' placeholder='0.00' />
          </div>
          <div className='space-y-2'>
            <Label htmlFor='currency'>Currency</Label>
            <Select>
              <SelectTrigger id='currency'>
                <SelectValue placeholder='Select currency' />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value='eth'>ETH</SelectItem>
                <SelectItem value='btc'>BTC</SelectItem>
                <SelectItem value='usdt'>USDT</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Button className='w-full'>Deposit</Button>
        </form>
      </CardContent>
    </Card>
  )
}
