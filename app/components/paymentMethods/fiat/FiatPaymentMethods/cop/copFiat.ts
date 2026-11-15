import { uniqueFiat } from "../../FiatMoney/uniqueFiat";
import { copBankTransfers } from "./cop_bankTransfers";
import { copElectronicPayments } from "./cop_electronicPayments";

const copInfo = uniqueFiat.find(fiat => fiat.id === "cop");

if (!copInfo) {
  throw new Error("COP currency data not found in Fiat.");
}

export const copPayment = {
  ...copInfo,
  paymentMethods: {
    bankTransfers: copBankTransfers,
    electronicPayments: copElectronicPayments
  }
};
