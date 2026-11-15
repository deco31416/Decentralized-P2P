import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { awgBankTransfers } from './awg_bankTransfers'
import { awgElectronicPayments } from './awg_electronicPayments'

const awgInfo = uniqueFiat.find(fiat => fiat.id === 'awg')

if (!awgInfo) {
  throw new Error('AWG currency data not found in Fiat.')
}

export const awgPayment = {
  ...awgInfo,
  paymentMethods: {
    bankTransfers: awgBankTransfers,
    electronicPayments: awgElectronicPayments
  }
}
