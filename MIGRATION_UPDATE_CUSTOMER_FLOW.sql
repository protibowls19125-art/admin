-- Migration: Update guest_customers table to support complete order flow
-- Adds: address (delivery address), order_type (dine_in, takeaway, delivery)

-- Add new columns to guest_customers table
ALTER TABLE public.guest_customers
ADD COLUMN IF NOT EXISTS address TEXT,
ADD COLUMN IF NOT EXISTS order_type VARCHAR(50);

-- Add comment for clarity
COMMENT ON COLUMN public.guest_customers.address IS 'Customer delivery address';
COMMENT ON COLUMN public.guest_customers.order_type IS 'Order type: dine_in, takeaway, or delivery';

-- Create index for order_type for faster queries
CREATE INDEX IF NOT EXISTS idx_guest_customers_order_type
ON public.guest_customers(order_type);

-- Update RLS policy if needed (already set to allow all for development)
-- No changes needed - existing allow-all policies will handle new columns
