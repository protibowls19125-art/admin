-- =============================================================================
-- Menu item price comparison — mirrors subscription_plans.compare_at_price
-- (ADD_DISCOUNT_AND_CHEF.sql). When compare_at_price > price, the customer
-- app shows a struck-through normal price + a green "SAVE X%" pill on the
-- food card and in the cart. Edit anytime: Admin -> Menu -> item -> "Normal
-- price ₹".
-- =============================================================================
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS compare_at_price NUMERIC(10,2) NOT NULL DEFAULT 0;
