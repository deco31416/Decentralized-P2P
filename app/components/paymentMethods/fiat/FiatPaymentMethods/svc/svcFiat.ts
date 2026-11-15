import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { svcBankTransfers } from './svc_bankTransfers'
import { svcElectronicPayments } from './svc_electronicPayments'

const svcInfo = uniqueFiat.find(fiat => fiat.id === 'svc')

if (!svcInfo) {
  throw new Error('SVC currency data not found in Fiat.')
}

export const svcPayment = {
  ...svcInfo,
  paymentMethods: {
    bankTransfers: svcBankTransfers,
    electronicPayments: svcElectronicPayments
  }
}
