// 📌 Ubicación: `components/LegalDisclaimer.tsx`
"use client";

import { useState } from 'react';
import { Button } from '@/app/components/ui/button';
import { CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/app/components/ui/card';
import { Checkbox } from '@/app/components/ui/checkbox';
import Modal from "@/app/components/ui/Modal";

interface LegalDisclaimerProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function LegalDisclaimerModal({ isOpen, onClose }: LegalDisclaimerProps) {
  const [isChecked, setIsChecked] = useState(false);

  return (
    <Modal isOpen={isOpen} onClose={isChecked ? onClose : undefined}>
      <div className="w-full">
        <CardHeader>
          <CardTitle>Legal Disclaimer</CardTitle>
          <CardDescription>Please read and accept our terms before continuing</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <p>
            By using this platform, you confirm that you are at least 18 years old and do not reside in the United
            States or Canada. This platform is for informational purposes only and does not constitute financial advice.
          </p>
          <p>
            Cryptocurrency trading involves significant risk and may not be suitable for all investors. Please ensure
            that you fully understand the risks involved before trading.
          </p>
          <div className="flex items-center space-x-2">
            <Checkbox id="terms" checked={isChecked} onCheckedChange={(checked) => setIsChecked(checked as boolean)} />
            <label
              htmlFor="terms"
              className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
            >
              I confirm that I meet the above requirements and accept the terms
            </label>
          </div>
        </CardContent>
        <CardFooter>
          <Button onClick={onClose} disabled={!isChecked} className="w-full">
            Accept and Continue
          </Button>
        </CardFooter>
      </div>
    </Modal>
  );
}
