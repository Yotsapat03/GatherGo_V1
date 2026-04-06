ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_house_no TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_floor TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_building TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_road TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_subdistrict TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_district TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_province TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_postal_code TEXT;
