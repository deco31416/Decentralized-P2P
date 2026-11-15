'use client'

import { useState, useCallback, useMemo, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { Input } from '@/app/components/ui/input'
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem
} from '@/app/components/ui/dropdown-menu'
import { Progress } from '@/app/components/ui/progress'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/app/components/ui/tabs'
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
import { ChevronDown, ArrowRight, DollarSign, Coins, Banknote, CheckCircle } from 'lucide-react'

const CURRENCIES = ['USD', 'COP', 'MXN', 'VES', 'EUR']
const STABLECOINS = ['USDT', 'USDC', 'DAI', 'FDUSD', 'XDAI']

type CurrencyDropdownProps = {
  value: string
  onChange: (value: string) => void
  options: string[]
  label: string
}

const CurrencyDropdown = ({ value, onChange, options, label }: CurrencyDropdownProps) => (
  <div className='flex flex-col space-y-2'>
    <label htmlFor={`${label}-dropdown`} className='text-sm font-medium'>
      {label}
    </label>
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button id={`${label}-dropdown`} variant='outline' className='w-full flex items-center justify-between'>
          {value} <ChevronDown className='h-4 w-4' />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align='start'>
        {options.map(option => (
          <DropdownMenuItem key={option} onClick={() => onChange(option)}>
            {option}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  </div>
)

const ExchangeStep = ({
  icon: Icon,
  title,
  description,
  status
}: {
  icon: React.ComponentType<{ className?: string }>
  title: string
  description: string
  status: 'pending' | 'active' | 'completed'
}) => (
  <div
    className={`flex items-center space-x-4 p-4 rounded-lg transition-all ${
      status === 'active'
        ? 'bg-blue-100 dark:bg-blue-900'
        : status === 'completed'
        ? 'bg-green-100 dark:bg-green-900'
        : 'bg-gray-100 dark:bg-gray-800'
    }`}
  >
    <div
      className={`p-2 rounded-full ${
        status === 'active' ? 'bg-blue-500' : status === 'completed' ? 'bg-green-500' : 'bg-gray-500'
      }`}
    >
      <Icon className='h-6 w-6 text-white' />
    </div>
    <div>
      <h3 className='font-semibold'>{title}</h3>
      <p className='text-sm text-gray-600 dark:text-gray-300'>{description}</p>
    </div>
    {status === 'completed' && <CheckCircle className='h-5 w-5 text-green-500 ml-auto' />}
  </div>
)

export default function FiatToFiatExchange() {
  const [exchangeState, setExchangeState] = useState({
    amount: '',
    fromCurrency: 'USD',
    stablecoin: 'USDT',
    toCurrency: 'COP'
  })
  const [step, setStep] = useState(0)
  const [error, setError] = useState('')
  const { toast } = useToast()

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value

    if (value === '') {
      setExchangeState(prev => ({ ...prev, amount: value }))
      setError('')
      return
    }

    const numValue = Number(value)

    if (!/^\d+\.?\d{0,2}$/.test(value)) {
      setError('Solo números con hasta 2 decimales')
      return
    }

    if (numValue <= 0) {
      setError('El monto debe ser mayor a 0')
      return
    }

    if (numValue > 1000000) {
      setError('Monto máximo: 1,000,000')
      return
    }

    if (!Number.isFinite(numValue) || Number.isNaN(numValue)) {
      setError('Número inválido')
      return
    }

    setExchangeState(prev => ({ ...prev, amount: value }))
    setError('')
  }, [])

  const updateCurrency = useCallback(
    (key: keyof typeof exchangeState) => (value: string) => {
      setExchangeState(prev => ({ ...prev, [key]: value }))
    },
    []
  )

  const startExchange = useCallback(() => {
    if (!exchangeState.amount || Number.parseFloat(exchangeState.amount) <= 0) {
      setError('Please enter a valid amount greater than zero.')
      return
    }
    setError('')
    setStep(1)
    toast({
      title: 'Exchange Started',
      description: `Converting ${exchangeState.fromCurrency} to ${exchangeState.stablecoin}`
    })
  }, [exchangeState, toast])

  // Manejar progresión de steps con cleanup
  useEffect(() => {
    if (step === 0) return

    const timers: NodeJS.Timeout[] = []

    if (step === 1) {
      const timer = setTimeout(() => {
        setStep(2)
        toast({
          title: 'Stablecoin Acquired',
          description: `${exchangeState.stablecoin} acquired, proceeding to final conversion`
        })
      }, 3000)
      timers.push(timer)
    }

    if (step === 2) {
      const timer = setTimeout(() => {
        setStep(3)
        toast({
          title: 'Exchange Completed',
          description: `Successfully exchanged to ${exchangeState.toCurrency}`
        })
      }, 3000)
      timers.push(timer)
    }

    return () => {
      timers.forEach(timer => clearTimeout(timer))
    }
  }, [step, exchangeState, toast])

  const exchangeSteps = useMemo(
    () => [
      { icon: DollarSign, title: 'Initiate Exchange', description: 'Preparing to start the exchange process' },
      {
        icon: Coins,
        title: 'Convert to Stablecoin',
        description: `Converting ${exchangeState.fromCurrency} to ${exchangeState.stablecoin}`
      },
      {
        icon: Banknote,
        title: 'Convert to Target Currency',
        description: `Converting ${exchangeState.stablecoin} to ${exchangeState.toCurrency}`
      },
      { icon: CheckCircle, title: 'Exchange Completed', description: 'Transaction finalized and funds transferred' }
    ],
    [exchangeState]
  )

  return (
    // <Card className="w-full max-w-2xl mx-auto">
    <Card>
      <CardHeader>
        <CardTitle>Fiat-to-Fiat Exchange</CardTitle>
        <CardDescription>Exchange your fiat currency through stablecoin intermediary</CardDescription>
      </CardHeader>

      <CardContent className='space-y-6'>
        <Tabs defaultValue='exchange' className='w-full'>
          <TabsList className='grid w-full grid-cols-2'>
            <TabsTrigger value='exchange'>Exchange</TabsTrigger>
            <TabsTrigger value='info'>How it works</TabsTrigger>
          </TabsList>
          <TabsContent value='exchange'>
            <div className='space-y-4'>
              <div>
                <label htmlFor='amount-input' className='block text-sm font-medium mb-2'>
                  Amount
                </label>
                <Input
                  id='amount-input'
                  type='text'
                  inputMode='decimal'
                  placeholder='E.g. 1000'
                  value={exchangeState.amount}
                  onChange={handleInputChange}
                  onKeyDown={e => {
                    if (['e', 'E', '-', '+'].includes(e.key)) {
                      e.preventDefault()
                    }
                  }}
                  aria-describedby='amount-error'
                />
                {error && (
                  <p id='amount-error' className='text-red-500 text-sm mt-1'>
                    {error}
                  </p>
                )}
              </div>

              <div className='grid grid-cols-1 sm:grid-cols-3 gap-4 items-center'>
                <CurrencyDropdown
                  label='From'
                  value={exchangeState.fromCurrency}
                  onChange={updateCurrency('fromCurrency')}
                  options={CURRENCIES}
                />
                <div className='flex justify-center'>
                  <ArrowRight className='h-6 w-6' />
                </div>
                <CurrencyDropdown
                  label='To'
                  value={exchangeState.toCurrency}
                  onChange={updateCurrency('toCurrency')}
                  options={CURRENCIES}
                />
              </div>

              <div>
                <label className='block text-sm font-medium mb-2'>Via Stablecoin</label>
                <CurrencyDropdown
                  label='Stablecoin'
                  value={exchangeState.stablecoin}
                  onChange={updateCurrency('stablecoin')}
                  options={STABLECOINS}
                />
              </div>

              <div className='space-y-2'>
                <Progress value={(step / 3) * 100} className='h-2' />
              </div>

              <AlertDialog>
                <AlertDialogTrigger asChild>
                  <Button className='w-full py-3' disabled={!!error || step > 0}>
                    {step === 0 ? 'Start Exchange' : 'Exchange in Progress'}
                  </Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Confirm Exchange</AlertDialogTitle>
                  </AlertDialogHeader>
                  <p>
                    Are you sure you want to exchange {exchangeState.amount} {exchangeState.fromCurrency} to{' '}
                    {exchangeState.toCurrency} via {exchangeState.stablecoin}?
                  </p>
                  <AlertDialogFooter>
                    <AlertDialogCancel>Cancel</AlertDialogCancel>
                    <AlertDialogAction onClick={startExchange}>Confirm</AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>

              <div className='space-y-4 mt-6'>
                {exchangeSteps.map((exchangeStep, index) => (
                  <ExchangeStep
                    key={index}
                    icon={exchangeStep.icon}
                    title={exchangeStep.title}
                    description={exchangeStep.description}
                    status={index < step ? 'completed' : index === step ? 'active' : 'pending'}
                  />
                ))}
              </div>
            </div>
          </TabsContent>
          <TabsContent value='info'>
            <div className='space-y-4'>
              <h3 className='text-lg font-semibold'>How Fiat-to-Fiat Exchange Works</h3>
              <ol className='list-decimal list-inside space-y-2'>
                <li>You select the amount and currencies for exchange.</li>
                <li>We convert your initial fiat currency to a stablecoin.</li>
                <li>The stablecoin is then converted to your desired fiat currency.</li>
                <li>We handle the custody and ensure secure transactions throughout the process.</li>
              </ol>
              <p>
                This triangular exchange allows for efficient cross-border transactions using cryptocurrency as an
                intermediary.
              </p>
            </div>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}
