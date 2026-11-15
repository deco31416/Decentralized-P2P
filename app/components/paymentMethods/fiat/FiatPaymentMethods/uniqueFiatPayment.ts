import { usdPayment } from './usd/usdFiat'
import { copPayment } from './cop/copFiat'
import { vesPayment } from './ves/vesFiat'
import { cadPayment } from './cad/cadFiat'
import { mxnPayment } from './mxn/mxnFiat'
import { brlPayment } from './brl/brlFiat'
import { arsPayment } from './ars/arsFiat'
import { clpPayment } from './clp/clpFiat'
import { penPayment } from './pen/penFiat'
import { dopPayment } from './dop/dopFiat'
import { svcPayment } from './svc/svcFiat'
import { awgPayment } from './awg/awgFiat'
import { eurPayment } from './eur/eurFiat'

export const uniqueFiatPayment = [
  usdPayment,
  copPayment,
  vesPayment,
  cadPayment,
  mxnPayment,
  brlPayment,
  arsPayment,
  clpPayment,
  penPayment,
  dopPayment,
  svcPayment,
  awgPayment,
  eurPayment
]
