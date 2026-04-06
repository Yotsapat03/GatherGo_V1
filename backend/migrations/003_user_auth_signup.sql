-- Ensure users table supports User-only signup/login fields
CREATE TABLE IF NOT EXISTS public.users (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  address TEXT NOT NULL,
  birth_year INTEGER,
  gender TEXT,
  occupation TEXT,
  password_hash TEXT NOT NULL,
  first_name TEXT,
  last_name TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  role_id INTEGER,
  last_login_at TIMESTAMPTZ,
  profile_image_url TEXT,
  national_id_image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS birth_year INTEGER;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS gender TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS occupation TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_name TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS role_id INTEGER;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS profile_image_url TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS national_id_image_url TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS password_hash TEXT;

-- Keep compatibility with existing app rows by defaulting missing values.
UPDATE public.users
SET
  name = COALESCE(NULLIF(name, ''), TRIM(CONCAT(COALESCE(first_name, ''), ' ', COALESCE(last_name, ''))), 'User'),
  phone = COALESCE(NULLIF(phone, ''), '-'),
  address = COALESCE(NULLIF(address, ''), '-'),
  password_hash = COALESCE(NULLIF(password_hash, ''), '$2a$10$7EqJtq98hPqEX7fNZaFWoOhi8I44qh13p6f9V6wiWvN8w4Jb8NQ.W')
WHERE
  name IS NULL
  OR phone IS NULL
  OR address IS NULL
  OR password_hash IS NULL
  OR name = ''
  OR phone = ''
  OR address = ''
  OR password_hash = '';

ALTER TABLE public.users ALTER COLUMN name SET NOT NULL;
ALTER TABLE public.users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE public.users ALTER COLUMN address SET NOT NULL;
ALTER TABLE public.users ALTER COLUMN email SET NOT NULL;
ALTER TABLE public.users ALTER COLUMN password_hash SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_unique_idx
  ON public.users (LOWER(email));
