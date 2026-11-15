import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { cadBankTransfers } from './cad_bankTransfers'
import { cadElectronicPayments } from './cad_electronicPayments'

const cadInfo = uniqueFiat.find(fiat => fiat.id === 'cad')

if (!cadInfo) {
  throw new Error('CAD currency data not found in Fiat.')
}

export const cadPayment = {
  ...cadInfo,
  paymentMethods: {
    bankTransfers: cadBankTransfers,
    electronicPayments: cadElectronicPayments
  }
}
