"use client";

import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/app/components/ui/table';
import { ScrollArea } from '@/app/components/ui/scroll-area';

export default function MarketOverview() {
  const marketData = [
    { pair: "BTC/USDT", price: "29,345.67", change: "+2.5%" },
    { pair: "ETH/USDT", price: "1,876.54", change: "-0.8%" },
    { pair: "XRP/USDT", price: "0.4567", change: "+1.2%" },
    { pair: "LTC/USDT", price: "87.65", change: "+3.1%" },
    { pair: "DOT/USDT", price: "5.43", change: "-1.5%" },
    { pair: "BNB/USDT", price: "312.54", change: "+0.7%" },
    { pair: "ADA/USDT", price: "0.384", change: "+1.1%" },
    { pair: "SOL/USDT", price: "22.98", change: "-0.4%" },
  ];

  return (
    <Card>
      <CardHeader>
        <CardTitle>Market Overview</CardTitle>
      </CardHeader>
      <CardContent>
        <ScrollArea className="h-[300px] w-full rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Pair</TableHead>
                <TableHead>Price</TableHead>
                <TableHead>24h Change</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {marketData.map((item) => (
                <TableRow key={item.pair}>
                  <TableCell>{item.pair}</TableCell>
                  <TableCell>{item.price}</TableCell>
                  <TableCell className={item.change.startsWith("+") ? "text-green-500" : "text-red-500"}>
                    {item.change}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </ScrollArea>
      </CardContent>
    </Card>
  );
}
