export interface PaymentMethod {
  id: string
  name: string
  icon: string
}

export interface CryptoMethod extends PaymentMethod {
  network: {
    id: string
    name: string
    icon: string
    chainId: number
    rpc: string
    explorer: string
    symbol: string // Se agrega el símbolo de la moneda (ej: ETH, BNB, TRX)
  }
}

// Tipos de pago con dinero fiat
export interface FiatMethod extends PaymentMethod {
  country: string // País donde se acepta (ej: "USA", "Mexico", "Colombia")
  category: 'bankTransfer' | 'digitalWallet' | 'cashPayment' | 'mobilePayment' | 'remittance' // Tipo de pago fiat
}

// Tipos de pagos organizados
export interface PaymentMethods {
  crypto: CryptoMethod[]
  fiat: FiatMethod[]
}

export interface CryptoMethodArray extends PaymentMethod {
  networks: {
    id: string
    name: string
    icon: string
    chainId: number
    rpc: string
    explorer: string
    symbol: string
  }[]
  price: string | number
}
