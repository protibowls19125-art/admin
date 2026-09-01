-- Migration: Create app_config table for storing WhatsApp and printer credentials
-- Run this in Supabase SQL Editor

-- Create app_config table
CREATE TABLE IF NOT EXISTS app_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key VARCHAR(100) UNIQUE NOT NULL,
  value JSONB NOT NULL,
  description TEXT,
  updated_by VARCHAR(255),
  updated_at TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Add comment
COMMENT ON TABLE app_config IS 'Stores application configuration like WhatsApp and thermal printer credentials';

-- Insert WhatsApp Business API configuration
INSERT INTO app_config (key, value, description)
VALUES (
  'whatsapp_credentials',
  '{
    "access_token": "YOUR_WHATSAPP_ACCESS_TOKEN",
    "phone_number_id": "YOUR_PHONE_NUMBER_ID",
    "admin_phone_number": "+91XXXXXXXXXX",
    "business_account_id": "YOUR_BUSINESS_ACCOUNT_ID"
  }'::jsonb,
  'WhatsApp Business API credentials - Update with your credentials from Meta Business Account'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Insert Thermal Printer configuration
INSERT INTO app_config (key, value, description)
VALUES (
  'thermal_printer_config',
  '{
    "printer_ip": "192.168.1.100",
    "printer_port": 9100,
    "printer_model": "Zebra ZPL",
    "paper_width_mm": 80,
    "auto_cut": true
  }'::jsonb,
  'Thermal printer network configuration - Update IP address and port for your printer'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Add RLS policies (optional - for admin access)
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

-- Policy: Allow authenticated admin users to read all config
CREATE POLICY "Allow admin read config" ON app_config
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users WHERE user_id = auth.uid()
    )
  );

-- Policy: Allow admin to update config
CREATE POLICY "Allow admin update config" ON app_config
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users WHERE user_id = auth.uid()
    )
  );

-- Grant permissions
GRANT SELECT ON app_config TO anon, authenticated;

-- Update guest_customers table to add 2-hour expiration
-- (If not already done in MIGRATION_UPDATE_CUSTOMER_FLOW.sql)
ALTER TABLE guest_customers ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP;

-- Create index for cleanup queries
CREATE INDEX IF NOT EXISTS idx_guest_customers_expires_at ON guest_customers(expires_at);

-- Add comment
COMMENT ON COLUMN guest_customers.expires_at IS 'Orders expire after 2 hours for guest customers';
