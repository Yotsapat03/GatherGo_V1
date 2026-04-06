# GatherGo Flutter App

This folder contains the Flutter frontend for GatherGo.

For the full local setup flow, including backend and database preparation, see:

- [README.md](C:\mobileapp\GatherGo\README.md)
- [DB_SETUP.md](C:\mobileapp\GatherGo\DB_SETUP.md)

## Quick start

```bash
flutter pub get
flutter run --dart-define API_URL=http://localhost:3000
```

Android emulator:

```bash
flutter run --dart-define API_URL=http://10.0.2.2:3000
```

Physical device:

```bash
flutter run --dart-define API_URL=http://YOUR_LOCAL_IP:3000
```

## Notes

- This app expects the backend to be running
- Default local backend port is `3000`
- Some features depend on backend environment variables and database demo data
