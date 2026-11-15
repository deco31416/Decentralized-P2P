'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/app/components/ui/card';
import { Button } from '@/app/components/ui/button';
import { Badge } from '@/app/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/app/components/ui/dialog';

interface KYCVerificationProps {
  isVerified: boolean;
  onStartVerification: () => void;
  isLoading?: boolean;
}

export function KYCVerification({ 
  isVerified, 
  onStartVerification, 
  isLoading = false 
}: KYCVerificationProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>KYC Verification Status</CardTitle>
        <CardDescription>Your current verification status and options</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex justify-between items-center">
          <span>Verification Status:</span>
          {isVerified ? (
            <Badge variant="default">Verified</Badge>
          ) : isLoading ? (
            <Badge variant="secondary">Verifying...</Badge>
          ) : (
            <Badge variant="destructive">Not Verified</Badge>
          )}
        </div>
        {!isVerified && !isLoading && (
          <Dialog>
            <DialogTrigger asChild>
              <Button>Start KYC Verification</Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>KYC Verification</DialogTitle>
                <DialogDescription>
                  You will be redirected to Civic.com to complete your KYC verification.
                </DialogDescription>
              </DialogHeader>
              <Button onClick={onStartVerification} disabled={isLoading}>
                {isLoading ? "Processing..." : "Proceed to Verification"}
              </Button>
            </DialogContent>
          </Dialog>
        )}
      </CardContent>
    </Card>
  );
} 