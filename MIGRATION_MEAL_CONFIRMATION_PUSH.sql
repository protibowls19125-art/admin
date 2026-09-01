-- Push notification when a member confirms their meal via the web app.
--
-- The WhatsApp webhook already sends a push when a member replies YES.
-- But the in-app confirm_meal() RPC only updates the DB — no push.
-- This trigger fires on INSERT/UPDATE to meal_confirmations when
-- status = 'confirmed', calling send-meal-confirmation-push via pg_net.
--
-- Run in Supabase SQL Editor AFTER deploying the edge function:
--   npx supabase functions deploy send-meal-confirmation-push
--
-- Replace <CRON_SECRET> with your live value before running.

CREATE OR REPLACE FUNCTION public.notify_meal_confirmed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM net.http_post(
    url     := 'https://esiatypehvnyeemvnzbl.supabase.co/functions/v1/send-meal-confirmation-push',
    headers := '{"Content-Type":"application/json","x-cron-secret":"7dfa50225b0ef27d13c555e8086b30087317ca65a29ed973499b968179b0af90"}'::jsonb,
    body    := jsonb_build_object(
      'subscription_id', NEW.subscription_id,
      'meal_date', NEW.meal_date
    )
  );
  RETURN NEW;
END;
$$;

-- Fire on INSERT when immediately confirmed
DROP TRIGGER IF EXISTS trg_notify_meal_confirmed_insert ON public.meal_confirmations;
CREATE TRIGGER trg_notify_meal_confirmed_insert
  AFTER INSERT ON public.meal_confirmations
  FOR EACH ROW
  WHEN (NEW.status = 'confirmed')
  EXECUTE FUNCTION public.notify_meal_confirmed();

-- Fire on UPDATE only if the status actually changed to 'confirmed'
DROP TRIGGER IF EXISTS trg_notify_meal_confirmed_update ON public.meal_confirmations;
CREATE TRIGGER trg_notify_meal_confirmed_update
  AFTER UPDATE ON public.meal_confirmations
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM 'confirmed' AND NEW.status = 'confirmed')
  EXECUTE FUNCTION public.notify_meal_confirmed();

-- Drop the old combined trigger if it exists
DROP TRIGGER IF EXISTS trg_notify_meal_confirmed ON public.meal_confirmations;
