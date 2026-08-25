# Halo Live — Mobile app (iOS / Android)

The full product (onboarding, order menu, PO, track, crew, map) ships as a **Capacitor** native shell around the same React app.

## Prerequisites (Mac for iOS)

- Node 20+
- Xcode 15+ (iOS)
- Android Studio (Android)
- CocoaPods: `sudo gem install cocoapods`

## One-time setup

```bash
cd ~/halo-live
git fetch origin && git reset --hard origin/main
echo 'VITE_API_BASE=https://archangel-halo.replit.app' > .env
# Or leave empty and point native webview at production after deploy

npm install

# Generate native projects (once)
npx cap add ios
npx cap add android
```

## Build & open

```bash
# Compile web → copy into native projects
npm run mobile:sync

# iOS Simulator / device
npm run mobile:ios
# Xcode: select a simulator → Run ▶

# Android
npm run mobile:android
```

## Live reload while coding UI

1. Start Vite on your Mac LAN IP:

```bash
PORT=5179 npm run dev
```

2. In `capacitor.config.ts`, temporarily set:

```ts
server: {
  url: 'http://YOUR_MAC_IP:5179',
  cleartext: true,
},
```

3. `npx cap sync` then run from Xcode/Android Studio.

4. Remove `server.url` before production builds.

## PWA (install from Safari)

Open the deployed or local site → Share → **Add to Home Screen**.  
Uses `manifest.webmanifest` + theme color `#080D1A`.

## App IDs

| | |
|--|--|
| **Bundle ID** | `com.archangel.halolive` |
| **Display name** | Halo Live |
| **Splash** | Dark ink `#080D1A` + gold ring |

## API

Native builds should set `VITE_API_BASE` to your live Halo API before `npm run build`:

```bash
echo 'VITE_API_BASE=https://archangel-halo.replit.app' > .env
npm run mobile:sync
```

## What’s included

- Splash + 6-step new-client onboarding  
- Service packages + green checkout  
- PO authorize, ETA stack, crew ping  
- Live map, photo verify, walk report  
- Status bar + splash plugins  
