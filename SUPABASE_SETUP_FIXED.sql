-- Drop existing tables if they exist
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
  price NUMERIC(10, 2) NOT NULL,
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
  total_price NUMERIC(10, 2) NOT NULL,
  payment_method TEXT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (customer_id) REFERENCES public.guest_customers(id)
);

-- 4. ORDER ITEMS TABLE
CREATE TABLE public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL,
  menu_item_id UUID,
  quantity INTEGER DEFAULT 1,
  price NUMERIC(10, 2) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE,
  FOREIGN KEY (menu_item_id) REFERENCES public.menu_items(id)
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
  event_type TEXT NOT NULL,
  customer_id UUID,
  order_id UUID,
  data JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (customer_id) REFERENCES public.guest_customers(id),
  FOREIGN KEY (order_id) REFERENCES public.orders(id)
);

-- Enable RLS on all tables
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guest_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

-- Create RLS Policies - Allow all (for development)
CREATE POLICY "menu_items_all" ON public.menu_items FOR ALL USING (true);
CREATE POLICY "guest_customers_all" ON public.guest_customers FOR ALL USING (true);
CREATE POLICY "orders_all" ON public.orders FOR ALL USING (true);
CREATE POLICY "order_items_all" ON public.order_items FOR ALL USING (true);
CREATE POLICY "profiles_all" ON public.profiles FOR ALL USING (true);
CREATE POLICY "analytics_events_all" ON public.analytics_events FOR ALL USING (true);

-- Create Indexes for performance
CREATE INDEX idx_menu_category ON public.menu_items(category);
CREATE INDEX idx_menu_available ON public.menu_items(available);
CREATE INDEX idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX idx_guest_customers_phone ON public.guest_customers(phone);

-- Drop existing storage policies
DROP POLICY IF EXISTS "Public Access to menu-images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated upload to menu-images" ON storage.objects;

-- Create menu-images bucket storage policies
CREATE POLICY "Public Access" ON storage.objects FOR SELECT USING (bucket_id = 'menu-images');
CREATE POLICY "Upload Access" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'menu-images');
