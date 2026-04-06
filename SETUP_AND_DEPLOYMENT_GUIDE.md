# GatherGo: Web & Android Compatibility + QR Upload

## 📋 Overview

This document provides the **complete refactoring plan** to make GatherGo work on:
- ✅ Android Emulator (10.0.2.2:3000)
- ✅ Flutter Web (Chrome) (localhost:3000)
- ✅ iOS Simulator (localhost:3000)

Plus implementation of **QR code upload** for Big Event payments.

---

## 🐛 Root Cause Analysis: Web Compatibility Issues

### Problems Identified

1. **Unconditional `dart:io` imports** (11 files)
   - `Platform.isAndroid`, `Platform.isSecure` require `dart:io`
   - `File()` class doesn't exist on web
   - `Image.file()` doesn't work on web
   - `http.MultipartFile.fromPath()` only works on mobile

2. **Scattered baseUrl logic**
   - Different implementations across multiple files
   - No centralized configuration service
   - Mix of Android/iOS/web checks inconsistently applied

3. **Image handling incompatibilities**
   - `Image.file()` → must use `Image.memory()` on web
   - File picking with `image_picker` → works differently on web

### Solution Architecture

Created **Foundation Services** in `lib/core/`:
- `services/config_service.dart` - Centralized platform detection
- `services/image_processor.dart` - Cross-platform image handling
- `constants/app_constants.dart` - Shared constants

---

## 📁 Files Already Fixed

✅ **Completed:**
- `lib/core/services/config_service.dart` - NEW
- `lib/core/services/image_processor.dart` - NEW 
- `lib/core/constants/app_constants.dart` - NEW
- `lib/admin/data/event_api.dart` - Web-compatible file uploads
- `lib/admin/data/audit_log/audit_log_api.dart` - ConfigService
- `lib/user/big_event/big_event_list_page.dart` - ConfigService + URL resolver
- `lib/user/big_event/big_event_detail_page.dart` - ConfigService
- `lib/user/events/pages/event_evidence_page.dart` - Image.memory() + XFile
- `lib/user/my_spot/create_spot_page.dart` - Image.memory() + XFile

### Files Still Needing Fix (Template Pattern)

These files follow the same pattern. Use the **Quick Fix Template** below:

1. `lib/user/big_event/event_payment_page.dart`
2. `lib/user/big_event/payment_page.dart`
3. `lib/admin/user/user_detail_loader_page.dart`
4. `lib/admin/bigevent/organizer_detail_page.dart`
5. `lib/admin/bigevent/big_event_detail_page.dart`
6. `lib/admin/bigevent/create_big_event_page.dart`
7. `lib/admin/bigevent/bigevent_list_page.dart`
8. `lib/admin/bigevent/add_organizer_page.dart`

---

## 🔧 Quick Fix Template

For remaining 8 files, apply this pattern:

### Step 1: Update Imports
```dart
// ❌ REMOVE these:
import 'dart:io';

// ✅ ADD this:
import '../../core/services/config_service.dart';
```

### Step 2: Replace baseUrl getter
```dart
// ❌ REPLACE THIS:
String get _baseUrl {
  if (kIsWeb) return "http://127.0.0.1:3000";
  if (Platform.isAndroid) return "http://10.0.2.2:3000";
  return "http://127.0.0.1:3000";
}

// ✅ WITH THIS:
String get _baseUrl => ConfigService.getBaseUrl();
```

### Step 3: Use URL resolver
```dart
// ✅ If you have URL resolution logic:
String _resolveUrl(String? input) {
  return ConfigService.resolveUrl(input);
}
```

### Step 4: Fix Image display
```dart
// ❌ Replace Image.file():
Image.file(slipFile!, fit: BoxFit.cover)

// ✅ WITH Image.memory() for cross-platform:
Image.memory(slipBytes!, fit: BoxFit.cover)
```

### Step 5: Fix File uploads in event_api
```dart
// Already done in event_api.dart - it now handles both File (native) and XFile (web) automatically
```

---

## 🗄️ Database Migration

### Step 1: Apply SQL Migration
```sql
-- Add QR code storage columns to events table
ALTER TABLE events
ADD COLUMN IF NOT EXISTS qr_url TEXT;

ALTER TABLE events
ADD COLUMN IF NOT EXISTS qr_payment_method VARCHAR(50);

-- Verify:
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'events'
ORDER BY ordinal_position;
```

**File:** `backend/migrations/001_add_qr_column.sql`

---

## 🔌 Backend Implementation

### Step 1: Update server.cjs

**Reference:** `backend/QR_UPLOAD_IMPLEMENTATION.md`

Add these 6 sections to `backend/server.cjs`:

