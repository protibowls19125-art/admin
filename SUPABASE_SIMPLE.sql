-- Drop existing tables
DROP TABLE IF EXISTS public.order_items CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.guest_customers CASCADE;
DROP TABLE IF EXISTS public.menu_items CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;
DROP TABLE IF EXISTS public.analytics_events CASCADE;

-- 1. MENU ITEMS TABLE
CREATE TABLE public.menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  price NUMERIC,
  category TEXT NOT NULL,
  image_url TEXT,
  available BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 2. GUEST CUSTOMERS TABLE
CREATE TABLE public.guest_customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT,
  gender TEXT,
  preference TEXT,
  is_info_complete BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP DEFAULT NOW() + INTERVAL '24 hours'
);

-- 3. ORDERS TABLE
CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID,
  total_price NUMERIC,
  payment_method TEXT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 4. ORDER ITEMS TABLE
CREATE TABLE public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID,
  menu_item_id UUID,
  quantity INTEGER DEFAULT 1,
  price NUMERIC,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 5. PROFILES TABLE
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY,
  email TEXT,
  role TEXT DEFAULT 'user',
  created_at TIMESTAMP DEFAULT NOW()
);

-- 6. ANALYTICS EVENTS TABLE
CREATE TABLE public.analytics_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT,
  customer_id UUID,
  order_id UUID,
  data JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guest_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies - Allow all
CREATE POLICY "Allow all" ON public.menu_items FOR ALL USING (true);
CREATE POLICY "Allow all" ON public.guest_customers FOR ALL USING (true);
CREATE POLICY "Allow all" ON public.orders FOR ALL USING (true);
CREATE POLICY "Allow all" ON public.order_items FOR ALL USING (true);
CREATE POLICY "Allow all" ON public.profiles FOR ALL USING (true);
CREATE POLICY "Allow all" ON public.analytics_events FOR ALL USING (true);

-- Indexes
CREATE INDEX idx_menu_category ON public.menu_items(category);
CREATE INDEX idx_orders_customer ON public.orders(customer_id);
CREATE INDEX idx_order_items_order ON public.order_items(order_id);
