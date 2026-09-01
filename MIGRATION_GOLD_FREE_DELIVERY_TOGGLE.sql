-- One-time migration: "+ free delivery" was hardcoded, always-on marketing
-- text on every Gold plan everywhere it's shown. Makes it a real per-plan
-- admin toggle instead, matching how discount_percent already works.
-- Defaults true so existing plans keep behaving exactly as before.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.gym_membership_plans
  ADD COLUMN IF NOT EXISTS free_delivery BOOLEAN NOT NULL DEFAULT true;
