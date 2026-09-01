-- =============================================================================
-- 1) DISCOUNT BADGE — admin-editable "normal price" anchor per plan.
--    When compare_at_price > price, the customer app automatically shows the
--    struck-through normal price and a green "SAVE X%" pill.
--    Edit anytime: Admin → Subscriptions → Settings → PLANS → "Normal price ₹".
-- =============================================================================
ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS compare_at_price NUMERIC(10,2) NOT NULL DEFAULT 0;

-- Starter anchors (~10% saving shown). Change them in the admin panel.
UPDATE public.subscription_plans SET compare_at_price = 1665
  WHERE name = 'Weekly Starter'   AND compare_at_price = 0;
UPDATE public.subscription_plans SET compare_at_price = 5555
  WHERE name = 'Monthly Wellness' AND compare_at_price = 0;
UPDATE public.subscription_plans SET compare_at_price = 9999
  WHERE name = 'Monthly Pro'      AND compare_at_price = 0;

-- =============================================================================
-- 2) CHEF ACCOUNT — kitchen-only login (both kitchen displays).
--    Step 1: Dashboard → Authentication → Users → Add user
--            email + password + ✅ Auto Confirm
--    Step 2: replace the email below and run:
-- =============================================================================
-- INSERT INTO public.profiles (id, email, role)
-- SELECT id, email, 'chef' FROM auth.users
-- WHERE email = 'chef@prowtibowls.com'
-- ON CONFLICT (id) DO UPDATE SET role = 'chef';

-- What a chef login can do (already enforced — no further setup):
--   • Lands on /kds (orders kitchen); can also open /subs-kds (subscription
--     kitchen: see confirmed meals, tick prepared, adjust priority).
--   • CANNOT open dashboard, members, meal planner, settings, menu,
--     customers or analytics — the router + RLS both deny it.
