import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { penBankTransfers } from './pen_bankTransfers'
import { penElectronicPayments } from './pen_electronicPayments'

const penInfo = uniqueFiat.find(fiat => fiat.id === 'pen')

if (!penInfo) {
  throw new Error('PEN currency data not found in Fiat.')
}

export const penPayment = {
  ...penInfo,
  paymentMethods: {
    bankTransfers: penBankTransfers,
    electronicPayments: penElectronicPayments
  }
}
