-- Adds the WhatsApp message sent when a member's plan completes
-- (meals_remaining hits 0). send-daily-meal-whatsapp's cron poll flips the
-- subscription to status='expired' and sends this — see the "Plan-completion
-- sweep" block in that function. Editable from Admin → Subscriptions →
-- WhatsApp Templates like the other ack messages.
--
-- Run once in the Supabase SQL Editor.

INSERT INTO public.whatsapp_templates (template_key, title, message_text) VALUES
  ('plan_completed', 'Plan completed (meals_remaining reaches 0)',
   'Hi {{name}} 👋 You''ve completed all the meals on your {{plan}} plan. '
   || E'\n\nThanks for being with us! Reach out or visit the app to renew and keep the meals coming. 🌱')
ON CONFLICT (template_key) DO NOTHING;
