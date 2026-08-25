import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import './styles/index.css'
import 'leaflet/dist/leaflet.css'

// Native shell (Capacitor) — no-op on web
async function bootNative() {
  try {
    const { Capacitor } = await import('@capacitor/core')
    if (!Capacitor.isNativePlatform()) return
    const { StatusBar, Style } = await import('@capacitor/status-bar')
    const { SplashScreen } = await import('@capacitor/splash-screen')
    await StatusBar.setStyle({ style: Style.Dark })
    try {
      await StatusBar.setBackgroundColor({ color: '#080D1A' })
    } catch { /* iOS may ignore */ }
    await SplashScreen.hide()
  } catch {
    // Web / packages not installed yet
  }
}

bootNative()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
)
