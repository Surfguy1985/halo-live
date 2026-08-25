import type { CapacitorConfig } from '@capacitor/cli'

const config: CapacitorConfig = {
  appId: 'com.archangel.halolive',
  appName: 'Halo Live',
  webDir: 'dist',
  server: {
    // For live reload during native debug, uncomment:
    // url: 'http://YOUR_LAN_IP:5179',
    // cleartext: true,
    androidScheme: 'https',
    iosScheme: 'https',
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1800,
      launchAutoHide: true,
      backgroundColor: '#080D1A',
      showSpinner: false,
      androidSplashResourceName: 'splash',
      splashFullScreen: true,
      splashImmersive: true,
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#080D1A',
    },
  },
  ios: {
    contentInset: 'automatic',
    preferredContentMode: 'mobile',
    scheme: 'Halo Live',
  },
  android: {
    allowMixedContent: true,
    backgroundColor: '#080D1A',
  },
}

export default config
