// SocialFi Rewards Types
export interface LeaderboardEntry {
  category: string
  leader: string
  score: string
  prize: number
}

export interface RandomWinner {
  username: string
  prize: number
}

export interface UserStats {
  referrals: number
  tradingVolume: number
  feesGenerated: number
}

export interface SocialfiRewardsData {
  totalPool: number
  timeRemaining: string
  leaderboard: LeaderboardEntry[]
  randomWinners: RandomWinner[]
  userStats: UserStats
}

// Referral Program Types
export interface ReferralHistoryEntry {
  id: number
  date: string
  action: string
  amount: number
}

export interface ReferralStats {
  referralLink: string
  totalReferrals: number
  activeReferrals: number
  totalEarnings: number
  availableForWithdrawal: number
  history: ReferralHistoryEntry[]
}
