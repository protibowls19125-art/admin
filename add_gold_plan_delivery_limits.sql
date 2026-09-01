-- Gold membership plans: add delivery toggle and daily free order limit
-- Run in Supabase SQL Editor

ALTER TABLE gym_membership_plans
  ADD COLUMN IF NOT EXISTS delivery_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS max_free_orders_per_day integer DEFAULT 0;

COMMENT ON COLUMN gym_membership_plans.delivery_enabled IS 'Whether this plan includes delivery as an option';
COMMENT ON COLUMN gym_membership_plans.max_free_orders_per_day IS 'Number of free orders per day (0 = no free orders, discount-only)';
