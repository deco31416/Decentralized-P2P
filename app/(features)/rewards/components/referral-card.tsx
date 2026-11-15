'use client'

import { useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Button } from '@/app/components/ui/button'
import { Input } from '@/app/components/ui/input'
import { Label } from '@/app/components/ui/label'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/app/components/ui/table'
import { Progress } from '@/app/components/ui/progress'
import { Copy, CheckCircle, ChevronLeft, ChevronRight } from 'lucide-react'
import { referralData } from '../mock/mock-data'
import { ReferralHistoryEntry } from '../types'

function ReferralLinkCard() {
  const [copied, setCopied] = useState(false)

  const copyToClipboard = () => {
    navigator.clipboard.writeText(referralData.referralLink)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Your Referral Link</CardTitle>
        <CardDescription>Share this link to earn rewards</CardDescription>
      </CardHeader>
      <CardContent>
        <div className='flex space-x-2'>
          <Input value={referralData.referralLink} readOnly />
          <Button onClick={copyToClipboard}>
            {copied ? <CheckCircle className='h-4 w-4' /> : <Copy className='h-4 w-4' />}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

function ReferralStatsCard() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Referral Statistics</CardTitle>
      </CardHeader>
      <CardContent>
        <div className='space-y-4'>
          <div>
            <Label>Total Referrals</Label>
            <div className='text-2xl font-bold'>{referralData.totalReferrals}</div>
          </div>
          <div>
            <Label>Active Referrals</Label>
            <div className='text-2xl font-bold'>{referralData.activeReferrals}</div>
          </div>
          <div>
            <Label>Total Earnings</Label>
            <div className='text-2xl font-bold'>${referralData.totalEarnings.toFixed(2)}</div>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

function WithdrawalCard() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Withdrawal</CardTitle>
      </CardHeader>
      <CardContent>
        <div className='space-y-4'>
          <div>
            <Label>Available for Withdrawal</Label>
            <div className='text-2xl font-bold'>${referralData.availableForWithdrawal.toFixed(2)}</div>
          </div>
          <Progress value={(referralData.availableForWithdrawal / 5) * 100} className='w-full' />
          <p className='text-sm text-muted-foreground'>
            ${referralData.availableForWithdrawal.toFixed(2)} / $5.00 needed to withdraw
          </p>
          <Button disabled={referralData.availableForWithdrawal < 5}>
            {referralData.availableForWithdrawal >= 5 ? 'Withdraw Earnings' : 'Insufficient Balance'}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

interface EarningsHistoryProps {
  entries: ReferralHistoryEntry[]
  currentPage: number
  totalPages: number
  onNextPage: () => void
  onPrevPage: () => void
}

function EarningsHistory({ entries, currentPage, totalPages, onNextPage, onPrevPage }: EarningsHistoryProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Earnings History</CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Action</TableHead>
              <TableHead className='text-right'>Amount</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {entries.map(item => (
              <TableRow key={item.id}>
                <TableCell>{item.date}</TableCell>
                <TableCell>{item.action}</TableCell>
                <TableCell className='text-right'>${item.amount.toFixed(2)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <div className='flex items-center justify-between mt-4'>
          <Button onClick={onPrevPage} disabled={currentPage === 1}>
            <ChevronLeft className='h-4 w-4 mr-2' />
            Previous
          </Button>
          <span>
            Page {currentPage} of {totalPages}
          </span>
          <Button onClick={onNextPage} disabled={currentPage === totalPages}>
            Next
            <ChevronRight className='h-4 w-4 ml-2' />
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

function ProgramInfoCard() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Referral Program Information</CardTitle>
      </CardHeader>
      <CardContent>
        <ul className='list-disc pl-5 space-y-2'>
          <li>Earn a percentage of your referrals token purchases, exchange fees, and IDO participations.</li>
          <li>You can withdraw your earnings once you accumulate $5 or more.</li>
          <li>Referral rewards are calculated and added to your balance in real-time.</li>
          <li>The more active referrals you have, the higher your potential earnings.</li>
        </ul>
      </CardContent>
    </Card>
  )
}

export function ReferralCard() {
  const [currentPage, setCurrentPage] = useState(1)
  const itemsPerPage = 5

  const totalPages = Math.ceil(referralData.history.length / itemsPerPage)
  const startIndex = (currentPage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const currentItems = referralData.history.slice(startIndex, endIndex)

  const nextPage = () => {
    setCurrentPage(prev => Math.min(prev + 1, totalPages))
  }

  const prevPage = () => {
    setCurrentPage(prev => Math.max(prev - 1, 1))
  }

  return (
    <div className='space-y-6'>
      <ReferralLinkCard />
      <div className='grid gap-6 md:grid-cols-2'>
        <ReferralStatsCard />
        <WithdrawalCard />
      </div>
      <EarningsHistory
        entries={currentItems}
        currentPage={currentPage}
        totalPages={totalPages}
        onNextPage={nextPage}
        onPrevPage={prevPage}
      />
      <ProgramInfoCard />
    </div>
  )
}
