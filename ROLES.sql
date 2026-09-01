-- =============================================================================
-- Role-based access for the admin panel.
--   admin    → full access
--   chef     → Kitchen Display only
--   delivery → Deliveries only
-- Role is stored in profiles.role. Orders are accessible to ALL staff;
-- menu management, customers and analytics stay ADMIN-only.
-- =============================================================================

-- Any staff member (admin / chef / delivery).
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
           SELECT 1 FROM public.profiles
           WHERE id = auth.uid() AND role IN ('admin','chef','delivery')
         )
      OR (auth.jwt() ->> 'email') = 'mithunsrinivas86@gmail.com';
$$;

-- Orders + order_items: any staff can read & update (KDS / deliveries).
DROP POLICY IF EXISTS "orders_admin" ON public.orders;
DROP POLICY IF EXISTS "orders_staff" ON public.orders;
CREATE POLICY "orders_staff" ON public.orders
  FOR ALL TO authenticated
  USING (public.is_staff()) WITH CHECK (public.is_staff());

DROP POLICY IF EXISTS "order_items_admin" ON public.order_items;
DROP POLICY IF EXISTS "order_items_staff" ON public.order_items;
CREATE POLICY "order_items_staff" ON public.order_items
  FOR ALL TO authenticated
  USING (public.is_staff()) WITH CHECK (public.is_staff());

-- (menu_items writes, guest_customers, analytics_events stay admin-only —
--  unchanged. Chef/delivery can read the menu since it's public-read.)

-- ── Create staff accounts ───────────────────────────────────────────────────
-- 1) Authentication → Users → Add user → email + password + ✅ Auto Confirm.
-- 2) Set each one's role here (replace the emails), then they log into /admin:
--
-- INSERT INTO public.profiles (id, email, role)
-- SELECT id, email, 'chef' FROM auth.users WHERE email = 'chef@example.com'
-- ON CONFLICT (id) DO UPDATE SET role = 'chef';
--
-- INSERT INTO public.profiles (id, email, role)
-- SELECT id, email, 'delivery' FROM auth.users WHERE email = 'delivery@example.com'
-- ON CONFLICT (id) DO UPDATE SET role = 'delivery';
