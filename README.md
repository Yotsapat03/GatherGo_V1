# GatherGo

GatherGo is a Flutter + Node.js project with:

- user/admin app flows
- spot event features
- spot chat moderation
- reporting and moderation tools

This repository is being prepared so other people can clone it and try a local demo setup without using the original developer database.

## Repo structure

- `gathergo/`: Flutter application
- `backend/`: Node.js + PostgreSQL backend
- `backend/migrations/`: tracked SQL migrations
- `backend/scripts/`: local database setup scripts

## Current portability status

Portable enough for local demo setup:

- user auth
- admin auth
- big-event base flows
- spot events
- spot moderation tables
- moderation learning/vocabulary tables

Still more fragile than the rest of the repo:

- advanced payment-provider flows
- some production-oriented payment edge cases

## Prerequisites

Install these first:

- Node.js 18+ recommended
- PostgreSQL 14+ recommended
- Flutter SDK

## Backend setup

1. Go to the backend folder

```bash
cd backend
```

2. Install dependencies

```bash
npm install
```

3. Copy the example environment file and fill in what you need

Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

macOS/Linux:

```bash
cp .env.example .env
```

4. Update `.env`

Required for a basic local demo:

- `DATABASE_URL`
- `PORT`

The backend now stops with a clear startup error if `DATABASE_URL` is missing.

Optional and safe to leave blank if you only need core app flows:

- `OPENAI_API_KEY`: enables AI moderation assistance
- `GOOGLE_MAPS_API_KEY`: enables map/geocoding-related features
- `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`: enables Stripe checkout flows; if left blank, Stripe-specific endpoints are disabled but the main local demo can still run
- `AIRWALLEX_*`: enables Airwallex/Alipay payment flows
- `ANTOM_*`: enables Antom/Alipay integration paths

5. Run database migrations

```bash
npm run db:migrate
```

6. Check database readiness

```bash
npm run db:preflight
```

7. Seed demo data

```bash
npm run db:seed-demo
```

Or run the full database bootstrap in one step:

```bash
npm run setup:demo
```

8. Start backend

```bash
npm start
```

Default backend URL:

- `http://localhost:3000`

## Flutter setup

1. Open another terminal

```bash
cd gathergo
```

2. Install Flutter packages

```bash
flutter pub get
```

3. Run the app and point it to the backend

Web/Desktop:

```bash
flutter run --dart-define API_URL=http://localhost:3000
```

Android emulator:

```bash
flutter run --dart-define API_URL=http://10.0.2.2:3000
```

If testing on a physical device, replace with your machine IP:

```bash
flutter run --dart-define API_URL=http://YOUR_LOCAL_IP:3000
```

## Demo accounts

After `npm run db:seed-demo`:

- Admin: `admin.demo@gathergo.local` / `Admin123!`
- User: `runner.one@gathergo.local` / `Runner123!`
- User: `runner.two@gathergo.local` / `Runner123!`

Demo data also includes:

- 1 demo organization
- 1 demo big event
- 1 demo booking
- 1 demo payment
- 1 demo receipt
- 1 demo spot

## Important notes

1. Do not commit `backend/.env`
2. Do not commit `backend/uploads`
3. Do not commit real production or personal database dumps
4. Some advanced third-party payment flows may still need extra environment setup

## Database notes

For more DB-specific details, see:

- [DB_SETUP.md](./DB_SETUP.md)

For a quick explanation of available environment variables, see:

- [backend/.env.example](./backend/.env.example)

## Recommended demo scope

If you are sharing this repo with a lecturer or reviewer, the safest demo scope right now is:

- login
- admin login
- big-event listing and booking
- spot features
- spot moderation

## Reviewer shortcut

If you are setting this up only to review the project locally:

1. Configure `DATABASE_URL` in `backend/.env`
2. Run `cd backend && npm install && npm run setup:demo`
3. Start backend with `npm start`
4. Run Flutter with `--dart-define API_URL=...`

That is enough for the main demo scope even if third-party payment or AI keys are missing, as long as `DATABASE_URL` is configured.
