# GatherGo Refactor & Enhancement Plan

## Phase 1: Diagnosis & Root Cause Analysis

### Web Compatibility Issues (Critical Blockers)

**Problem Sources:**
1. **Unconditional dart:io imports** (11 files)
   - `lib/user/events/pages/event_evidence_page.dart` - uses `File`, `Image.file()`
   - `lib/user/my_spot/create_spot_page.dart` - uses `File(file.path)`
   - `lib/user/big_event/event_payment_page.dart` - uses `defaultTargetPlatform`
   - `lib/user/big_event/payment_page.dart` - uses `defaultTargetPlatform`
   - `lib/user/big_event/big_event_list_page.dart` - uses `Platform.isAndroid`
   - `lib/user/big_event/big_event_detail_page.dart` - uses `Platform.isAndroid`
   - `lib/admin/data/audit_log/audit_log_api.dart` - uses `Platform`
   - `lib/admin/data/event_api.dart` - uses `Platform` + `File` for uploads
   - `lib/admin/user/user_detail_loader_page.dart` - uses `Platform`
   - `lib/admin/bigevent/organizer_detail_page.dart` - uses `dart:io`
   - `lib/admin/bigevent/big_event_detail_page.dart` - uses `Platform`
   - `lib/admin/bigevent/create_big_event_page.dart` - uses `dart:io`
   - `lib/admin/bigevent/bigevent_list_page.dart` - uses `Platform`
   - `lib/admin/bigevent/add_organizer_page.dart` - uses `Platform` + `File`

2. **BaseUrl resolution scattered across files** (3+ implementations)
   - Different logic in event_api.dart, big_event_list_page.dart, etc.
   - No centralized service

3. **File operations incompatible with web**
   - `Image.file()` - doesn't work on web
   - `http.MultipartFile.fromPath()` - only works on native platforms
   - `File(file.path)` - dart:io not available on web

### Database Migration Needed

**Current State:** Events table no longer stores QR images
**Solution:** Add `qr_url TEXT NULL` column to events table

### Backend Requirements

**Missing Endpoints:**
- `POST /api/admin/events/:id/qr` - QR upload (multipart/form-data)
- Need static file serving for `/uploads/qr/*`
- CORS configuration for Flutter Web

### Folder Structure Issues

**Current:** Scattered, hard to navigate
**Goal:** Feature-based, clear organization

---

## Phase 2: Implementation Plan

### Step 1: Create Config Service (Foundation)
**File:** `lib/services/config_service.dart`
- Centralize baseUrl resolution for all platforms
- Export configurable constants
- Handle web/iOS/Android differences

### Step 2: Create Image Processing Service
**File:** `lib/services/image_processor.dart`
- Abstract image picking differences (web vs native)
- Handle XFile to bytes conversion for web
- Provide web-safe image display widgets

### Step 3: Fix API Layer
**Files to Update:**
- `lib/admin/data/event_api.dart` - replace Platform checks, handle web file uploads
- Create new `lib/admin/data/file_upload_service.dart` for multipart uploads

### Step 4: Update All UI Files
**Files to Fix (14 total):**
- Remove direct `import 'dart:io'`
- Use config_service for baseUrl
- Use image_processor for image operations
- Replace `Image.file()` with web-safe alternative

### Step 5: Backend Changes
**Files to Update:**
- `backend/db.js` - add connection pool optimization
- `backend/server.cjs` - add QR upload endpoint, CORS config, static serving

### Step 6: Database Migration
**SQL Migration:** Add `qr_url` column to events table

### Step 7: Folder Refactoring
**New Structure:**
```
lib/
├── core/                          # NEW: Shared services & utils
│   ├── services/
│   │   ├── config_service.dart     # Platform config
│   │   ├── image_processor.dart    # Image handling
│   │   └── api_client.dart         # Centralized HTTP client
│   └── constants/
│       └── app_constants.dart
├── data/                          # NEW: Data layer (moved/consolidated)
│   ├── models/
│   │   ├── big_event.dart
│   │   ├── spot.dart
│   │   └── user.dart
│   ├── repositories/             # NEW: Repository pattern
│   │   ├── event_repository.dart
│   │   └── auth_repository.dart
│   └── api/
│       ├── event_api.dart
│       └── auth_api.dart
├── admin/                         # No change in structure
│   ├── pages/
│   └── widgets/
├── user/                          # Restructured
│   ├── features/
│   │   ├── big_event/
│   │   ├── spot/
│   │   └── payment/
│   └── shared/
├── widgets/                       # Shared UI components
└── main.dart
```

---

## Phase 3: Testing Strategy

### Web Compatibility Checklist
- [ ] No dart:io imports (grep verification)
- [ ] BaseUrl resolves correctly (debug logs)
- [ ] Images load on web (Image.network)
- [ ] File uploads work on web (HTTP multipart)
- [ ] No console errors in Chrome DevTools

### Android Compatibility
- [ ] All existing features work
- [ ] BaseUrl resolves to 10.0.2.2
- [ ] File picking works
- [ ] Image display works

### Feature Testing
- [ ] Big Event list loads
- [ ] QR image displays correctly
- [ ] Admin can upload QR
- [ ] Payment flow works
- [ ] Spot creation works

---

## Timeline Estimate
- Phase 1 (Services): 1-2 hours
- Phase 2 (File Updates): 2-3 hours  
- Phase 3 (Backend): 1 hour
- Phase 4 (Testing): 1-2 hours
- **Total: 5-8 hours**

---

## Git Strategy
- Create feature branch: `refactor/web-compat-qr-upload`
- Commit by phase
- Final PR with all changes

---

## Success Criteria
1. ✅ `flutter run -d chrome` runs without errors
2. ✅ Web app displays Big Events with QR images
3. ✅ Android emulator still works
4. ✅ Admin can upload QR via POST /api/admin/events/:id/qr
5. ✅ Code is organized and documented
6. ✅ No dead code, all imports are used
