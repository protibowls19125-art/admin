-- One-time migration: real push notifications (fire even with the admin's
-- tab/browser closed) for "new order received" — via Firebase Cloud
-- Messaging. Replaces the old same-tab-only browser Notification.
--
-- Flow: order INSERT on public.orders → trg_notify_new_order fires
-- immediately (pg_net, not polled) → send-order-push-notification edge
-- function → FCM push to every registered admin/staff browser
-- (public.device_tokens, written by the admin app on login).
--
-- Run once in the Supabase SQL Editor. Requires pg_net already enabled
-- (it is, as of the meal-reminder automation) and CRON_SECRET already set.

-- ── 1. Device tokens — one row per (admin user, browser) ────────────────────
-- Written only by the admin app (push_notification_service.dart) on login,
-- so every row here already belongs to staff — the send function pushes to
-- all of them, no role filter needed.
CREATE TABLE IF NOT EXISTS public.device_tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token  TEXT NOT NULL,
  platform   TEXT NOT NULL DEFAULT 'web',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, fcm_token)
);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "device_tokens_own" ON public.device_tokens;
CREATE POLICY "device_tokens_own" ON public.device_tokens
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ── 2. Trigger: fire the instant a new order lands ──────────────────────────
-- Replace <CRON_SECRET> below with the live value (same one used by the
-- other pg_cron jobs in this project) before running.
CREATE OR REPLACE FUNCTION public.notify_new_order()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM net.http_post(
    url     := 'https://esiatypehvnyeemvnzbl.supabase.co/functions/v1/send-order-push-notification',
    headers := '{"Content-Type":"application/json","x-cron-secret":"<CRON_SECRET>"}'::jsonb,
    body    := jsonb_build_object('order_id', NEW.id, 'order_number', NEW.order_number)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_order ON public.orders;
CREATE TRIGGER trg_notify_new_order
  AFTER INSERT ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'pending')
  EXECUTE FUNCTION public.notify_new_order();
