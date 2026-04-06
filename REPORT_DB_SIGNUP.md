# Signup/Login Database Issues Report

## Current status

No DB issues found in the current code implementation (schema + API guard logic are consistent), with one operational condition: migration `003_user_auth_signup.sql` must be applied to the target database before runtime.

## 1) Common DB issues that can break signup/login

1. Missing `users` table.
2. Missing required columns (for example: `name`, `phone`, `address`, `password_hash`, `profile_image_url`, `national_id_image_url`).
3. Email uniqueness not enforced, causing duplicate accounts.
4. `NOT NULL` violations when old rows are incomplete.
5. App code expects compatibility columns (`first_name`, `last_name`, `status`, `role_id`, `last_login_at`) but DB does not have them.
6. Migration not applied to the target database.
7. Upload payload issues for images (very large file, wrong multipart field names, or malformed request body).

## 2) How to diagnose each issue

1. Verify table exists:
```sql
SELECT to_regclass('public.users');
```

2. Verify column list:
```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema='public' AND table_name='users'
ORDER BY ordinal_position;
```

3. Verify email uniqueness index:
```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public' AND tablename='users';
```

4. Detect duplicate emails (case-insensitive):
```sql
SELECT LOWER(email) AS email_key, COUNT(*)
FROM public.users
GROUP BY LOWER(email)
HAVING COUNT(*) > 1;
```

5. Detect null/blank required fields:
```sql
SELECT id, email, name, phone, address
FROM public.users
WHERE name IS NULL OR phone IS NULL OR address IS NULL
   OR TRIM(COALESCE(name,''))='' OR TRIM(COALESCE(phone,''))='' OR TRIM(COALESCE(address,''))='';
```

6. Check backend logs during auth:
- Look for startup messages: `users auth columns ready`
- Check API errors: `Auth signup error` / `Auth login error`

7. Diagnose image upload/input issues:
- Confirm request is `multipart/form-data` with fields `profileImage` and `nationalIdImage`.
- Confirm files are under server upload limits and not blocked by proxy.
- Check server logs for multer/validation errors.

## 3) Changes made to prevent issues

1. Added migration `backend/migrations/003_user_auth_signup.sql`:
- Ensures table/columns for signup and compatibility.
- Adds case-insensitive unique index on email: `users_email_lower_unique_idx`.
- Backfills missing required values for old rows.
- Applies `NOT NULL` constraints to core signup fields.

2. Added backend runtime safeguard in `server.cjs`:
- `ensureUserAuthColumns()` runs at startup and before auth endpoints.

3. Added strict API validation:
- Required field checks.
- Email format check.
- Password min-length check.
- Duplicate email handling with 409 response.

4. Password security:
- Uses bcrypt hashing (`bcryptjs`) in `/api/auth/signup`.
- Uses bcrypt verify in `/api/auth/login`.
- No plaintext password storage.

5. Upload reliability:
- Backend accepts multipart uploads for `profileImage` and `nationalIdImage` and stores URLs.
- Required-field validation prevents empty image records for signup.
