import type { ReactNode } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { getRoleFromStorage } from './lib/api'
import { hasCompletedOnboarding } from './lib/onboarding'
import { AppTabs, roleHome } from './components/AppTabs'
import Splash from './pages/Splash'
import Onboard from './pages/Onboard'
import Landing from './pages/Landing'
import RoleGate from './pages/RoleGate'
import LiveMap from './pages/LiveMap'
import FieldGuide from './pages/FieldGuide'
import Messages from './pages/Messages'
import OrderMenu from './pages/OrderMenu'
import Checkout from './pages/Checkout'
import UnitsToday from './pages/UnitsToday'
import WalkIntro from './pages/WalkIntro'
import PmOrder from './pages/PmOrder'
import TrackWork from './pages/TrackWork'
import Complete from './pages/Complete'
import CrewHome from './pages/CrewHome'
import CrewPing from './pages/CrewPing'
import CrewJob from './pages/CrewJob'
import DispatchBoard from './pages/DispatchBoard'
import Orders from './pages/Orders'
import PhotoVerify from './pages/PhotoVerify'

function RequireRole({ children }: { children: ReactNode }) {
  const role = getRoleFromStorage()
  if (!role) return <Navigate to="/enter" replace />
  return <>{children}</>
}

function RootRedirect() {
  if (!hasCompletedOnboarding()) return <Navigate to="/splash" replace />
  const role = getRoleFromStorage()
  if (!role) return <Navigate to="/enter" replace />
  return <Navigate to={roleHome(role)} replace />
}

export default function App() {
  return (
    <>
      <Routes>
        <Route path="/" element={<RootRedirect />} />
        <Route path="/splash" element={<Splash />} />
        <Route path="/onboard" element={<Onboard />} />
        <Route path="/welcome" element={<Landing />} />
        <Route path="/enter" element={<RoleGate />} />
        <Route path="/live" element={<RequireRole><LiveMap /></RequireRole>} />
        <Route path="/field/:workId?" element={<RequireRole><FieldGuide /></RequireRole>} />
        <Route path="/messages/:buildingId?" element={<RequireRole><Messages /></RequireRole>} />
        <Route path="/order" element={<RequireRole><OrderMenu /></RequireRole>} />
        <Route path="/order/checkout" element={<RequireRole><Checkout /></RequireRole>} />
        <Route path="/units" element={<RequireRole><UnitsToday /></RequireRole>} />
        <Route path="/walk" element={<RequireRole><WalkIntro /></RequireRole>} />
        <Route path="/approve" element={<RequireRole><PmOrder /></RequireRole>} />
        <Route path="/track" element={<RequireRole><TrackWork /></RequireRole>} />
        <Route path="/complete" element={<RequireRole><Complete /></RequireRole>} />
        <Route path="/crew" element={<RequireRole><CrewHome /></RequireRole>} />
        <Route path="/crew/ping" element={<RequireRole><CrewPing /></RequireRole>} />
        <Route path="/crew/job" element={<RequireRole><CrewJob /></RequireRole>} />
        <Route path="/dispatch" element={<RequireRole><DispatchBoard /></RequireRole>} />
        <Route path="/orders" element={<RequireRole><Orders /></RequireRole>} />
        <Route path="/photos/:jobId?" element={<RequireRole><PhotoVerify /></RequireRole>} />
        <Route path="*" element={<RootRedirect />} />
      </Routes>
      <AppTabs />
    </>
  )
}
