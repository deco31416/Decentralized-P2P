'use client'

import { useState } from 'react'
import { KYCVerification } from './kyc-verification'
import { VerifiedInfo } from './verified-info'
import { AccountForm } from './account-form'

import type { UserData } from '../lib/types'
import { useToast } from '@/app/hooks/use-toast'

// Simulated user data
const initialUserData: UserData = {
  name: 'John Doe',
  email: 'john@example.com',
  wallet: '0x1234...5678',
  whatsapp: '+1234567890',
  telegram: '@johndoe',
  country: 'United States'
}

export function Settings() {
  const [isVerified, setIsVerified] = useState(false)
  const [userData, setUserData] = useState<UserData>(initialUserData)
  const [isVerifying, setIsVerifying] = useState(false)
  const [isSaving, setIsSaving] = useState(false)
  const { toast } = useToast()

  const handleStartVerification = async () => {
    try {
      setIsVerifying(true)
      // Simulated API call
      await new Promise(resolve => setTimeout(resolve, 2000))
      setIsVerified(true)
      toast({
        title: 'Verification Successful',
        description: 'Your identity has been verified successfully.'
      })
    } catch (error) {
      console.error('Verification error:', error)
      toast({
        title: 'Verification Failed',
        description: 'There was an error during verification. Please try again.',
        variant: 'destructive'
      })
    } finally {
      setIsVerifying(false)
    }
  }

  const handleUpdateSettings = async (newData: Partial<UserData>) => {
    try {
      setIsSaving(true)
      // Simulated API call
      await new Promise(resolve => setTimeout(resolve, 1000))
      setUserData(prev => ({ ...prev, ...newData }))
      toast({
        title: 'Settings Updated',
        description: 'Your settings have been saved successfully.'
      })
    } catch (error) {
      console.error('Update error:', error)
      toast({
        title: 'Update Failed',
        description: 'There was an error saving your settings. Please try again.',
        variant: 'destructive'
      })
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <div className='space-y-6'>
      <KYCVerification isVerified={isVerified} onStartVerification={handleStartVerification} isLoading={isVerifying} />

      {isVerified && <VerifiedInfo userData={userData} />}

      <AccountForm userData={userData} onSubmit={handleUpdateSettings} isLoading={isSaving} />
    </div>
  )
}
