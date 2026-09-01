-- =============================================================================
-- M1 fix: anti-flood rate limiting for order creation.
-- Private table used only by the razorpay-create-order edge function
-- (service_role). Not exposed to anon/authenticated. No app changes needed.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.order_rate_limit (
  id         BIGSERIAL PRIMARY KEY,
  ip         TEXT,
  phone      TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_orl_ip    ON public.order_rate_limit (ip, created_at);
CREATE INDEX IF NOT EXISTS idx_orl_phone ON public.order_rate_limit (phone, created_at);

-- RLS on, NO policies → anon/authenticated get nothing; only service_role
-- (the edge function) can read/write it (service_role bypasses RLS).
ALTER TABLE public.order_rate_limit ENABLE ROW LEVEL SECURITY;

-- (Optional) clear any old policies if this is re-run.
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='order_rate_limit'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.order_rate_limit;', p.policyname);
  END LOOP;
END $$;
