import { SocialfiRewardsData, ReferralStats } from '../types'

export const socialfiRewardsData: SocialfiRewardsData = {
  totalPool: 1000,
  timeRemaining: '15 days 7 hours',
  leaderboard: [
    { category: 'Referrals', leader: 'User123', score: '50 referrals', prize: 250 },
    { category: 'Trading Volume', leader: 'Trader456', score: '$500,000', prize: 250 },
    { category: 'Fees Generated', leader: 'Active789', score: '$5,000', prize: 250 }
  ],
  randomWinners: [
    { username: 'Lucky101', prize: 125 },
    { username: 'Fortunate202', prize: 125 }
  ],
  userStats: {
    referrals: 8,
    tradingVolume: 75000,
    feesGenerated: 750
  }
}

export const referralData: ReferralStats = {
  referralLink: 'https://p2pexchange.com/ref/user123',
  totalReferrals: 15,
  activeReferrals: 8,
  totalEarnings: 47.5,
  availableForWithdrawal: 6.75,
  history: [
    { id: 1, date: '2024-02-10', action: 'Token Purchase', amount: 2.5 },
    { id: 2, date: '2024-02-09', action: 'Exchange Fee', amount: 0.75 },
    { id: 3, date: '2024-02-08', action: 'IDO Participation', amount: 3.5 },
    { id: 4, date: '2024-02-07', action: 'Exchange Fee', amount: 0.5 },
    { id: 5, date: '2024-02-06', action: 'Token Purchase', amount: 1.5 },
    { id: 6, date: '2024-02-05', action: 'Token Purchase', amount: 2.0 },
    { id: 7, date: '2024-02-04', action: 'Exchange Fee', amount: 0.6 },
    { id: 8, date: '2024-02-03', action: 'IDO Participation', amount: 4.0 },
    { id: 9, date: '2024-02-02', action: 'Token Purchase', amount: 1.8 },
    { id: 10, date: '2024-02-01', action: 'Exchange Fee', amount: 0.8 }
  ]
}
