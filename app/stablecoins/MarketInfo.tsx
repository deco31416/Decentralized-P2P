import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/app/components/ui/table';

export function MarketInfo() {
  const markets = [
    { source: "Media", price: "$1.00" },
    { source: "CoinMarketCap", price: "$1.01" },
    { source: "CoinGecko", price: "$0.99" },
    { source: "CryptoCompare", price: "$1.00" },
  ];

  return (
    <Card>
      <CardHeader>
        <CardTitle>Información de precios del mercado</CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Fuente</TableHead>
              <TableHead>Precio</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {markets.map((market) => (
              <TableRow key={market.source}>
                <TableCell>{market.source}</TableCell>
                <TableCell>{market.price}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
