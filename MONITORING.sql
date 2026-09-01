-- =============================================================================
-- Security monitoring: an audit log of attack-signal events.
-- Written by the edge functions (service_role); readable only by admins.
-- Surfaced on the admin dashboard "Security Activity" card.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.audit_log (
  id         BIGSERIAL PRIMARY KEY,
  event      TEXT NOT NULL,          -- e.g. rate_limit_block, payment_verify_fail
  detail     JSONB,                  -- contextual info (phone, order id, counts)
  ip         TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_created ON public.audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_event   ON public.audit_log (event, created_at DESC);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Admins can read it; nobody else (service_role bypasses RLS to write it).
DROP POLICY IF EXISTS "audit_admin_read" ON public.audit_log;
CREATE POLICY "audit_admin_read" ON public.audit_log
  FOR SELECT TO authenticated
  USING (public.is_admin());

-- (Optional) let admins also see raw order-attempt volume from the rate limiter.
DROP POLICY IF EXISTS "order_rate_limit_admin_read" ON public.order_rate_limit;
CREATE POLICY "order_rate_limit_admin_read" ON public.order_rate_limit
  FOR SELECT TO authenticated
  USING (public.is_admin());
