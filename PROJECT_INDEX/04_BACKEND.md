# 04 · Backend (Supabase + SQL + Edge Functions)

**Project ref:** `pahanghosyepfuwcfexg` · URL `https://pahanghosyepfuwcfexg.supabase.co`
Both apps connect with the **anon key** (hardcoded fallback in `supabase_service.dart`, overridable
via `.env`). RLS is **open (`USING (true)`) for development** — see security note below.

## Database schema

Canonical setup script: **`SUPABASE_SETUP_FIXED.sql`** (the most complete root SQL file).
There are also `SUPABASE_SETUP.sql` and `SUPABASE_SIMPLE.sql` (earlier/simpler variants).

| Table | Key columns | Purpose |
|-------|-------------|---------|
| `menu_items` | `id`, `name`, `description`, `price`, `category`, `image_url`, `available`, + (via migrations) `featured`, nutrition (`protein/carbs/fat/fiber/serving_size/kcal`), `daily_limit`, `orders_today`, `last_reset_date` | Menu catalog |
| `orders` | `id`, `customer_id→guest_customers`, `total_price`, `payment_method`, `status`, + (migrations) `order_number`, `order_type`, `customer_name`, `customer_phone`, `customer_info` (JSONB), `items` (JSONB), `delivery_address` | Placed orders |
| `order_items` | `id`, `order_id→orders` (cascade), `menu_item_id→menu_items`, `quantity`, `price` | Line items |
| `guest_customers` | `id`, `name`, `phone`, `email`, `gender`, `preference`, `is_info_complete`, `expires_at` (NOW()+24h) | Guest diners |
| `profiles` | `id`, `email`, `role` | Admin/staff accounts |
| `analytics_events` | `id`, `event_type`, `customer_id`, `order_id`, `data` (JSONB) | Event tracking |

**Storage bucket:** `menu-images` (public read, open insert) — admin menu photo uploads.
**Indexes:** category, availability, orders.customer_id, order_items.order_id, guest_customers.phone.

> The base table definitions in `SUPABASE_SETUP_FIXED.sql` are the **minimal** schema. Several
> columns the apps rely on (e.g. `order_number`, `order_type`, `items` JSONB, `featured`, nutrition,
> `daily_limit`) are added by the migration files below — apply them too.

## RPC functions (called from Dart)

| RPC | Called by | Purpose |
|-----|-----------|---------|
| `get_next_order_number` | `OrderProvider.createOrder` (user) | Atomic 6-digit sequential order number (layer 1 of fallback). |
| `increment_item_order_count(p_item_id, p_quantity, p_date)` | `OrderProvider.createOrder` (user) | Bumps `menu_items.orders_today` for daily-limit "sold out" enforcement. |

(There is also a DB **trigger** that sets `order_number` on insert if the RPC wasn't used.)

## Migrations (root `MIGRATION_*.sql` / `ADD_*.sql`)

Apply on top of the base schema. Names are self-describing:

| File | Adds |
|------|------|
| `ADD_ORDER_NUMBER_COLUMN.sql` | `orders.order_number` + sequence/trigger/RPC |
| `MIGRATION_ADD_ORDER_TYPE.sql` | `orders.order_type` (dine-in / takeaway / delivery) |
| `MIGRATION_ADD_ORDER_DETAILS.sql` | order detail columns (customer info / items JSON) |
| `MIGRATION_ADD_FEATURED.sql` | `menu_items.featured` |
| `MIGRATION_APP_CONFIG.sql` | app-config table/values |
| `MIGRATION_UPDATE_CUSTOMER_FLOW.sql` | customer-flow schema changes |

> When the schema is unclear, **read the migration file** — it's the precise record of each change.

## Edge functions (`supabase/functions/`, Deno + TypeScript)

| Function | Input body | Purpose |
|----------|-----------|---------|
| `print-to-thermal-printer/index.ts` | `{ printerIp, printerPort, billContent, orderId }` | POST → send formatted bill to a network thermal printer. |
| `send-whatsapp-notification/index.ts` | `{ accessToken, phoneNumberId, adminPhoneNumber, message, orderId }` | POST → WhatsApp Business API notification to admin on new order. |
| `razorpay-create-order/index.ts` | `{ amount, currency?, receipt? }` | POST → creates a Razorpay order with `KEY_SECRET`; returns `{ orderId, amount, currency, keyId }`. Reads secrets from Deno env. |
| `razorpay-verify-payment/index.ts` | `{ razorpay_order_id, razorpay_payment_id, razorpay_signature }` | POST → verifies the HMAC-SHA256 payment signature with `KEY_SECRET`; returns `{ verified }`. |
| `subscription-create-order/index.ts` | `{ plan_id }` | Razorpay order for a subscription plan (price from DB) + skeleton `subscriptions` row. |
| `subscription-verify-payment/index.ts` | razorpay ids + signature | Verifies signature → subscription `payment_received`. |
| `subscription-submit-details/index.ts` | razorpay ids + onboarding fields | Attaches member details → `pending_approval`. |
| `admin-manage-member/index.ts` | `{ action: approve\|reject\|remove\|add_manual\|reset_password, … }` | Manager-only (JWT role re-checked): creates member logins, activates/cancels plans. |
| `admin-manage-staff/index.ts` | `{ action: invite\|revoke\|reactivate\|reset_password, … }` | Admin-only (JWT role re-checked, role must be exactly `admin`): creates/bans/unbans staff logins (`profiles` roles), resets passwords. |
| `send-daily-meal-whatsapp/index.ts` | cron secret header or manager JWT | Nightly: creates tomorrow's `meal_confirmations` + sends the WhatsApp question (templates from DB). |
| `whatsapp-webhook/index.ts` | Meta webhook (GET verify / POST messages) | YES/NO replies flip tomorrow's meal to confirmed/skipped; sends ack. Shared helpers in `_shared/whatsapp.ts`. |

### Subscription schema (see `SUBSCRIPTION_SETUP.sql` + `SUBSCRIPTION_GUIDE.md`)
Tables: `subscription_plans`, `subscriptions`, `meal_confirmations`,
`delivery_agents`, `subscription_banners`, `whatsapp_templates`, and
(`SUBSCRIPTION_MEALS.sql`) `subscription_meals` + `meal_schedule` — the
subscription's OWN dish catalog & per-date menu, separate from `menu_items`.
Role helpers `is_sub_manager()` / `is_sub_staff()`; member RPC `confirm_meal(date,bool)`.
Roles: `sub_manager` (subscription section only), `member` (customer app member area).

### Razorpay online payment (server-verified)
Edge fns + `user/lib/services/razorpay_service.dart` + `user/web/index.html` (checkout.js) implement
online payment for the **customer web app**. Order is created **only after** server-side signature
verification. Secrets (`RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`) are Supabase function secrets — never
in the client. Full setup: **`RAZORPAY_SETUP.md`** at repo root.

Both: reject non-POST (405), validate required fields (400), use `std@0.168.0/http/server`.

## ⚠️ Security notes (dev posture — harden before production)

- **Open RLS** (`USING (true)`) on every table — any anon client can read/write everything.
- **Anon key + Supabase URL hardcoded** in `supabase_service.dart` and committed `.env.example`.
- Edge functions take printer/WhatsApp credentials **in the request body** (not server secrets).

These are acceptable for a demo but should be locked down (real RLS policies, server-side secrets,
authenticated writes) before any real deployment.
