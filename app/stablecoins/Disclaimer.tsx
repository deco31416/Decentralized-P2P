import { Alert, AlertDescription } from '@/app/components/ui/alert';
import { AlertTriangle } from "lucide-react";

export function Disclaimer() {
  return (
    <Alert variant="destructive">
      <AlertTriangle className="h-4 w-4" />
      <AlertDescription className="text-sm">
        Los precios de las criptomonedas están sujetos a un alto riesgo de mercado y a una gran volatilidad.
        Solo deberías invertir en productos que conozcas y siempre que comprendas los riesgos asociados a estos.
      </AlertDescription>
    </Alert>
  );
}
