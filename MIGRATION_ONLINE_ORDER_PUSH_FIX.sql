-- Fix: online orders (Razorpay) don't trigger push notifications
--
-- Root cause: orders are INSERT-ed as 'awaiting_payment', then UPDATE-d to
-- 'pending' by razorpay-verify-payment. But the trigger only fires
-- AFTER INSERT WHEN (NEW.status = 'pending') — an UPDATE to 'pending'
-- never triggers it.
--
-- Fix: add an AFTER UPDATE trigger that fires when status transitions
-- to 'pending' (from 'awaiting_payment').
-- Run in Supabase SQL Editor.

-- Keep the INSERT trigger for COD/free orders (they insert as 'pending'):
-- (no change needed to trg_notify_new_order)

-- Add UPDATE trigger for online orders:
DROP TRIGGER IF EXISTS trg_notify_online_order_confirmed ON public.orders;
CREATE TRIGGER trg_notify_online_order_confirmed
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  WHEN (OLD.status = 'awaiting_payment' AND NEW.status = 'pending')
  EXECUTE FUNCTION public.notify_new_order();
