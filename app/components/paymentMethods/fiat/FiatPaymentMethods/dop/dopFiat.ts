import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { dopBankTransfers } from './dop_bankTransfers'
import { dopElectronicPayments } from './dop_electronicPayments'

const dopInfo = uniqueFiat.find(fiat => fiat.id === 'dop')

if (!dopInfo) {
  throw new Error('DOP currency data not found in Fiat.')
}

export const dopPayment = {
  ...dopInfo,
  paymentMethods: {
    bankTransfers: dopBankTransfers,
    electronicPayments: dopElectronicPayments
  }
}
