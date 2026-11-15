import {
  Home,
  DollarSign,
  CreditCard,
  RefreshCw,
  // ChevronLeft,
  // ChevronRight,
  Wallet,
  ArrowDownToLine,
  ArrowUpFromLine,
  Clock,
  Scale,
  Rocket,
  Award,
  Users,
  Gift,
  LayoutGrid
} from 'lucide-react'

interface NavigationItem {
  icon: typeof Home
  text: string
  path: string
}

export function useNavigationItems() {
  const menuItems: NavigationItem[] = [
    { icon: Home, text: 'Dashboard', path: '/dashboard' },
    { icon: RefreshCw, text: 'P2P Market', path: '/p2p/market' },
    { icon: ArrowDownToLine, text: 'Deposit', path: '/deposit' },
    { icon: ArrowUpFromLine, text: 'Withdraw', path: '/withdraw' },
    { icon: DollarSign, text: 'Exchange', path: '/p2p/exchange' },
    { icon: Wallet, text: 'My Orders', path: '/p2p/orders' },
    { icon: CreditCard, text: 'My Trades', path: '/p2p/trades' },
    { icon: Clock, text: 'Ongoing Operations', path: '/p2p/ongoing-operations' },
    { icon: Scale, text: 'Appeals', path: '/p2p/appeals' },
    { icon: Rocket, text: 'IDO', path: '/ido' },
    { icon: Award, text: 'Staking', path: '/staking' },
    { icon: Users, text: 'Referrals', path: '/rewards/referral' },
    { icon: Gift, text: 'SocialFi Rewards', path: '/rewards/socialfi' },
    { icon: LayoutGrid, text: 'Extras', path: '/extras' }
    // { icon: Settings, text: 'Settings', path: '/settings' }
  ]

  return menuItems
}
