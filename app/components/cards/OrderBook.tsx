"use client";

import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/app/components/ui/table';
import { ScrollArea } from '@/app/components/ui/scroll-area';

export default function OrderBook() {
  const buyOrders = [
    { price: "29,340.50", amount: "0.5234", total: "15,356.82" },
    { price: "29,339.75", amount: "0.1000", total: "2,933.98" },
    { price: "29,338.20", amount: "0.3500", total: "10,268.37" },
    { price: "29,337.00", amount: "0.2500", total: "7,335.25" },
    { price: "29,336.50", amount: "0.4000", total: "11,737.00" },
  ];

  const sellOrders = [
    { price: "29,341.00", amount: "0.2500", total: "7,335.25" },
    { price: "29,342.50", amount: "0.4000", total: "11,737.00" },
    { price: "29,343.75", amount: "0.1750", total: "5,135.16" },
    { price: "29,345.00", amount: "0.3000", total: "8,803.50" },
    { price: "29,346.25", amount: "0.5000", total: "14,673.12" },
  ];

  return (
    <Card>
      <CardHeader>
        <CardTitle>Order Book</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 gap-4">
          {/* 📌 Sección de Buy Orders con Scroll */}
          <div>
            <h3 className="mb-2 font-semibold text-green-500">Buy Orders</h3>
            <ScrollArea className="h-[250px] w-full rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Price</TableHead>
                    <TableHead>Amount</TableHead>
                    <TableHead>Total</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {buyOrders.map((order, index) => (
                    <TableRow key={index}>
                      <TableCell>{order.price}</TableCell>
                      <TableCell>{order.amount}</TableCell>
                      <TableCell>{order.total}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </ScrollArea>
          </div>

          {/* 📌 Sección de Sell Orders con Scroll */}
          <div>
            <h3 className="mb-2 font-semibold text-red-500">Sell Orders</h3>
            <ScrollArea className="h-[250px] w-full rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Price</TableHead>
                    <TableHead>Amount</TableHead>
                    <TableHead>Total</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sellOrders.map((order, index) => (
                    <TableRow key={index}>
                      <TableCell>{order.price}</TableCell>
                      <TableCell>{order.amount}</TableCell>
                      <TableCell>{order.total}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </ScrollArea>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
