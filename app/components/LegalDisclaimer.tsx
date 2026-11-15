import { useState, useEffect } from 'react'
import { Button } from '@/app/components/ui/button'
import { Checkbox } from '@/app/components/ui/checkbox'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/app/components/ui/dialog'

interface LegalDisclaimerProps {
  onAccept: () => void
}

export default function LegalDisclaimer({ onAccept }: LegalDisclaimerProps) {
  const [isChecked, setIsChecked] = useState(false)
  const [open, setOpen] = useState(true)

  const handleAccept = () => {
    // Guardar en localStorage que el usuario ha aceptado los términos
    localStorage.setItem("disclaimerAccepted", "true")
    setOpen(false)
    onAccept()
  }

  // Si el diálogo se cierra sin aceptar, volver a abrirlo
  useEffect(() => {
    if (!open) {
      setOpen(true)
    }
  }, [open])

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="sm:max-w-lg" onInteractOutside={(e) => e.preventDefault()}>
        <DialogHeader>
          <DialogTitle>Aviso Legal</DialogTitle>
          <DialogDescription>
            Por favor, lee y acepta nuestros términos antes de continuar
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-4">
          <p>
            Al utilizar esta plataforma, confirmas que tienes al menos 18 años y que no resides en los
            Estados Unidos o Canadá. Esta plataforma es solo para fines informativos y no constituye asesoramiento financiero.
          </p>
          <p>
            El comercio de criptomonedas implica un riesgo significativo y puede no ser adecuado para todos los inversores. Por favor, asegúrate
            de que comprendes completamente los riesgos involucrados antes de operar.
          </p>
          <div className="flex items-center space-x-2 pt-2">
            <Checkbox id="terms" checked={isChecked} onCheckedChange={(checked) => setIsChecked(checked as boolean)} />
            <label
              htmlFor="terms"
              className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
            >
              Confirmo que cumplo con los requisitos anteriores y acepto los términos
            </label>
          </div>
        </div>
        <DialogFooter>
          <Button onClick={handleAccept} disabled={!isChecked} className="w-full sm:w-auto">
            Aceptar y Continuar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

