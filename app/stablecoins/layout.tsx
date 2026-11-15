'use client'

// import Sidebar from '@/app/components/Sidebar';
// import { useState } from "react";
// import dynamic from "next/dynamic';

// const HeaderNoSSR = dynamic(() => import('@/components/Header'), { ssr: false })

export default function StableCoinsLayout({ children }: { children: React.ReactNode }) {
  // const [sidebarOpen, setSidebarOpen] = useState(false);

  return (
    <div className="flex min-h-screen bg-background">
      {/* Sidebar */}
      {/* <Sidebar isOpen={sidebarOpen} setIsOpen={setSidebarOpen}  
        activeSection=""
        setActiveSection={() => {}}
      /> */}

      <div className='flex-1 flex flex-col transition-all duration-300'>
        {/* Header con título dinámico */}
        {/* <HeaderNoSSR
          onMenuClick={() => setSidebarOpen(!sidebarOpen)}
          isSidebarOpen={sidebarOpen}
          title="Stablecoins"
        /> */}

        {/* Contenido Principal */}
        <main className='flex-1 p-4'>{children}</main>
      </div>
    </div>
  )
}
