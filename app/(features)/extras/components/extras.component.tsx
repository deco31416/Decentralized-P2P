'use client'

import MarketOverview from '@/app/components/cards/MarketOverview'
import OrderBook from '@/app/components/cards/OrderBook'
import QuickExchange from '@/app/components/cards/QuickExchange'
import TradeHistory from '@/app/components/cards/TradeHistory'
import TradingVolume from '@/app/components/cards/TradingVolume'
import OngoingOperationsCard from '@/app/components/cards/OngoingOperationsCard'
import AppealsCard from '@/app/components/cards/AppealsCard'
import ActiveIDOsCard from '@/app/components/cards/ActiveIDOsCard'
import UpcomingIDOsCard from '@/app/components/cards/UpcomingIDOsCard'
import StakingCard from '@/app/components/cards/StakingCard'
import SocialFiLotteryCard from '@/app/components/cards/SocialFiLotteryCard'
import RewardDistributionCard from '@/app/components/cards/RewardDistributionCard'
import TopPerformersCard from '@/app/components/cards/TopPerformersCard'
import FiatToFiatExchange from '@/app/components/cards/FiatToFiat'
import { DashboardCard } from './dashboard-card.component'

const DASHBOARD_ITEMS = [
  { title: 'Market Overview', Component: MarketOverview },
  { title: 'Order Book', Component: OrderBook },
  { title: 'Quick Exchange', Component: QuickExchange },
  { title: 'Active IDOs', Component: ActiveIDOsCard },
  { title: 'Trade History', Component: TradeHistory },
  { title: 'Trading Volume', Component: TradingVolume },
  { title: 'Ongoing Operations', Component: OngoingOperationsCard },
  { title: 'Appeals', Component: AppealsCard },
  { title: 'Upcoming IDOs', Component: UpcomingIDOsCard },
  { title: 'Staking', Component: StakingCard },
  { title: 'SocialFi Rewards', Component: SocialFiLotteryCard },
  { title: 'Reward Distribution', Component: RewardDistributionCard },
  { title: 'Current Top Performers', Component: TopPerformersCard },
  { title: 'Fiat To Fiat', Component: FiatToFiatExchange }
]

export function Extras() {
  return (
    <div className='p-4 sm:p-6 md:p-8 bg-background'>
      <h1 className='text-2xl font-bold mb-6'>Dashboard Cards</h1>
      <div className='grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4'>
        {DASHBOARD_ITEMS.map(({ title, Component }) => (
          <DashboardCard key={title} title={title}>
            <Component />
          </DashboardCard>
        ))}
      </div>
    </div>
  )
}
