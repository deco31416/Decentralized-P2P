'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/app/components/ui/card';
import type { UserData } from "../lib/types";

interface VerifiedInfoProps {
  userData: UserData;
}

export function VerifiedInfo({ userData }: VerifiedInfoProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Verified User Information</CardTitle>
        <CardDescription>Your verified personal details</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="space-y-2">
          <div className="flex justify-between">
            <span className="font-medium">Name:</span>
            <span>{userData.name}</span>
          </div>
          <div className="flex justify-between">
            <span className="font-medium">Email:</span>
            <span>{userData.email}</span>
          </div>
          <div className="flex justify-between">
            <span className="font-medium">Wallet:</span>
            <span>{userData.wallet}</span>
          </div>
          <div className="flex justify-between">
            <span className="font-medium">Country:</span>
            <span>{userData.country}</span>
          </div>
        </div>
      </CardContent>
    </Card>
  );
} 