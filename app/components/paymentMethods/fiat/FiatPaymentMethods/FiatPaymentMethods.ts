import { uniqueFiat } from '../FiatMoney/uniqueFiat'

import { usdBankTransfers } from './usd/usd_bankTransfers'
import { usdElectronicPayments } from './usd/usd_electronicPayments'
import { copBankTransfers } from './cop/cop_bankTransfers'
import { copElectronicPayments } from './cop/cop_electronicPayments'
import { vesBankTransfers } from './ves/ves_bankTransfers'
import { vesElectronicPayments } from './ves/ves_electronicPayments'
import { arsBankTransfers } from './ars/ars_bankTransfers'
import { arsElectronicPayments } from './ars/ars_electronicPayments'
import { awgBankTransfers } from './awg/awg_bankTransfers'
import { awgElectronicPayments } from './awg/awg_electronicPayments'
import { brlBankTransfers } from './brl/brl_bankTransfers'
import { brlElectronicPayments } from './brl/brl_electronicPayments'
import { cadBankTransfers } from './cad/cad_bankTransfers'
import { cadElectronicPayments } from './cad/cad_electronicPayments'
import { clpBankTransfers } from './clp/clp_bankTransfers'
import { clpElectronicPayments } from './clp/clp_electronicPayments'
import { dopBankTransfers } from './dop/dop_bankTransfers'
import { dopElectronicPayments } from './dop/dop_electronicPayments'
import { eurBankTransfers } from './eur/eur_bankTransfers'
import { eurElectronicPayments } from './eur/eur_electronicPayments'
import { mxnBankTransfers } from './mxn/mxn_bankTransfers'
import { mxnElectronicPayments } from './mxn/mxn_electronicPayments'
import { penBankTransfers } from './pen/pen_bankTransfers'
import { penElectronicPayments } from './pen/pen_electronicPayments'
import { svcBankTransfers } from './svc/svc_bankTransfers'
import { svcElectronicPayments } from './svc/svc_electronicPayments'

// Define PaymentMethod type
interface PaymentMethod {
  id: string
  name: string
  icon: string
}

// Define FiatInfo type
interface FiatInfo {
  id: string
  name: string
  icon: string
  paymentMethods: {
    bankTransfers: PaymentMethod[]
    electronicPayments: PaymentMethod[]
  }
}

// Create a specific type for FiatPaymentMethods
interface FiatPaymentMethodsType {
  [key: string]: FiatInfo
}

// Function to get fiat info by ID
const getFiatInfo = (fiatId: string): FiatInfo => {
  const fiat = uniqueFiat.find(fiat => fiat.id === fiatId)

  // Ensure we return a fully populated FiatInfo object, including paymentMethods
  return fiat
    ? {
        ...fiat,
        paymentMethods: {
          bankTransfers: [],
          electronicPayments: []
        }
      }
    : {
        id: fiatId,
        name: fiatId.toUpperCase(),
        icon: '',
        paymentMethods: {
          bankTransfers: [],
          electronicPayments: []
        }
      }
}

// Define FiatPaymentMethods with explicit types for each currency
export const FiatPaymentMethods: FiatPaymentMethodsType = {
  usd: {
    ...getFiatInfo('usd'),
    paymentMethods: {
      bankTransfers: usdBankTransfers,
      electronicPayments: usdElectronicPayments
    }
  },
  cop: {
    ...getFiatInfo('cop'),
    paymentMethods: {
      bankTransfers: copBankTransfers,
      electronicPayments: copElectronicPayments
    }
  },
  ves: {
    ...getFiatInfo('ves'),
    paymentMethods: {
      bankTransfers: vesBankTransfers,
      electronicPayments: vesElectronicPayments
    }
  },
  ars: {
    ...getFiatInfo('ars'),
    paymentMethods: {
      bankTransfers: arsBankTransfers,
      electronicPayments: arsElectronicPayments
    }
  },
  awg: {
    ...getFiatInfo('awg'),
    paymentMethods: {
      bankTransfers: awgBankTransfers,
      electronicPayments: awgElectronicPayments
    }
  },
  brl: {
    ...getFiatInfo('brl'),
    paymentMethods: {
      bankTransfers: brlBankTransfers,
      electronicPayments: brlElectronicPayments
    }
  },
  cad: {
    ...getFiatInfo('cad'),
    paymentMethods: {
      bankTransfers: cadBankTransfers,
      electronicPayments: cadElectronicPayments
    }
  },
  clp: {
    ...getFiatInfo('clp'),
    paymentMethods: {
      bankTransfers: clpBankTransfers,
      electronicPayments: clpElectronicPayments
    }
  },
  dop: {
    ...getFiatInfo('dop'),
    paymentMethods: {
      bankTransfers: dopBankTransfers,
      electronicPayments: dopElectronicPayments
    }
  },
  eur: {
    ...getFiatInfo('eur'),
    paymentMethods: {
      bankTransfers: eurBankTransfers,
      electronicPayments: eurElectronicPayments
    }
  },
  mxn: {
    ...getFiatInfo('mxn'),
    paymentMethods: {
      bankTransfers: mxnBankTransfers,
      electronicPayments: mxnElectronicPayments
    }
  },
  pen: {
    ...getFiatInfo('pen'),
    paymentMethods: {
      bankTransfers: penBankTransfers,
      electronicPayments: penElectronicPayments
    }
  },
  svc: {
    ...getFiatInfo('svc'),
    paymentMethods: {
      bankTransfers: svcBankTransfers,
      electronicPayments: svcElectronicPayments
    }
  }
}
