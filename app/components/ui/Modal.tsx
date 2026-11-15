// 📌 Ubicación: `components/ui/Modal.tsx`
"use client";

import { ReactNode, useEffect, useState } from "react";
import { CircleX } from "lucide-react"; // Ícono de cerrar
import { useTheme } from "next-themes"; // Detecta el tema actual
import { cn } from "@/lib/utils";

interface ModalProps {
  isOpen: boolean;
  onClose?: () => void;
  children: ReactNode;
  className?: string;
}

export default function Modal({ isOpen, onClose, children, className }: ModalProps) {
  const { theme } = useTheme(); // Detecta el tema actual
  const [visible, setVisible] = useState(isOpen);

  // Agregar animación al abrir y cerrar
  useEffect(() => {
    if (isOpen) {
      setVisible(true);
    } else {
      setTimeout(() => setVisible(false), 200); // Tiempo de salida
    }
  }, [isOpen]);

  if (!visible) return null;

  return (
    <div
      className={cn(
        "fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-xl p-4 transition-all",
        isOpen ? "animate-fadeIn" : "animate-fadeOut"
      )}
    >
      {/* Capa de fondo para cerrar */}
      <div className="absolute inset-0" onClick={onClose} />

      {/* Contenedor del Modal con bordes y estilos de Card */}
      <div
        className={cn(
          "relative w-full max-w-lg bg-background border border-border rounded-xl shadow-lg p-6 transition-all transform scale-100",
          isOpen ? "opacity-100 translate-y-0" : "opacity-0 translate-y-4",
          className
        )}
        onClick={(e) => e.stopPropagation()} // Evitar cierre accidental
      >
        {/* Botón de cerrar */}
        {onClose && (
          <button
            onClick={onClose}
            className={cn(
              "absolute top-4 right-4 p-2 rounded-full transition-all duration-300",
              theme === "dark"
                ? "text-white hover:bg-gray-800 hover:text-gray-300"
                : "text-gray-900 hover:bg-gray-200 hover:text-gray-700"
            )}
          >
            <CircleX className="w-6 h-6 transition-transform duration-200 hover:w-6 hover:h-6" />
          </button>
        )}

        {/* Contenido dinámico */}
        {children}
      </div>
    </div>
  );
}
