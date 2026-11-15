'use client'

import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { ReactNode } from 'react'

interface DashboardCardProps {
  title: string
  children: ReactNode
}

export function DashboardCard({ title, children }: DashboardCardProps) {
  return (
    <Card className='sm:col-span-4'>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  )
}
