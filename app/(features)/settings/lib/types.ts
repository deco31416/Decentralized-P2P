export interface UserData {
  name: string;
  email: string;
  wallet: string;
  whatsapp: string;
  telegram: string;
  country: string;
}

export interface SettingsState {
  isVerified: boolean;
  userData: UserData;
} 