import { uniqueFiat } from "./uniqueFiat"; 

export interface FiatCurrency {
  id: string;
  name: string;
  icon: string;
}

export const fiatCurrencies: FiatCurrency[] = uniqueFiat;
