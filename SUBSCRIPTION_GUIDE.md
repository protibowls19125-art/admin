# 🥗 Subscription Feature — Setup & Operations Guide

Home-delivery meal subscriptions: customer pays → fills preferences → manager
approves & creates their login → nightly WhatsApp "meal tomorrow?" → kitchen
prepares confirmed meals → manager assigns a delivery agent.

---

## 1. One-time setup

### a) Database
Run **`SUBSCRIPTION_SETUP.sql`** in the Supabase SQL Editor
(after `SECURITY_HARDENING.sql` and `ROLES.sql`, which are already applied).
It creates: `subscription_plans`, `subscriptions`, `meal_confirmations`,
`delivery_agents`, `subscription_banners`, `whatsapp_templates`, role helpers
(`is_sub_manager`, `is_sub_staff`), RLS policies, the `confirm_meal` RPC and
seed plans/templates/banner.

### b) Edge functions
```bash
supabase functions deploy subscription-create-order
supabase functions deploy subscription-verify-payment
supabase functions deploy subscription-submit-details
supabase functions deploy admin-manage-member
supabase functions deploy send-daily-meal-whatsapp
supabase functions deploy whatsapp-webhook --no-verify-jwt
```
> `whatsapp-webhook` must be public (`--no-verify-jwt`) because Meta calls it.
> It protects itself with the verify token + optional payload signature.

### c) Secrets
```bash
supabase secrets set CRON_SECRET=<long-random-string>
supabase secrets set WHATSAPP_VERIFY_TOKEN=<random-string-you-choose>
# Optional but recommended once you have them from Meta:
supabase secrets set WHATSAPP_APP_SECRET=<meta-app-secret>
```
(Razorpay secrets `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` are already set.)

### d) Nightly automation (8 PM IST)
Enable extensions **pg_cron** and **pg_net** (Database → Extensions), then run
the `cron.schedule` block at the bottom of `SUBSCRIPTION_SETUP.sql` with your
`CRON_SECRET` filled in.

### e) Subscription manager account (separate credentials)
1. Supabase → Authentication → Users → **Add user** (email + password, ✅ Auto Confirm)
2. SQL Editor:
```sql
INSERT INTO public.profiles (id, email, role)
SELECT id, email, 'sub_manager' FROM auth.users
WHERE email = 'subscriptions@yourdomain.com'
ON CONFLICT (id) DO UPDATE SET role = 'sub_manager';
```
This login sees **only** the subscription section of the admin panel.

### f) WhatsApp Business API (when credentials arrive)
1. Admin panel → Subscriptions → ⚙ Settings → **WHATSAPP** tab → paste
   *Access token* + *Phone number ID* → Save. Messages start flowing —
   **no code change needed**.
2. Meta App Dashboard → WhatsApp → Configuration → Webhook:
   - Callback URL: `https://pahanghosyepfuwcfexg.supabase.co/functions/v1/whatsapp-webhook`
   - Verify token: the `WHATSAPP_VERIFY_TOKEN` you set above
   - Subscribe to the **messages** field.

---

## 2. How each requirement maps

| Requirement | Where |
|---|---|
| Select plan → pay via Razorpay | Customer app `/subscribe` (server-priced, signature-verified) |
| Questions: name, mobile, preference, health goal | `/subscribe/details` (after payment) |
| Goes to admin panel, manager approves | Admin `/subs` → APPROVALS tab |
| Manager creates login + password | The **APPROVE** dialog (creates Supabase auth user, role `member`) |
| Premium card for members | Customer app `/member` (gold membership card, code MP-XXXX) |
| Nightly WhatsApp "meal tomorrow?" | `send-daily-meal-whatsapp` (pg_cron 20:00 IST, or "Send now" button) |
| Member confirms | WhatsApp reply YES/NO (webhook) **or** in-app buttons |
| Kitchen display: counts, priority, checkboxes, prepared/pending | Admin `/subs-kds` KITCHEN tab |
| Manager assigns delivery agent | Admin `/subs-kds` DELIVERY tab |
| Separate admin credentials | `sub_manager` role (confined to `/subs*`) |
| Add/remove members | `/subs` → ADD MEMBER button / REMOVE |
| Banners in the app | Admin `/subs-settings` → BANNERS (customer home page carousel) |
| Change WhatsApp messages without code | Admin `/subs-settings` → WHATSAPP templates editor |

## 3. Statuses

```
subscriptions:       awaiting_payment → payment_received → pending_approval
                     → active | rejected     (active → paused/cancelled/expired)
meal_confirmations:  awaiting → confirmed|skipped → preparing → prepared
                     → out_for_delivery → delivered   (missed = never confirmed)
```

## 4. Security model

- **Anon clients can't write** any subscription table — payment & onboarding go
  through edge functions (service role); prices always come from the DB.
- Razorpay signature is verified **server-side** (HMAC-SHA256) before a
  subscription is marked paid; failures land in `audit_log`.
- `admin-manage-member` re-verifies the caller's JWT **and** role on every call
  — the admin UI role check is cosmetic only.
- Members can read only their own row (`auth_user_id = auth.uid()`); their only
  write path is the `confirm_meal` RPC (own future meals, not yet in kitchen).
- Nightly job callable only with `CRON_SECRET` or a manager JWT; the Meta
  webhook enforces the verify token + optional `X-Hub-Signature-256`.
- Removing a member cancels the plan **and bans the auth user**.

## 5. Daily operations cheat-sheet (manager)

1. Morning: `/subs-kds` — check today's confirmed meals, bump priorities.
2. Chef ticks the checkbox as each meal is prepared (totals update live).
3. DELIVERY tab: assign an agent → SEND OUT → DELIVERED.
4. New signups: `/subs` APPROVALS — review details, tap APPROVE, share the
   login on WhatsApp.
5. Campaigns: `/subs-settings` — edit banners/plans/messages any time, live.
