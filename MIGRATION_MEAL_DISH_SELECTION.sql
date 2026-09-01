-- One-time migration: lets a manager pick specific dishes (from the same
-- Meal Planner catalog, subscription_meals) for a member's meals on a
-- SPECIFIC day, alongside the meal_count override — reviewed against
-- reply_text (the member's raw WhatsApp reply) from Today's Meal.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS selected_dish_ids JSONB NOT NULL DEFAULT '[]'::jsonb;
