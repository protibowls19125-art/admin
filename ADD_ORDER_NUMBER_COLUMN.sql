-- Run this in Supabase Dashboard → SQL Editor
-- =====================================================

-- 1. Add missing columns to orders table
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_number  TEXT,
  ADD COLUMN IF NOT EXISTS order_type    TEXT,
  ADD COLUMN IF NOT EXISTS customer_name TEXT,
  ADD COLUMN IF NOT EXISTS customer_phone TEXT,
  ADD COLUMN IF NOT EXISTS customer_info JSONB,
  ADD COLUMN IF NOT EXISTS items         JSONB;

CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);

-- 2. Counter table for atomic daily order numbering
CREATE TABLE IF NOT EXISTS public.order_counters (
  date_key TEXT PRIMARY KEY,
  counter  INT DEFAULT 0
);

ALTER TABLE public.order_counters ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all" ON public.order_counters FOR ALL USING (true);

-- 3. RPC function — returns next order number in DDMMCC format (IST timezone)
CREATE OR REPLACE FUNCTION get_next_order_number()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  today_prefix TEXT;
  today_key    TEXT;
  next_count   INT;
BEGIN
  today_prefix := TO_CHAR(NOW() AT TIME ZONE 'Asia/Kolkata', 'DDMM');
  today_key    := TO_CHAR(NOW() AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD');

  INSERT INTO public.order_counters (date_key, counter)
  VALUES (today_key, 1)
  ON CONFLICT (date_key) DO UPDATE
    SET counter = order_counters.counter + 1
  RETURNING counter INTO next_count;

  RETURN today_prefix || LPAD(next_count::TEXT, 2, '0');
END;
$$;
