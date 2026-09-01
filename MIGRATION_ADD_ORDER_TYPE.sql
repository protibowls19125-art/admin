-- Migration: Add order_type and expires_at columns to guest_customers table
-- Run this in Supabase SQL Editor

ALTER TABLE guest_customers
ADD COLUMN IF NOT EXISTS order_type VARCHAR(50),
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP;

-- Set default values for existing records
UPDATE guest_customers
SET order_type = 'dine_in', expires_at = NOW() + INTERVAL '2 hours'
WHERE order_type IS NULL OR expires_at IS NULL;

-- Create index for cleanup queries
CREATE INDEX IF NOT EXISTS idx_guest_customers_expires_at ON guest_customers(expires_at);

-- Add comment
COMMENT ON COLUMN guest_customers.order_type IS 'Order type: dine_in or takeaway';
COMMENT ON COLUMN guest_customers.expires_at IS 'Guest customer record expires after 2 hours';
