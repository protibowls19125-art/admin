-- =============================================================================
-- MIGRATION: MANUAL ENTRY TO KDS + KDS TIMER & GYM IMPORT FIXES
-- Enables manual subscription entries to flow through KDS and support timers.
-- Run once in the Supabase SQL Editor.
-- =============================================================================

-- 1. Allow manual entries (no subscription_id) to exist in meal_confirmations
ALTER TABLE public.meal_confirmations
  ALTER COLUMN subscription_id DROP NOT NULL;

-- 2. Drop the old strict UNIQUE constraint that blocked multiple NULL subscription_id rows
ALTER TABLE public.meal_confirmations
  DROP CONSTRAINT IF EXISTS meal_confirmations_subscription_id_meal_date_key;

-- 3. Re-add partial unique index (enforced only when subscription_id IS NOT NULL)
CREATE UNIQUE INDEX IF NOT EXISTS uq_meal_sub_date
  ON public.meal_confirmations (subscription_id, meal_date)
  WHERE subscription_id IS NOT NULL;

-- 4. Add missing columns referenced by KDS push, timer, and delivery time logic
ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS pushed_to_kitchen BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS pushed_at TIMESTAMPTZ;

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS delivery_time TEXT DEFAULT '';

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS manual_entry_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'meal_confirmations_manual_entry_id_fkey'
  ) THEN
    ALTER TABLE public.meal_confirmations
      ADD CONSTRAINT meal_confirmations_manual_entry_id_fkey
      FOREIGN KEY (manual_entry_id) REFERENCES public.manual_subscription_entries(id) ON DELETE SET NULL;
  END IF;
END $$;

-- 5. Relax meal_count CHECK constraint to allow 1 (single-dish manual entries)
ALTER TABLE public.meal_confirmations
  DROP CONSTRAINT IF EXISTS meal_confirmations_meal_count_check;

ALTER TABLE public.meal_confirmations
  ADD CONSTRAINT meal_confirmations_meal_count_check
  CHECK (meal_count IS NULL OR meal_count >= 1);

-- 6. Payment tracking for delivery (cash & online UPI / Razorpay collection)
ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'unpaid';

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS payment_amount NUMERIC;

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS payment_collected_at TIMESTAMPTZ;

-- 7. Grant SELECT on manual_subscription_entries to all authenticated staff (delivery agents, chefs, managers)
DROP POLICY IF EXISTS "manual_entries_authenticated_select" ON public.manual_subscription_entries;
CREATE POLICY "manual_entries_authenticated_select" ON public.manual_subscription_entries
  FOR SELECT TO authenticated
  USING (true);
