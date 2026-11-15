import { useRouter } from 'next/router'
import React, { useEffect, useState } from 'react'
import { FiatPaymentMethods } from '@/app/components/paymentMethods/fiat/FiatPaymentMethods/FiatPaymentMethods'
import Image from 'next/image'

type PaymentMethodType = 'bankTransfers' | 'electronicPayments'

interface PaymentMethod {
  id: string
  name: string
  icon: string
}

interface PaymentMethodListProps {
  countryCode: string // Ya no es un tipo restringido ('usd' | 'cop' ...), es dinámico.
  methodType: PaymentMethodType
}

export default function FiatPaymentMethodsList({ countryCode, methodType }: PaymentMethodListProps) {
  const router = useRouter()
  const [methods, setMethods] = useState<PaymentMethod[]>([])

  useEffect(() => {
    // Obtén los métodos de pago de la moneda y tipo de pago especificado
    const countryData = FiatPaymentMethods[countryCode] // Accedemos a la moneda de forma dinámica

    if (countryData) {
      const selectedMethods = countryData.paymentMethods[methodType] || []
      setMethods(selectedMethods)
    }
  }, [countryCode, methodType]) // Se vuelve a ejecutar cuando cambian countryCode o methodType

  const handleClick = (methodId: string) => {
    // Redirige al detalle del método de pago
    router.push(`/app/payments/${countryCode}/${methodType}/${methodId}`)
  }

  return (
    <div>
      <h2>{methodType === 'bankTransfers' ? 'Transferencias Bancarias' : 'Pagos Electrónicos'}</h2>
      <ul>
        {methods.length > 0 ? (
          methods.map(method => (
            <li key={method.id}>
              <button onClick={() => handleClick(method.id)} className='flex items-center'>
                <Image src={method.icon} alt={method.name} className='icon' width={40} height={40} />
                {method.name}
              </button>
            </li>
          ))
        ) : (
          <p>No se encontraron métodos de pago disponibles.</p>
        )}
      </ul>
    </div>
  )
}
