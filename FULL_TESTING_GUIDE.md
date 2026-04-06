# 🚀 Full System Testing - READY TO START

**Status:** All components ready for full testing  
**Date:** February 23, 2026  
**Backend:** Running on port 3000  
**Database:** QR columns ✅ verified  

---

## ✅ Pre-Testing Checklist

### Backend Setup
- [x] Server.cjs has all 6 QR features
- [x] CORS configured for Flutter (web + Android)
- [x] QR upload directory created
- [x] /api/admin/events/:id/qr endpoint ready
- [x] GET /api/big-events returns qr_url + qr_payment_method
- [x] Database migration applied (qr_url, qr_payment_method columns exist)
- [x] .env file configured

### Flutter Setup
- [x] 8 pages refactored with ConfigService
- [x] ConfigService centralized baseUrl logic
- [x] All dart:io imports removed
- [x] Image.memory() for web compatibility
- [x] XFile + Uint8List for cross-platform images

### Database
- [x] qr_url column (TEXT)
- [x] qr_payment_method column (VARCHAR(50))
- [x] Index created for qr_url

---

## 🧪 Testing Phases

### Phase 1: Backend Verification (5 minutes)
```bash
# Start backend
cd backend
npm start
# OR
node server.cjs

# You should see:
# ✅ API running on port 3000
# ✅ Connected: { db: 'run_event_db2', schema: 'public' }
```

### Phase 2: Android Testing (20 minutes)

**1. Clear Flutter Build**
```bash
cd gathergo
flutter clean
flutter pub get
```

**2. Run on Android**
```bash
flutter run
```

**3. Test Big Event List**
- Navigate to Big Event section
- Verify events load correctly
- Check cover images display
- Look for qr_url in event data

**4. Test Android API Calls**
Expected behavior:
- API calls use 10.0.2.2:3000
- Images load correctly
- No dart:io errors

### Phase 3: Web Testing (20 minutes)

**1. Run on Chrome**
```bash
flutter run -d chrome
```

**2. Test Big Event List**
- Events should display
- Cover images should show
- QR URLs should be present in data

**3. Test Web API Calls**
Expected behavior:
- API calls use localhost:3000
- Images load via Image.network()
- No compilation errors

### Phase 4: Database Integration (10 minutes)

**1. Verify Event Data**
```javascript
// Check if events table has qr columns
SELECT id, title, qr_url, qr_payment_method FROM events LIMIT 5;

// Should return: (null for qr_url initially)
```

**2. Test QR Upload Endpoint** (Optional)
```bash
curl -X POST \
  -H "Content-Type: multipart/form-data" \
  -F "file=@test_qr.png" \
  -F "payment_method=promptPay" \
  http://localhost:3000/api/admin/events/1/qr
```

**3. Expected Response**
```json
{
  "message": "QR code uploaded successfully",
  "id": 1,
  "title": "Event Name",
  "qr_url": "/uploads/qr/qr_event_1_1708345667123.png",
  "qr_payment_method": "promptPay",
  "updated_at": "2026-02-23T10:30:00.000Z"
}
```

---

## 🐛 Common Issues & Solutions

### Issue 1: "dart:io not available" on Web
**Solution:** Already fixed - all dart:io imports removed, ConfigService used instead

### Issue 2: Images not showing on Web
**Solution:** Using Image.memory() - should work automatically

### Issue 3: API returns 404 for baseUrl
**Solution:** Check ConfigService.getBaseUrl() is returning correct URL for platform

### Issue 4: CORS error on Web
**Solution:** CORS already configured for localhost:8080 and localhost:5000

### Issue 5: File upload fails
**Solution:** Check /uploads/qr/ directory exists and is writable

---

## ✨ What You're Testing

### Android Emulator
```
Flutter App (localhost) 
    ↓
    ↓ HTTP request to 10.0.2.2:3000
    ↓
Backend (localhost:3000)
    ↓
    ↓ SQL query
    ↓
PostgreSQL Database
```

