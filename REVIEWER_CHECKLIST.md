# Reviewer Checklist

Use this checklist when cloning the project for a local review.

## Minimum working path

1. Create PostgreSQL database
2. Copy `backend/.env.example` to `backend/.env`
3. Set `DATABASE_URL`
4. Keep optional provider keys blank unless you want to test those integrations
5. Run:

```bash
cd backend
npm install
npm run setup:demo
npm start
```

6. Run Flutter:

```bash
cd gathergo
flutter pub get
flutter run --dart-define API_URL=http://localhost:3000
```

## Demo flows that should be reviewed first

- admin login
- user login
- big-event listing
- big-event booking
- spot creation
- spot joining
- spot moderation pages
- moderation queue and learning workflow

## Known limitations during review

- some advanced payment-provider paths may still depend on extra environment setup
- third-party services such as OpenAI, Stripe, Google Maps, and Airwallex may need environment keys
- Stripe-specific routes are disabled automatically when `STRIPE_SECRET_KEY` is not configured
- local uploads are intentionally excluded from Git and may not exist in a fresh clone
- if `API_URL` still points to `localhost`, use your machine IP instead when testing from a phone or another device

## Demo credentials

- Admin: `admin.demo@gathergo.local` / `Admin123!`
- User: `runner.one@gathergo.local` / `Runner123!`
- User: `runner.two@gathergo.local` / `Runner123!`
