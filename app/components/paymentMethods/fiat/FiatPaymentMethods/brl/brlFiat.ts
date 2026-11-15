import { uniqueFiat } from '../../FiatMoney/uniqueFiat'
import { brlBankTransfers } from './brl_bankTransfers'
import { brlElectronicPayments } from './brl_electronicPayments'

const brlInfo = uniqueFiat.find(fiat => fiat.id === 'brl')

if (!brlInfo) {
  throw new Error('BRL currency data not found in Fiat.')
}

export const brlPayment = {
  ...brlInfo,
  paymentMethods: {
    bankTransfers: brlBankTransfers,
    electronicPayments: brlElectronicPayments
  }
}
