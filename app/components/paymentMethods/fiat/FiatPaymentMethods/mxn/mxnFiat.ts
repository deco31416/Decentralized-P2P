import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { mxnBankTransfers } from './mxn_bankTransfers'
import { mxnElectronicPayments } from './mxn_electronicPayments'

const mxnInfo = uniqueFiat.find(fiat => fiat.id === 'mxn')

if (!mxnInfo) {
  throw new Error('MXN currency data not found in Fiat.')
}

export const mxnPayment = {
  ...mxnInfo,
  paymentMethods: {
    bankTransfers: mxnBankTransfers,
    electronicPayments: mxnElectronicPayments
  }
}
