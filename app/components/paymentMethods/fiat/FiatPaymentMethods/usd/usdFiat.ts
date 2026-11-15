import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { usdBankTransfers } from './usd_bankTransfers'
import { usdElectronicPayments } from './usd_electronicPayments'

const usdInfo = uniqueFiat.find(fiat => fiat.id === 'usd')

if (!usdInfo) {
  throw new Error('USD currency data not found in Fiat.')
}

export const usdPayment = {
  ...usdInfo,
  paymentMethods: {
    bankTransfers: usdBankTransfers,
    electronicPayments: usdElectronicPayments
  }
}
