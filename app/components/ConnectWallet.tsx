import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/app/components/ui/card';
import CustomLargeButton from "./ConnectButton/CustomLargeButton";

export default function ConnectWallet() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Welcome to CambiaCripto.com</CardTitle>
          <CardDescription>Connect your wallet to start trading</CardDescription>
        </CardHeader>
        <CardContent className="w-full max-w-md mx-auto">
          <div className="flex w-full justify-center items-center">
            <CustomLargeButton />
          </div>
          <p className="mt-4 text-sm text-muted-foreground text-center">
            You can still view orders without connecting your wallet
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
