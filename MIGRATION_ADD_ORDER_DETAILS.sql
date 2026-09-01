-- Migration: Add order details columns for customer app integration
-- Run this in Supabase SQL Editor

ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS order_number TEXT,
ADD COLUMN IF NOT EXISTS order_type TEXT,
ADD COLUMN IF NOT EXISTS customer_name TEXT,
ADD COLUMN IF NOT EXISTS customer_phone TEXT,
ADD COLUMN IF NOT EXISTS customer_info JSONB,
ADD COLUMN IF NOT EXISTS items JSONB;

ALTER TABLE public.order_items
ADD COLUMN IF NOT EXISTS name TEXT;

-- Indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON public.orders(created_at);
