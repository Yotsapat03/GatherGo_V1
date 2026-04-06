# Quick Start: Finish the Refactor

**Start Here:** Follow these 5 simple steps to complete the refactor.

---

## 📌 What's Done for You

✅ Core services created  
✅ 4 UI pages fixed (event list, detail, evidence, spot creation)  
✅ Event API refactored for web  
✅ Database migration script ready  
✅ Backend implementation guide ready  
✅ Complete documentation provided  

---

## 💻 Step 1: Test Current State (5 minutes)

### Android Emulator
```bash
cd gathergo
flutter run
```

**Expected Result:**
- App launches without errors
- Big Events list loads
- No "Platform.isAndroid" errors

### Flutter Web
```bash
cd gathergo
flutter run -d chrome
```

**Expected Result:**
- Launches without compile errors
- No red errors in Chrome console
- Can navigate pages

---

## 🔧 Step 2: Apply Quick Fix to 8 Pages (1-2 hours)

**Use this template for each file:**

### File Template (for all 8 remaining pages)

Replace the imports at the top:
```dart
// ❌ REMOVE:
import 'dart:io';

// ✅ ADD:
import '../../core/services/config_service.dart';  // (adjust ../ count)
```

Find and replace the baseUrl getter:
```dart
// ❌ OLD:
String get _baseUrl {
  if (kIsWeb) return "http://127.0.0.1:3000";
  if (Platform.isAndroid) return "http://10.0.2.2:3000";
  return "http://127.0.0.1:3000";
}

// ✅ NEW:
String get _baseUrl => ConfigService.getBaseUrl();
```

If file has `_resolveUrl` function, simplify it:
```dart
// ✅ Replace with (or just use ConfigService.resolveUrl() directly):
String _resolveUrl(String? input) => ConfigService.resolveUrl(input);
```

### Files to Apply Template To

1. `lib/admin/bigevent/create_big_event_page.dart`
2. `lib/admin/bigevent/bigevent_list_page.dart`
3. `lib/admin/bigevent/big_event_detail_page.dart` (admin version, different from user)
4. `lib/admin/bigevent/add_organizer_page.dart`
5. `lib/admin/bigevent/organizer_detail_page.dart`
6. `lib/admin/user/user_detail_loader_page.dart`
7. `lib/user/big_event/event_payment_page.dart`
8. `lib/user/big_event/payment_page.dart`

### Verify Each File
After editing each file, run:
```bash
flutter analyze lib/<path-to-file>
```

Should show **0 errors**

---

## 🗄️ Step 3: Database Migration (10 minutes)

### Connect to Database
```bash
# Open PostgreSQL
psql -U postgres -d run_event_db2

# Or if you have a different setup:
# psql -h localhost -U your_user -d your_db
```

### Run Migration
```sql
-- Copy-paste from backend/migrations/001_add_qr_column.sql:
ALTER TABLE events
ADD COLUMN IF NOT EXISTS qr_url TEXT;

ALTER TABLE events
ADD COLUMN IF NOT EXISTS qr_payment_method VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_events_qr_url ON events(qr_url);
```

### Verify
```sql
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'events' 
AND column_name LIKE 'qr%' 
ORDER BY ordinal_position;

-- Should return:
-- qr_url        | text
-- qr_payment_method | character varying
```

---

## 🚀 Step 4: Backend Implementation (2-3 hours)

**File:** `backend/server.cjs`

### Option A: Manual (if you're comfortable editing)

**Reference:** `backend/QR_UPLOAD_IMPLEMENTATION.md`

Add 6 sections:
1. Enhanced CORS (~line 40)
2. QR upload directory (~line 465)
3. QR multer middleware (~line 480)
4. QR upload endpoint (~line 510)
5. Update big-events GET endpoint
6. Error handler (before app.listen())

### Option B: Automated (paste these blocks)

Find each location by searching for the line number/comment, then paste the code from `backend/QR_UPLOAD_IMPLEMENTATION.md`

### Verify Backend

```bash
cd backend
npm start
```

Should output:
```
🔥 Connected: { db: 'run_event_db2', schema: 'public' }
✅ App listening on port 3000
```

---

## 📱 Step 5: Test Everything (1 hour)

### Test 1: Android Emulator
```bash
cd gathergo
flutter run
```

- [ ] App launches
- [ ] No dart:io errors
- [ ] Big Events list loads
- [ ] Images load
- [ ] Can navigate pages

### Test 2: Flutter Web
```bash
cd gathergo
flutter run -d chrome
```

