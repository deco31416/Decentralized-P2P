import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { clpBankTransfers } from './clp_bankTransfers'
import { clpElectronicPayments } from './clp_electronicPayments'

const clpInfo = uniqueFiat.find(fiat => fiat.id === 'clp')

if (!clpInfo) {
  throw new Error('CLP currency data not found in Fiat.')
}

export const clpPayment = {
  ...clpInfo,
  paymentMethods: {
    bankTransfers: clpBankTransfers,
    electronicPayments: clpElectronicPayments
  }
}
