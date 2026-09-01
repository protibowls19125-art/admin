-- One-time migration: fix confirm_meal() — the in-app "confirm today's
-- meal" RPC (user app, member_page.dart) — which was never updated when the
-- rest of the system (WhatsApp reminder/webhook, admin manual override)
-- moved from a next-day cycle to a SAME-DAY cycle. Two real bugs fixed:
--
--   1. It REJECTED today's date ("Only future meals can be changed") and
--      only accepted a future date — so the in-app button was confirming a
--      day nothing else in the system asks about, while today's actual
--      meal_confirmations row (the one the kitchen acts on) had no working
--      in-app path at all.
--   2. It never adjusted subscriptions.meals_remaining — unlike the
--      WhatsApp-reply path (whatsapp-webhook) and the manager's manual
--      override (admin-confirm-meal), both of which call
--      adjust_meals_remaining. An in-app confirm silently never moved the
--      member's meal balance.
--
-- Also adds the cutoff cascade: WhatsApp cutoff 11 AM (set separately in
-- Admin → Subscriptions → WHATSAPP SEND), in-app confirm closes 1 PM
-- (enforced here), manager override stays open 11 AM–6 PM
-- (admin-confirm-meal, already migrated).
--
-- Run once in the Supabase SQL Editor. Requires SUBSCRIPTION_SETUP.sql and
-- MIGRATION_MEALS_REMAINING.sql already applied.

CREATE OR REPLACE FUNCTION public.confirm_meal(p_meal_date DATE, p_confirm BOOLEAN)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sub public.subscriptions%ROWTYPE;
  v_new TEXT := CASE WHEN p_confirm THEN 'confirmed' ELSE 'skipped' END;
  v_current_status TEXT;
  v_meals_per_day INT;
  v_delta INT := 0;
  v_ist_hour INT;
BEGIN
  SELECT * INTO v_sub FROM public.subscriptions
  WHERE auth_user_id = auth.uid() AND status = 'active'
  LIMIT 1;
  IF v_sub.id IS NULL THEN
    RAISE EXCEPTION 'No active subscription for this account';
  END IF;

  -- Same-day cycle only, matching WhatsApp/admin (send-daily-meal-whatsapp
  -- asks about TODAY, same-day cutoff — not next-day).
  IF p_meal_date <> CURRENT_DATE THEN
    RAISE EXCEPTION 'Only today''s meal can be confirmed from the app';
  END IF;

  IF p_meal_date > COALESCE(v_sub.end_date, p_meal_date) THEN
    RAISE EXCEPTION 'Date is outside your subscription period';
  END IF;

  -- In-app window closes 1 PM IST — after that only a manager can still
  -- override (11 AM–6 PM, admin-confirm-meal); the cutoff auto-resolve in
  -- send-daily-meal-whatsapp finalizes anything still unanswered.
  v_ist_hour := EXTRACT(HOUR FROM (NOW() AT TIME ZONE 'Asia/Kolkata'))::int;
  IF v_ist_hour >= 13 THEN
    RAISE EXCEPTION 'Today''s meal can only be confirmed in the app before 1 PM';
  END IF;

  SELECT status INTO v_current_status FROM public.meal_confirmations
  WHERE subscription_id = v_sub.id AND meal_date = p_meal_date;

  -- Once the kitchen has picked it up, the app can't reach back and change
  -- it — same boundary the WhatsApp/admin paths respect.
  IF v_current_status IS NOT NULL
     AND v_current_status NOT IN ('awaiting', 'confirmed', 'skipped') THEN
    RAISE EXCEPTION 'Your meal is already with the kitchen and can''t be changed here';
  END IF;

  -- Same decision table as mealsRemainingDelta() (whatsapp-webhook /
  -- admin-confirm-meal) — a manual/app confirm must count identically to a
  -- real WhatsApp reply, or the balance quietly drifts wrong.
  SELECT meals_per_day INTO v_meals_per_day
  FROM public.subscription_plans WHERE id = v_sub.plan_id;
  v_meals_per_day := COALESCE(v_meals_per_day, 1);
  IF p_confirm AND COALESCE(v_current_status, 'awaiting') <> 'confirmed' THEN
    v_delta := -v_meals_per_day;
  ELSIF NOT p_confirm AND v_current_status = 'confirmed' THEN
    v_delta := v_meals_per_day;
  END IF;

  INSERT INTO public.meal_confirmations (subscription_id, meal_date, status,
                                         confirmed_via, confirmed_at)
  VALUES (v_sub.id, p_meal_date, v_new, 'app', NOW())
  ON CONFLICT (subscription_id, meal_date) DO UPDATE
    SET status = v_new, confirmed_via = 'app', confirmed_at = NOW(),
        updated_at = NOW();

  IF v_delta <> 0 THEN
    PERFORM public.adjust_meals_remaining(v_sub.id, v_delta);
  END IF;

  RETURN v_new;
END;
$$;