- [ ] No compile errors
- [ ] Chrome console clean (no dart:io errors)
- [ ] Big Events list loads
- [ ] Images load  
- [ ] API calls use `http://localhost:3000`

### Test 3: QR Upload (Backend)
```bash
# Start backend first:
cd backend
npm start

# Then test endpoint with curl:
curl -X POST http://localhost:3000/api/admin/events/1/qr \
  -F "file=@test_qr.png" \
  -F "payment_method=promptPay"

# Should return:
# {
#   "message": "QR code uploaded successfully",
#   "id": 1,
#   "qr_url": "/uploads/qr/qr_event_1_..."
# }
```

### Test 4: QR Display (Frontend)
- In app, view big event detail page
- QR image should display (if uploaded)
- Image should load from `/uploads/qr/`

---

## ✅ Final Checklist

### Compilation
- [ ] No dart:io import errors
- [ ] No Platform.isAndroid errors  
- [ ] Web compiles without errors
- [ ] Android compiles without errors

### Runtime (Android)
- [ ] App starts
- [ ] Big Events page loads
- [ ] API calls use 10.0.2.2:3000
- [ ] Images display

### Runtime (Web Chrome)
- [ ] App starts
- [ ] Big Events page loads
- [ ] API calls use localhost:3000
- [ ] Images display
- [ ] DevTools console clean

### Database
- [ ] qr_url column exists
- [ ] qr_payment_method column exists

### Backend
- [ ] Server starts on port 3000
- [ ] POST /api/admin/events/:id/qr endpoint works
- [ ] QR files saved to /uploads/qr/
- [ ] CORS headers include localhost:8080

### QR Feature
- [ ] Admin can upload QR code
- [ ] QR URL stored in database  
- [ ] QR URL returned in API response
- [ ] User sees QR image on event detail page

---

## 🐛 Troubleshooting

### "dart:io not available on web"
- Check imports at top of file
- Should NOT have `import 'dart:io'`
- Should have `import '../../core/services/config_service.dart'`

### "Platform.isAndroid not found"
- Replace with `ConfigService.isAndroid`
- Or use `ConfigService.getBaseUrl()` instead

### Images showing as broken on web
- Don't use `Image.file()` - use `Image.memory()` or `Image.network()`
- Check DevTools Network tab for 404 errors
- Verify backend is serving `/uploads/` static files

### API calls wrong port/host on web
- Use `ConfigService.getBaseUrl()` in all page classes
- Check big_event_list_page.dart for example
- All models should use service, not hardcoded "localhost"

### QR upload returns 404
- Check POST endpoint is `/api/admin/events/:id/qr`
- Check event ID is valid
- Check backend server is running
- Check CORS allows the request

### QR image not displaying
- Event detail page needs to resolve URL with `ConfigService.resolveUrl()`
- QR URL might be relative like `/uploads/qr/file.png`
- Check `Image.network()` has proper error handler

---

## 📞 Help Resources

1. **SETUP_AND_DEPLOYMENT_GUIDE.md** - Full setup guide
2. **backend/QR_UPLOAD_IMPLEMENTATION.md** - Backend code
3. **lib/core/services/config_service.dart** - How baseUrl works
4. **lib/admin/data/event_api.dart** - Example of web-compatible API

---

## 🎉 What You'll Have After This

✅ **Web Compatible:**
- Flutter app runs on Chrome
- No dart:io errors
- All images load

✅ **Android Compatible:**
- Flutter app runs on Android emulator
- Uses 10.0.2.2:3000 correctly
- All Images load

✅ **QR Upload Feature:**
- Admin can upload payment QR code
- Users see QR image in event detail
- QR stored reliably in database

✅ **Clean Architecture:**
- Centralized configuration service
- Web/native abstraction layer
- Easy to add new platforms

---

## ⏱️ Time Estimate

| Task | Time |
|------|------|
| Apply template to 8 files | 1-2 hrs |
| Database migration | 10 min |
| Backend implementation | 2-3 hrs |
| Testing & verification | 1 hr |
| **Total** | **4-7 hrs** |

---

## 🚀 After Completion

0. Commit all changes:
```bash
git add .
git commit -m "refactor: web & android compatibility + QR upload"
```

1. Update version in pubspec.yaml:
```yaml
version: 1.1.0+2  # was 1.0.0+1
```

2. Ready to share with team!

---

**Questions?** Refer to the detailed guides in the `SETUP_AND_DEPLOYMENT_GUIDE.md` file.

Good luck! 🎉
