-- =============================================================================
-- SECURITY HARDENING — replaces the wide-open `USING (true)` policies.
-- Run this in the Supabase SQL Editor. Apply the new edge functions and the
-- updated customer app TOGETHER with this (see SECURITY_HARDENING.md), because
-- after this runs the anon key can no longer write orders directly.
-- =============================================================================

-- 1. Link column so verify-payment can finalize the right pending order.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS razorpay_order_id TEXT;
CREATE INDEX IF NOT EXISTS idx_orders_rzp ON public.orders(razorpay_order_id);

-- 2. Admin check. SECURITY DEFINER so it can read profiles without tripping
--    the profiles RLS (and to avoid recursive policy evaluation).
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- 3. Drop EVERY existing policy on these tables by enumeration. Old open
--    policies can have any name (set up via dashboard or a different script),
--    and because policies are OR'd, one leftover `USING (true)` keeps the door
--    open. This catches them regardless of name.
DO $$
DECLARE p record;
BEGIN
  FOR p IN
    SELECT policyname, tablename FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('menu_items','orders','order_items',
                        'guest_customers','profiles','analytics_events')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I;', p.policyname, p.tablename);
  END LOOP;
END $$;

-- Make sure RLS is on (service_role bypasses RLS, so edge functions still work).
ALTER TABLE public.menu_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guest_customers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

-- 4. MENU_ITEMS — public can read the menu; only admins can change it.
CREATE POLICY "menu_public_read" ON public.menu_items
  FOR SELECT USING (true);
CREATE POLICY "menu_admin_write" ON public.menu_items
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 5. ORDERS / ORDER_ITEMS — NO anon access. Customers never touch these
--    directly; all order writes happen in edge functions (service_role, which
--    bypasses RLS). Admins (authenticated) get full access for the admin app.
CREATE POLICY "orders_admin" ON public.orders
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "order_items_admin" ON public.order_items
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 6. GUEST_CUSTOMERS / ANALYTICS — admin-only (PII). Writes via service_role.
CREATE POLICY "guest_customers_admin" ON public.guest_customers
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "analytics_admin" ON public.analytics_events
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 7. PROFILES — a user can read their own row; admins manage all.
CREATE POLICY "profiles_self_read" ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());
CREATE POLICY "profiles_admin" ON public.profiles
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 8. STORAGE (menu-images) — public read, but uploads only by admins.
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Upload Access" ON storage.objects;
DROP POLICY IF EXISTS "Public Access to menu-images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated upload to menu-images" ON storage.objects;
-- Drop our own names too, so this script is safe to re-run.
DROP POLICY IF EXISTS "menu_images_public_read"  ON storage.objects;
DROP POLICY IF EXISTS "menu_images_admin_write"  ON storage.objects;
DROP POLICY IF EXISTS "menu_images_admin_update" ON storage.objects;
DROP POLICY IF EXISTS "menu_images_admin_delete" ON storage.objects;
CREATE POLICY "menu_images_public_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'menu-images');
CREATE POLICY "menu_images_admin_write" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'menu-images' AND public.is_admin());
CREATE POLICY "menu_images_admin_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'menu-images' AND public.is_admin());
CREATE POLICY "menu_images_admin_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'menu-images' AND public.is_admin());

-- 9. Promote your admin account. REPLACE the email with your real admin login,
--    then this makes is_admin() true for it.
-- INSERT INTO public.profiles (id, email, role)
-- SELECT id, email, 'admin' FROM auth.users WHERE email = 'admin@example.com'
-- ON CONFLICT (id) DO UPDATE SET role = 'admin';



