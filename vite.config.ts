import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const port = Number(env.PORT || process.env.PORT) || 5173
  // Proxy to Halo API so browser calls /api/* hit live Base44-backed server
  // Proxy always targets Halo origin. Empty VITE_API_BASE = browser uses relative /api.
  const rawBase = (env.VITE_API_BASE || process.env.VITE_API_BASE || '').replace(/\/$/, '')
  const apiTarget =
    rawBase && /^https?:\/\//.test(rawBase)
      ? rawBase
      : 'https://archangel-halo.replit.app'

  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      alias: { '@': path.resolve(__dirname, './src') },
    },
    server: {
      port,
      host: '0.0.0.0',
      strictPort: false,
      allowedHosts: true,
      proxy: {
        '/api': {
          target: apiTarget,
          changeOrigin: true,
          secure: true,
        },
      },
    },
    preview: { port, host: '0.0.0.0' },
  }
})
