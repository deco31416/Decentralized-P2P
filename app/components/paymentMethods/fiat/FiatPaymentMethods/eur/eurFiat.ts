import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { eurBankTransfers } from './eur_bankTransfers'
import { eurElectronicPayments } from './eur_electronicPayments'

const eurInfo = uniqueFiat.find(fiat => fiat.id === 'eur')

if (!eurInfo) {
  throw new Error('EUR currency data not found in Fiat.')
}

export const eurPayment = {
  ...eurInfo,
  paymentMethods: {
    bankTransfers: eurBankTransfers,
    electronicPayments: eurElectronicPayments
  }
}