1. **Enhanced CORS** (~line 40)
   ```javascript
   const corsOptions = {
     origin: [
       'http://localhost:3000',
       'http://127.0.0.1:3000',
       'http://localhost:59968',
       'http://localhost:8080',
       'http://localhost:5000',
     ],
     credentials: true,
     methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
   };
   app.use(cors(corsOptions));
   ```

2. **QR upload directory** (~line 465)
   ```javascript
   const qrUploadDir = path.join(uploadDir, 'qr');
   if (!fs.existsSync(qrUploadDir)) fs.mkdirSync(qrUploadDir, { recursive: true });
   ```

3. **QR multer middleware** (~line 480)
   ```javascript
   const qrStorage = multer.diskStorage({...});
   const uploadQR = multer({storage: qrStorage, ...});
   ```

4. **QR upload endpoint** (~line 510)
   ```javascript
   app.post('/api/admin/events/:id/qr', uploadQR.single('file'), async (req, res) => {
     // See QR_UPLOAD_IMPLEMENTATION.md for full code
   });
   ```

5. **Error handling** (before app.listen())
   ```javascript
   app.use((err, req, res, next) => {
     if (err instanceof multer.MulterError) {
       return res.status(400).json({message: `File upload error: ${err.message}`});
     }
     next();
   });
   ```

6. **Update big-events endpoint** to include qr_url:
   ```javascript
   // Ensure SELECT includes: qr_url, qr_payment_method
   ```

---

## 📱 Flutter Implementation

### QR Display in Big Event Detail Page

```dart
// In big_event_detail_page.dart, display QR code:

// ✅ Get QR URL from event data
final qrUrl = event['qr_url'] ?? '';
final resolvedQrUrl = ConfigService.resolveUrl(qrUrl);

// ✅ Display with loading state
if (qrUrl.isNotEmpty)
  Image.network(
    resolvedQrUrl,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) {
      return Container(
        color: Colors.grey[200],
        child: const Center(child: Text('QR image failed to load')),
      );
    },
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return Center(
        child: CircularProgressIndicator(value: progress.expectedTotalBytes != null
            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
            : null),
      );
    },
  )
else
  const SizedBox(
    height: 200,
    child: Center(child: Text('QR code not yet uploaded')),
  ),
```

---

## 🚀 Backend Setup & Run

### Prerequisites
```bash
Node.js >= 14
PostgreSQL >= 12
npm or yarn
```

### Install Dependencies
```bash
cd backend
npm install
```

### Configure Environment
```bash
# Create .env file
PORT=3000
DATABASE_URL=postgres://postgres:YOUR_PASSWORD@localhost:5432/run_event_db2
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

### Run Database Migration
```bash
# Connect to PostgreSQL and run:
psql -U postgres -d run_event_db2 -f migrations/001_add_qr_column.sql
```

### Start Backend
```bash
npm start  # or: node server.cjs
```

**Expected Output:**
```
🔥 Connected: { db: 'run_event_db2', schema: 'public' }
🔥 users columns: [ 'id', 'email', ... ]
✅ Server running on http://localhost:3000
```

---

## 🎯 Flutter Setup & Run

### Android Emulator
```bash
cd gathergo

# Run on Android emulator
flutter run -d emulator-5554

# Or let Flutter auto-detect:
flutter run
```

### Flutter Web
```bash
cd gathergo

# Run on Chrome
flutter run -d chrome

# Or specify port if default is taken:
flutter run -d chrome --web-port 5000
```

### Check Web Compatibility
1. Open Chrome DevTools (F12)
2. Check Console for errors - should be **empty or only logs**
3. Network tab - all API calls should hit `http://localhost:3000`
4. No `dart:io` import errors
5. Images should load (Network tab should show 200 responses)

---

## ✅ Verification Checklist

### Web Platform (Chrome)
- [ ] `flutter run -d chrome` starts without compile errors
- [ ] No red errors in Chrome DevTools console
- [ ] Big Events list page loads
- [ ] QR image displays (if uploaded)
- [ ] Can navigate between pages
- [ ] Images load without broken image icons
- [ ] API calls to `http://localhost:3000` (not 10.0.2.2)

### Android Emulator
- [ ] `flutter run` works without errors
- [ ] Big Events list loads
- [ ] QR image displays
- [ ] API calls use `http://10.0.2.2:3000`
- [ ] Images load

### Backend
- [ ] Database has `qr_url`, `qr_payment_method` columns
- [ ] POST `/api/admin/events/:id/qr` accepts file upload
- [ ] QR files stored in `/uploads/qr/`
- [ ] GET `/api/big-events` returns `qr_url` field
- [ ] CORS allows localhost:8080, localhost:5000

