'use client'

import Script from 'next/script'

export function StructuredData() {
  const organizationSchema = {
    '@context': 'https://schema.org',
    '@type': 'FinancialService',
    name: 'CambiaCripto',
    alternateName: 'Cambia Cripto',
    url: 'https://cambiacripto.com',
    logo: 'https://cambiacripto.com/images/logos/logo.png',
    description:
      'Plataforma P2P descentralizada para intercambio seguro de criptomonedas. Compra, vende e intercambia Bitcoin, USDT, Ethereum con staking y trading cripto-fiat.',
    sameAs: [
      'https://twitter.com/cambiacripto',
      'https://facebook.com/cambiacripto',
      'https://linkedin.com/company/cambiacripto',
      'https://t.me/cambiacripto'
    ],
    contactPoint: {
      '@type': 'ContactPoint',
      contactType: 'Customer Support',
      email: 'support@cambiacripto.com',
      availableLanguage: ['Spanish', 'English']
    },
    address: {
      '@type': 'PostalAddress',
      addressCountry: 'CO'
    }
  }

  const websiteSchema = {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: 'CambiaCripto',
    url: 'https://cambiacripto.com',
    potentialAction: {
      '@type': 'SearchAction',
      target: {
        '@type': 'EntryPoint',
        urlTemplate: 'https://cambiacripto.com/search?q={search_term_string}'
      },
      'query-input': 'required name=search_term_string'
    }
  }

  const serviceSchema = {
    '@context': 'https://schema.org',
    '@type': 'Service',
    serviceType: 'Cryptocurrency Exchange',
    provider: {
      '@type': 'Organization',
      name: 'CambiaCripto'
    },
    areaServed: {
      '@type': 'Country',
      name: ['Colombia', 'Mexico', 'United States', 'Spain', 'Argentina']
    },
    hasOfferCatalog: {
      '@type': 'OfferCatalog',
      name: 'Servicios de Criptomonedas',
      itemListElement: [
        {
          '@type': 'Offer',
          itemOffered: {
            '@type': 'Service',
            name: 'Intercambio P2P de Criptomonedas',
            description: 'Compra y vende Bitcoin, USDT, Ethereum de forma segura'
          }
        },
        {
          '@type': 'Offer',
          itemOffered: {
            '@type': 'Service',
            name: 'Staking de Criptomonedas',
            description: 'Genera recompensas con tus criptomonedas'
          }
        },
        {
          '@type': 'Offer',
          itemOffered: {
            '@type': 'Service',
            name: 'Trading Cripto-Fiat',
            description: 'Intercambia entre criptomonedas y monedas fiat'
          }
        }
      ]
    }
  }

  const breadcrumbSchema = {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [
      {
        '@type': 'ListItem',
        position: 1,
        name: 'Inicio',
        item: 'https://cambiacripto.com'
      },
      {
        '@type': 'ListItem',
        position: 2,
        name: 'Mercado P2P',
        item: 'https://cambiacripto.com/p2p/market'
      },
      {
        '@type': 'ListItem',
        position: 3,
        name: 'Exchange',
        item: 'https://cambiacripto.com/exchange'
      },
      {
        '@type': 'ListItem',
        position: 4,
        name: 'Staking',
        item: 'https://cambiacripto.com/staking'
      }
    ]
  }

  return (
    <>
      <Script
        id='organization-schema'
        type='application/ld+json'
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(organizationSchema)
        }}
      />
      <Script
        id='website-schema'
        type='application/ld+json'
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(websiteSchema)
        }}
      />
      <Script
        id='service-schema'
        type='application/ld+json'
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(serviceSchema)
        }}
      />
      <Script
        id='breadcrumb-schema'
        type='application/ld+json'
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(breadcrumbSchema)
        }}
      />
    </>
  )
}
