import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { arsBankTransfers } from './ars_bankTransfers'
import { arsElectronicPayments } from './ars_electronicPayments'

const arsInfo = uniqueFiat.find(fiat => fiat.id === 'ars')

if (!arsInfo) {
  throw new Error('ARS currency data not found in Fiat.')
}

export const arsPayment = {
  ...arsInfo,
  paymentMethods: {
    bankTransfers: arsBankTransfers,
    electronicPayments: arsElectronicPayments
  }
}
