-- One-time migration: marks a subscription as a developer test member. Test
-- members flow through the exact same reminder/reply/confirm/push pipeline
-- as real members, but are excluded from every real aggregate stat (active
-- member count, membership revenue, KDS prep totals, survey response
-- counts) so testing never skews production numbers. They still show up in
-- the normal Members/Today's Meal/Survey Responses lists with a TEST badge.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS is_test BOOLEAN NOT NULL DEFAULT false;
