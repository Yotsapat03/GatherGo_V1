# DB Setup

This repo can now be prepared for local demo usage with:

```bash
cd backend
npm install
npm run setup:demo
```

## What these scripts do

- `db:migrate`: applies every SQL file in `backend/migrations` once and records it in `public.schema_migrations`
- `db:preflight`: checks whether the database already has the core tables needed by the app
- `db:seed-demo`: creates demo admin/user/event/payment data
- `setup:demo`: runs migrate, preflight, and seed in order with step-by-step console output

## Minimum environment setup

Required:

- `DATABASE_URL`
- `PORT`

If `DATABASE_URL` is missing, the backend now fails fast at startup with a clear error instead of silently using a placeholder connection string.

Optional:

- `OPENAI_API_KEY`
- `GOOGLE_MAPS_API_KEY`
- `STRIPE_*`
- `AIRWALLEX_*`
- `ANTOM_*`

The demo database bootstrap does not require the optional keys above.
Stripe-specific routes are disabled automatically when `STRIPE_SECRET_KEY` is not configured.

## Demo credentials

Default demo credentials after seeding:

- Admin: `admin.demo@gathergo.local` / `Admin123!`
- User: `runner.one@gathergo.local` / `Runner123!`
- User: `runner.two@gathergo.local` / `Runner123!`

Default demo entities after seeding:

- 1 organization
- 1 big event
- 1 paid booking
- 1 payment
- 1 receipt
- 1 spot

You can override these with environment variables:

- `DEMO_ADMIN_EMAIL`
- `DEMO_ADMIN_PASSWORD`
- `DEMO_USER_PASSWORD`

## Current limitation

The tracked migrations now include a base schema for:

- admin login
- users
- spot flows
- moderation flows
- organizations
- events
- bookings
- participants
- payments
- receipts

This should make local review much more portable than before.

There may still be edge cases where older production-only columns or assumptions are missing, especially in advanced payment/provider flows.