**Expected:** All requests work, images load, no errors

### Web (Chrome)
```
Flutter Web App (localhost:8080)
    ↓
    ↓ HTTP request to localhost:3000
    ↓
Backend (localhost:3000)
    ↓
    ↓ SQL query
    ↓
PostgreSQL Database
```

**Expected:** All requests work, images load, no compilation errors

---

## 📊 Test Scenarios

### Scenario 1: View Event List
1. Open app (Android or Web)
2. Navigate to "Big Events"
3. **Expected:** List loads, images display
4. **Check:** No errors in console

### Scenario 2: View Event Detail
1. Tap on event from list
2. **Expected:** Detail page opens with all fields
3. **Check:** Images display, QR URL present in data

### Scenario 3: Check API Response
1. Open DevTools (Web) or Logcat (Android)
2. Watch network requests
3. **Expected:** 
   - GET /api/big-events returns data with qr_url
   - baseUrl correctly set for platform
   - Images load successfully

### Scenario 4: Error Handling
1. Disconnect network
2. Try to load events
3. **Expected:** Graceful error message

---

## 🔍 Debug Commands

### Android Logcat
```bash
flutter logs
# Look for "baseUrl=", "ConfigService", "HTTP"
```

### Web DevTools
1. Open Chrome DevTools (F12)
2. Go to "Network" tab
3. Filter for API calls
4. **Check:**
   - Host is localhost:3000
   - Status 200 OK
   - Response includes qr_url

### Backend Logs
```bash
# Watch server.cjs console for:
# ✅ QR code uploaded
# ✅ GET /api/big-events
# ❌ Errors
```

---

## ⏱️ Estimated Times

| Task | Time |
|------|------|
| Phase 1: Backend Verify | 5 min |
| Phase 2: Android Test | 20 min |
| Phase 3: Web Test | 20 min |
| Phase 4: Integration Test | 10 min |
| **Total** | **~55 min** |

---

## ✅ Success Criteria

### Android ✅
- [ ] App runs without errors
- [ ] Big Events list displays
- [ ] Images load correctly
- [ ] API calls use 10.0.2.2:3000
- [ ] No dart:io errors in console

### Web ✅
- [ ] No compilation errors
- [ ] App loads in Chrome
- [ ] Big Events list displays
- [ ] Images load correctly
- [ ] API calls use localhost:3000

### Database ✅
- [ ] qr_url column exists
- [ ] qr_payment_method column exists
- [ ] Events can be queried with QR fields
- [ ] QR upload endpoint works (optional)

### Overall ✅
- [ ] Both platforms work identically
- [ ] No platform-specific code needed
- [ ] ConfigService handles all differences
- [ ] Ready for production

---

## 📝 After Testing

### If All Tests Pass ✅
1. ✅ Mark as production ready
2. ✅ Deploy to staging
3. ✅ Run acceptance tests with team
4. ✅ Deploy to production

### If Issues Found 🔧
1. Check error messages
2. Review debug logs
3. Apply fixes to specific files
4. Re-test affected scenarios

---

## 🎯 Next Steps

1. **Start Backend**
   ```bash
   cd backend
   npm start
   ```

2. **Choose Platform**
   - Android: `flutter run`
   - Web: `flutter run -d chrome`

3. **Run Tests** following Phase 1-4 above

4. **Verify** success criteria all check out

5. **Report** any issues

---

## 📞 Quick Reference

**Backend:**
- File: `backend/server.cjs`
- Port: 3000
- Status: Running ✅

**Database:**
- Host: localhost:5432
- DB: run_event_db2
- Status: Connected ✅
- Migration: Applied ✅

**Flutter:**
- Directory: `gathergo/`
- Android: `flutter run`
- Web: `flutter run -d chrome`

---

**Everything is ready! You're good to proceed with full testing.** 🚀
