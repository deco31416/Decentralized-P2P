import '@styles/globals.css'
import { Providers } from './providers'
import { Inter } from 'next/font/google'
import type { Metadata } from 'next'
import type React from 'react'
import { MainLayout } from '@/app/components/MainLayout'
import { StructuredData } from '@/app/components/StructuredData'

// const poppins = Poppins({
//   subsets: ['latin'],
//   weight: ['300', '400', '600', '700']
// })

// Cambiar de Poppins a Inter
const inter = Inter({
  subsets: ['latin'],
  weight: ['300', '400', '600', '700'],
  variable: '--font-inter',
  display: 'swap'
})

export const metadata: Metadata = {
  metadataBase: new URL('https://cambiacripto.com'),
  title: 'CambiaCripto | Proyecto P2P Web3 en desarrollo',
  description:
    'Proyecto de código abierto en desarrollo que explora flujos P2P para activos digitales. Incluye una aplicación Next.js y contratos Solidity experimentales.',
  keywords: [
    'proyecto P2P cripto',
    'interfaz P2P Web3',
    'aplicación Next.js',
    'contratos Solidity',
    'software de código abierto',
    'CambiaCripto'
  ],
  authors: [{ name: 'deoc31416' }],
  creator: 'deoc31416',
  publisher: 'deoc31416',
  manifest: '/manifest.json',
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1
    }
  },
  openGraph: {
    type: 'website',
    locale: 'es_ES',
    alternateLocale: ['en_US'],
    url: 'https://cambiacripto.com',
    siteName: 'CambiaCripto',
    title: 'CambiaCripto | Proyecto P2P Web3 en desarrollo',
    description:
      'Proyecto abierto en desarrollo con una interfaz Next.js y contratos Solidity experimentales para explorar flujos P2P.',
    images: [
      {
        url: '/images/logos/logo.png',
        width: 1200,
        height: 630,
        alt: 'CambiaCripto - Plataforma P2P de Criptomonedas'
      }
    ]
  },
  twitter: {
    card: 'summary_large_image',
    title: 'CambiaCripto | Proyecto P2P Web3 en desarrollo',
    description: 'Proyecto abierto en desarrollo para explorar interfaces P2P y contratos Web3.',
    images: ['/images/logos/logo.png'],
    creator: '@deoc31416'
  },
  alternates: {
    canonical: 'https://cambiacripto.com',
    languages: {
      'es-ES': 'https://cambiacripto.com/es',
      'en-US': 'https://cambiacripto.com/en'
    }
  },
  category: 'Finance'
}

export const viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  themeColor: '#8b5cf6'
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang='es' suppressHydrationWarning>
      <body className={inter.className}>
        <StructuredData />
        <Providers attribute='class' defaultTheme='dark' enableSystem disableTransitionOnChange>
          <MainLayout>{children}</MainLayout>
        </Providers>
      </body>
    </html>
  )
}




