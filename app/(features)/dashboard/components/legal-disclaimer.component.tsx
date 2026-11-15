'use client'

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle
} from '@/app/components/ui/alert-dialog'
import { Checkbox } from '@/app/components/ui/checkbox'
import { useState } from 'react'

interface LegalDisclaimerProps {
  onAccept: () => void
}

export function LegalDisclaimer({ onAccept }: LegalDisclaimerProps): JSX.Element {
  const [accepted, setAccepted] = useState(false)

  const handleAccept = () => {
    localStorage.setItem('disclaimerAccepted', 'true')
    onAccept()
  }

  return (
    <AlertDialog open={true}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Legal notice</AlertDialogTitle>
          <AlertDialogDescription asChild>
            <div className='space-y-4'>
              <p>
                Before continuing, please read our terms and conditions. CambiaCripto.com is not responsible for the
                actions of third parties or their transactions, including access by clicking Continue.:
              </p>
              <ul className='list-disc pl-4 space-y-2'>
                <li>
                  By using this platform, you confirm that you are at least 18 years old and do not reside in the United
                  States, Canada, or any other country where cryptocurrency use is prohibited. This platform is for
                  informational purposes only and does not constitute financial advice.
                </li>
                <li>
                  Trading cryptocurrencies carries significant risk and may not be suitable for all investors. Please
                  ensure you fully understand the risks before trading.
                </li>
                <li>You are responsible for the security of your private keys and funds.</li>
              </ul>
              <div className='flex items-center space-x-2'>
                <Checkbox id='terms' checked={accepted} onCheckedChange={checked => setAccepted(checked as boolean)} />
                <label
                  htmlFor='terms'
                  className='text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70'
                >
                  I confirm and accept the terms and conditions.
                </label>
              </div>
            </div>
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogAction onClick={handleAccept} disabled={!accepted}>
            Accept and Continue
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