### Admin QR Upload Flow
- [ ] Admin can access create event page
- [ ] File picker works (native or web)
- [ ] QR file uploads successfully
- [ ] QR URL returned in response
- [ ] QR image displays in user event detail page

---

## 📊 API Endpoint Reference

### QR Upload
```
POST /api/admin/events/:id/qr
Content-Type: multipart/form-data

Body:
  file: <image_file>
  payment_method: "promptPay" | "aliPay"

Response (200):
{
  "message": "QR code uploaded successfully",
  "id": 123,
  "qr_url": "/uploads/qr/qr_event_123_1708345667123.png",
  "qr_payment_method": "promptPay"
}
```

### Get Big Events
```
GET /api/big-events

Response (200):
[
  {
    "id": 123,
    "title": "Marathon 2026",
    "qr_url": "/uploads/qr/qr_event_123_1708345667123.png",
    "qr_payment_method": "promptPay",
    ...
  }
]
```

---

## 🐛 Troubleshooting

### Issue: "dart:io" import error on web
**Solution:** Remove `import 'dart:io'` and use `ConfigService`

### Issue: Platform.isAndroid not found on web
**Solution:** Use `ConfigService.isAndroid` instead

### Issue: Images don't load on web
**Solutions:**
1. Use `Image.network()` with full URL
2. Use `Image.memory()` for picked images
3. Check CORS - backend should allow all image requests
4. Check DevTools Network tab for 404 errors

### Issue: API calls to wrong baseUrl on web
**Solution:** All API calls should use `ConfigService.getBaseUrl()`

### Issue: QR file upload fails
**Solutions:**
1. Check `/uploads/qr/` directory exists
2. Check file size < 5MB
3. Check CORS headers allow file upload
4. Check multer errorHandler is in place

### Issue: QR image URL is null after upload
**Solution:** Ensure backend returns full URL path (e.g., `/uploads/qr/file.png`)

---

## 📦 Folder Structure (After Refactor)

```
gathergo/
├── lib/
│   ├── core/                          # NEW: Shared services
│   │   ├── services/
│   │   │   ├── config_service.dart    # Platform detection
│   │   │   └── image_processor.dart   # Image handling
│   │   └── constants/
│   │       └── app_constants.dart
│   ├── admin/
│   │   ├── pages/
│   │   ├── widgets/
│   │   └── data/
│   │       ├── event_api.dart         # UPDATED
│   │       └── audit_log/
│   ├── user/
│   │   ├── features/
│   │   │   ├── big_event/             # Contains detail page, list page
│   │   │   ├── spot/
│   │   │   └── payment/
│   │   └── data/
│   ├── widgets/
│   ├── constants/
│   ├── app_routes.dart
│   └── main.dart
│
├── pubspec.yaml
└── web/
    └── index.html
```

---

## 🔐 Security Notes

1. **CORS Configuration**
   - Current config allows `localhost` and `127.0.0.1`
   - In production, replace with your actual domain
   - Remove `localhost` from production CORS origins

2. **File Upload Validation**
   - Backend validates file size (5MB max)
   - Validates MIME type (images only)
   - Filename sanitized by multer

3. **QR Code Storage**
   - Files stored in `/uploads/qr/`
   - Directory created automatically
   - No authentication required for GET /uploads (public)
   - POST requires admin role (implement in backend if needed)

---

## 📚 Dependencies Used

- **Flutter/Dart:**
  - `image_picker: ^1.1.2` (cross-platform image selection)
  - `http: ^1.2.2` (HTTP client with web support)
  - `flutter/foundation.dart` (platform detection)

- **Backend (Node.js):**
  - `express: ^5.2.1`
  - `multer: ^2.0.2` (file upload handling)
  - `pg: ^8.18.0` (PostgreSQL)
  - `cors: ^2.8.5` (CORS middleware)

---

## 🎓 Next Steps

1. **Apply Quick Fix Template** to 8 remaining files
2. **Update backend** with 6 code sections from `QR_UPLOAD_IMPLEMENTATION.md`
3. **Run database migration** to add QR columns
4. **Test on Android** - Run flutter and verify 10.0.2.2 baseUrl
5. **Test on Web** - Run chrome and verify localhost:3000 baseUrl
6. **Test QR upload** - Admin creates event, uploads QR, user sees QR

---

## 📞 Support Files

- `backend/migrations/001_add_qr_column.sql` - Database migration
- `backend/QR_UPLOAD_IMPLEMENTATION.md` - Complete backend code
- `REFACTOR_PLAN.md` - Original refactor analysis
- This file - Complete setup guide

---

**Last Updated:** February 23, 2026
**Status:** 60% complete (core infrastructure done, UI files need quick fix template applied)
