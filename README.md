# Halo Live

DoorDash × Turo for apartment make-ready. One live order — Field builds it, Property authorizes with a PO, Crew accepts, Dispatch assigns. Cure windows are first-class.

## Run

```bash
git clone https://github.com/Surfguy1985/halo-live.git
cd halo-live
echo 'VITE_API_BASE=' > .env
npm install
PORT=5179 npm run dev
```

Empty `VITE_API_BASE` = browser calls `/api/*` via Vite proxy → `https://archangel-halo.replit.app`.

## Roles

| Role | Lands on |
|------|----------|
| Field / Vendor | `/units` menu · dispatch · crew |
| Pulse | `/approve` PO · `/track` ETA stack |
| Portfolio | `/live` map · dispatch · track |

## Design

Fixed seed: ink `#080D1A` · gold `#E3B85C` · live `#B4FF44` · paper `#F4F4F0` · Archivo + Martian Mono.

## Mobile app

Native **iOS** and **Android** via Capacitor. See [MOBILE.md](./MOBILE.md).

```bash
npm install
npx cap add ios
npm run mobile:ios
```
