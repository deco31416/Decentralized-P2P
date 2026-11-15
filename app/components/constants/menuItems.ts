import {
    Home,
    DollarSign,
    CreditCard,
    RefreshCw,
    Wallet,
    ArrowDownToLine,
    ArrowUpFromLine,
    Clock,
    Scale,
    Rocket,
    Award,
    Users,
    Gift,
    LayoutGrid,
  } from "lucide-react";
  
  export const menuItems = [
    { icon: Home, text: "Dashboard", section: "dashboard" },
    { icon: RefreshCw, text: "P2P Market", section: "market" },
    { icon: ArrowDownToLine, text: "Deposit", section: "deposit" },
    { icon: ArrowUpFromLine, text: "Withdraw", section: "withdraw" },
    { icon: DollarSign, text: "Exchange", section: "exchange" },
    { icon: Wallet, text: "My Orders", section: "orders" },
    { icon: CreditCard, text: "My Trades", section: "trades" },
    { icon: Clock, text: "Ongoing Operations", section: "ongoing-operations" },
    { icon: Scale, text: "Appeals", section: "appeals" },
    { icon: Rocket, text: "IDO", section: "ido" },
    { icon: Award, text: "Staking", section: "staking" },
    { icon: Users, text: "Referrals", section: "referrals" },
    { icon: Gift, text: "SocialFi Rewards", section: "socialfi-rewards" },
    { icon: LayoutGrid, text: "Extras", section: "extras" },
  ];
  