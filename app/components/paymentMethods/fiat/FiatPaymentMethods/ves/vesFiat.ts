import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { vesBankTransfers } from './ves_bankTransfers'
import { vesElectronicPayments } from './ves_electronicPayments'

const vesInfo = uniqueFiat.find(fiat => fiat.id === 'ves')

if (!vesInfo) {
  throw new Error('VES currency data not found in Fiat.')
}

export const vesPayment = {
  ...vesInfo,
  paymentMethods: {
    bankTransfers: vesBankTransfers,
    electronicPayments: vesElectronicPayments
  }
}
