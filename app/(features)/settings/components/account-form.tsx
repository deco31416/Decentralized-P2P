'use client'

import { useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { Input } from '@/app/components/ui/input'
import { Label } from '@/app/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/app/components/ui/select'
import { Switch } from '@/app/components/ui/switch'
import { MessageCircle, Send } from 'lucide-react'
import type { UserData } from '../lib/types'

interface AccountFormProps {
  userData: UserData
  onSubmit: (data: Partial<UserData>) => void
  isLoading?: boolean
}

export function AccountForm({ userData, onSubmit, isLoading = false }: AccountFormProps) {
  const [formData, setFormData] = useState(userData)
  const [language, setLanguage] = useState('en')
  const [is2FAEnabled, setIs2FAEnabled] = useState(false)

  const handleChange = (field: keyof UserData, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }))
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const changedFields = Object.keys(formData).reduce((acc, key) => {
      const k = key as keyof UserData
      if (formData[k] !== userData[k]) {
        acc[k] = formData[k]
      }
      return acc
    }, {} as Partial<UserData>)

    if (Object.keys(changedFields).length > 0) {
      onSubmit(changedFields)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Account Settings</CardTitle>
        <CardDescription>Manage your account settings and preferences</CardDescription>
      </CardHeader>
      <CardContent>
        <form className='space-y-4' onSubmit={handleSubmit}>
          <div className='space-y-2'>
            <Label htmlFor='name'>Name</Label>
            <Input id='name' value={formData.name} onChange={e => handleChange('name', e.target.value)} />
          </div>
          <div className='space-y-2'>
            <Label htmlFor='email'>Email</Label>
            <Input
              id='email'
              type='email'
              value={formData.email}
              onChange={e => handleChange('email', e.target.value)}
            />
          </div>
          <div className='grid grid-cols-1 md:grid-cols-2 gap-4'>
            <div className='space-y-2'>
              <Label htmlFor='whatsapp'>WhatsApp</Label>
              <div className='flex items-center'>
                <MessageCircle className='w-5 h-5 text-muted-foreground mr-2' />
                <Input
                  id='whatsapp'
                  type='tel'
                  value={formData.whatsapp}
                  onChange={e => handleChange('whatsapp', e.target.value)}
                  className='flex-grow'
                />
              </div>
            </div>
            <div className='space-y-2'>
              <Label htmlFor='telegram'>Telegram</Label>
              <div className='flex items-center'>
                <Send className='w-5 h-5 text-muted-foreground mr-2' />
                <Input
                  id='telegram'
                  type='text'
                  value={formData.telegram}
                  onChange={e => handleChange('telegram', e.target.value)}
                  className='flex-grow'
                />
              </div>
            </div>
          </div>
          <div className='space-y-2'>
            <Label htmlFor='language'>Language</Label>
            <Select value={language} onValueChange={setLanguage}>
              <SelectTrigger id='language'>
                <SelectValue placeholder='Select a language' />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value='en'>English</SelectItem>
                <SelectItem value='es'>Spanish</SelectItem>
                <SelectItem value='fr'>French</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className='flex items-center space-x-2'>
            <Switch id='2fa' checked={is2FAEnabled} onCheckedChange={setIs2FAEnabled} />
            <Label htmlFor='2fa'>Enable 2FA</Label>
          </div>
          <Button type='submit' disabled={isLoading}>
            {isLoading ? 'Saving...' : 'Save Settings'}
          </Button>
        </form>
      </CardContent>
    </Card>
  )
}
