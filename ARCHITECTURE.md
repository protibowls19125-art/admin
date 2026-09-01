# ProtiBowl — Complete Architecture Reference

> **⚠️ AGENT INSTRUCTIONS**: Before scanning the codebase, READ THIS FILE FIRST.
> If this file exists, use it as your primary reference. After making changes,
> UPDATE this file with any new information, patterns, or files you discovered.
> This is the single source of truth for the project structure.

**Last Updated**: 2026-08-21

---

## 1. Project Overview

**ProtiBowl** is a food ordering + subscription meal platform built with:
- **2 Flutter web apps** (user-facing + admin panel)
- **Supabase** backend (Postgres DB, Edge Functions, Auth, Storage)
- **Razorpay** payment gateway
- **WhatsApp Cloud API** for subscription meal reminders
- **Google Sheets** for order/meal export
- **Firebase Cloud Messaging** for push notifications

**Supabase Project**: `esiatypehvnyeemvnzbl` (URL: `https://esiatypehvnyeemvnzbl.supabase.co`)

---

## 2. Repository Structure

```
Final_protibowl/
├── admin/                    # Admin Flutter web app
├── user/                     # Customer Flutter web app
├── supabase/
│   └── functions/            # Deno Edge Functions
│       ├── _shared/          # Shared utilities (whatsapp, firebase, geofence, security)
│       └── ...               # Individual edge functions
├── design/                   # Design assets
├── *.sql                     # Database migration scripts (run manually in Supabase SQL editor)
└── *.md                      # Documentation files
```

---

## 3. Two Business Models (Dual-Model Architecture)

The app runs TWO independent business models under one admin panel:

### Model 1: Gym/Restaurant (à la carte ordering)
- Customer browses menu → adds to cart → places order (online/COD/free)
- Admin manages via: Dashboard, Orders, KDS, Menu, Gym Delivery, Analytics
- Payment: Razorpay (online), Cash on Delivery, Free (₹0 items)

### Model 2: Subscription Meals (recurring meal delivery)
- Customer subscribes to a plan → gets daily meals delivered
- WhatsApp integration for meal preferences/reminders
- Admin manages via: Subscription Dashboard, Kitchen, Delivery, Meals, Responses, Settings

**Model Chooser**: Admin login → ModelChooserPage → routes to appropriate dashboard.

---

## 4. Admin App Architecture

### Entry Point
- `admin/lib/main.dart` — Initializes Supabase, Firebase, SharedOrdersService

### Providers (State Management — Provider pattern)
| Provider | File | Purpose |
|----------|------|---------|
| `AuthProvider` | `providers/auth_provider.dart` | Login/logout, role-based access. Singleton `adminAuth`. |
| `AdminMenuProvider` | `providers/admin_menu_provider.dart` | CRUD for menu items, image upload to Supabase Storage |
| `AdminOrdersProvider` | `providers/admin_orders_provider.dart` | Fetch/update orders, auto-refresh (15s), new-order detection, delivery agents |
| `AdminOrderProvider` | `providers/admin_order_provider.dart` | Single order operations |
| `CustomerInfoProvider` | `providers/customer_info_provider.dart` | Guest customer info |
| `SubscriptionAdminProvider` | `providers/subscription_admin_provider.dart` | Full subscription management (members, meals, plans, WhatsApp) |
| `GymMembershipAdminProvider` | `providers/gym_membership_admin_provider.dart` | Gold membership plan management |
| `StaffAdminProvider` | `providers/staff_admin_provider.dart` | Staff account CRUD (uses `admin-manage-staff` edge function) |

### Pages
| Page | Route | Purpose |
|------|-------|---------|
| `ModelChooserPage` | `/choose-model` | Pick Gym or Subscription model |
| `DashboardPage` | `/` or `/dashboard` | KPIs, recent orders, quick actions |
| `OrdersPage` | `/orders` | All orders list with status dropdown |
| `OrderDetailPage` | `/orders/:orderId` | ⚠️ PLACEHOLDER — shows only title |
| `KDSPage` | `/kds` | Kitchen Display System — order cards with images, timer, status flow |
| `MenuPage` | `/menu` | Full menu CRUD — add/edit items, images, badges, addons, nutrition |
| `AnalyticsPage` | `/analytics` | Sales charts, order trends |
| `CustomersPage` | `/customers` | Guest customer list |
| `GymDeliveryPage` | `/gym-delivery` | Assign delivery agents to orders |
| `AgentPerformancePage` | `/agent-performance` | Delivery agent stats |
| `ServiceHoursPage` | `/service-hours` | Operating hours, delivery toggle, off-days |
| `GymMembershipSettingsPage` | `/gym-membership-settings` | Gold membership plans |
| `StaffPage` | `/staff` | Staff account management |
| `SubscriptionDashboardPage` | `/subs` | Subscription model dashboard |
| `SubscriptionChefPage` | `/subs-kitchen` | Subscription kitchen view |
| `SubscriptionDeliveryPage` | `/subs-delivery` | Subscription delivery management |
| `SubscriptionMealsPage` | `/subs-meals` | Meal plan configuration |
| `SubscriptionResponsesPage` | `/subs-responses` | WhatsApp meal preference responses |
| `SubscriptionTodayPage` | `/subs-today` | Today's subscription orders |
| `SubscriptionSettingsPage` | `/subs-settings` | Developer-only subscription config |

### Role-Based Access Control
| Role | Access |
|------|--------|
| `developer` | Everything including `/subs-settings` |
| `admin` | Everything except `/subs-settings` |
| `gym_manager` | Gym model pages (orders, menu, KDS, service hours) — no subs, no staff, no dashboard/analytics |
| `sub_manager` | Subscription pages + agent performance — no gym pages |
| `gym_chef` | `/kds` only |
| `gym_delivery` | `/gym-delivery` only |
| `subs_chef` | `/subs-kitchen` only |
| `subs_delivery` | `/subs-delivery` only |

### Services
| Service | File | Purpose |
|---------|------|---------|
| `SupabaseService` | `services/supabase_service.dart` | Supabase client singleton |
| `SharedOrdersService` | `services/shared_orders_service.dart` | Local order cache (SharedPreferences) |
| `GuestCustomerService` | `services/guest_customer_service.dart` | Guest customer tracking |
| `PushNotificationService` | `services/push_notification_service.dart` | Firebase push notifications |

### Utilities
| Utility | File | Purpose |
|---------|------|---------|
| `new_order_sound_web.dart` | `utils/new_order_sound_web.dart` | Play notification sound on new orders (web Audio API) |
| `browser_notify_web.dart` | `utils/browser_notify_web.dart` | Browser push notifications |

### Widgets
| Widget | File | Purpose |
|--------|------|---------|
| `AuthGate` | `widgets/auth_gate.dart` | Login form UI |
| `ExitGuard` | `widgets/exit_guard.dart` | Prevent accidental back navigation |
| `DeliveryOrdersList` | `widgets/delivery_orders_list.dart` | Delivery order cards |
| `AddAgentDialog` | `widgets/add_agent_dialog.dart` | Add delivery agent dialog |
| `ModelSwitcher` | `widgets/model_switcher.dart` | Switch between Gym/Subscription |
| `KdsEmptyState` | `widgets/kds_empty_state.dart` | Empty state for KDS |

---

## 5. User App Architecture

### Entry Point
- `user/lib/main.dart` — Initializes Supabase, LocalStorage, SharedOrders, GuestCustomerTracking, ServiceHours

### Providers
| Provider | File | Purpose |
|----------|------|---------|
| `MenuProvider` | `providers/menu_provider.dart` | Fetch menu items from `menu_items` table |
| `CartProvider` | `providers/cart_provider.dart` | Cart state — add/remove/clear, total calculation |
| `OrderProvider` | `providers/order_provider.dart` | Place orders (online/COD/free), fetch order history |
| `CustomerInfoProvider` | `providers/customer_info_provider.dart` | Customer name/phone persistence |
| `SubscriptionProvider` | `providers/subscription_provider.dart` | Subscription plan browsing, onboarding |
| `GymMembershipProvider` | `providers/gym_membership_provider.dart` | Gold membership login/status/activation |

### Pages
| Page | Route | Purpose |
|------|-------|---------|
| `HomePage` | `/` | Featured items, menu grid, category tabs, promo banners |
| `HomePage(tab:1)` | `/menu` | Menu tab directly |
| `ProductDetailPage` | `/product/:id` | Full product view — nutrition, addons, spice, buy-now, add-to-cart |
| `OrderFormPage` | `/order` | Cart review, customer info, delivery address, payment selection, order placement |
| `ConfirmationPage` | `/confirmation?orderId=` | Order success — animation, order number, tracking link |
| `OrderTrackingPage` | `/my-orders` | Order history with real-time status |
| `CustomerInfoPage` | `/customer-info` | First-time customer info collection |
| `FaqPage` | `/faq` | FAQ accordion |
| `SubscriptionPage` | `/subscribe` | Browse subscription plans |
| `SubscriptionOnboardingPage` | `/subscribe/details` | Subscription signup flow |
| `MemberChooserPage` | `/member` | Choose Gold or Elite membership |
| `GoldMembershipPage` | `/member/gold` | Gold membership login/dashboard |
| `MemberPage` | `/member/elite` | Elite subscription member dashboard |
| `BillSheet` | (bottom sheet) | E-bill breakdown overlay |

### Services
| Service | File | Purpose |
|---------|------|---------|
| `SupabaseService` | `services/supabase_service.dart` | Supabase client singleton |
| `LocalStorageService` | `services/local_storage_service.dart` | SharedPreferences wrapper |
| `SharedOrdersService` | `services/shared_orders_service.dart` | Local order cache |
| `GuestCustomerTrackingService` | `services/guest_customer_tracking_service.dart` | Track guest visits |
| `ServiceHoursService` | `services/service_hours_service.dart` | Check if restaurant is open, delivery available |
| `BillCalc` | `services/bill_calc.dart` | Calculate subtotal, GST, delivery, discounts |
| `BillService` | `services/bill_service*.dart` | Generate PDF/print bill (web/mobile stubs) |
| `OrderApiService` | `services/order_api_service.dart` | Order API calls |
| `RazorpayService` | `services/razorpay_service*.dart` | Razorpay checkout (web/mobile/stub) |
| `RazorpayModels` | `services/razorpay_models.dart` | Razorpay data models |

### Widgets
| Widget | File | Purpose |
|--------|------|---------|
| `AppBottomNav` | `widgets/app_bottom_nav.dart` | Bottom navigation bar |
| `BauhausButton` | `widgets/bauhaus_button.dart` | Primary action button |
| `BauhausCard` | `widgets/bauhaus_card.dart` | Menu item card |
| `BauhausCategoryChip` | `widgets/bauhaus_category_chip.dart` | Category filter chip |
| `BauhausDivider` | `widgets/bauhaus_divider.dart` | Styled divider |
| `BauhausInfoBox` | `widgets/bauhaus_info_box.dart` | Info/notice box |
| `FloatingCartBar` | `widgets/floating_cart_bar.dart` | Sticky cart bar at bottom |
| `LocationPicker` | `widgets/location_picker.dart` | Map-based location picker for delivery |
| `LogoLoader` | `widgets/logo_loader.dart` | Branded loading animation |
| `PromoBannerCarousel` | `widgets/promo_banner_carousel.dart` | Auto-scrolling promo banners |
| `StatusAnimation` | `widgets/status_animation.dart` | Order status animated indicator |

### Models
| Model | File | Key Fields |
|-------|------|------------|
| `MenuItem` | `models/menu_item.dart` | id, name, description, price, compareAtPrice, category, tags, kcal, available, imageUrl, badge, featured, customizable, addons, nutrition (protein/carbs/fat/fiber), dailyLimit, ordersToday |
| `Order` | `models/order.dart` | id, userId, status, total, items, tableNumber, createdAt, completedAt |

---

## 6. Database Schema (Supabase Postgres)

### Core Tables
| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `menu_items` | Menu catalog | id, name, description, price, compare_at_price, category, tags, kcal, available, image_url, badge, featured, customizable, addons (JSONB), daily_limit, orders_today, last_reset_date, nutrition fields |
| `orders` | All orders | id, order_number (6-digit sequential), order_type (dine_in/takeaway/delivery), customer_name, customer_phone, total_price, payment_method (online/cod/free), status, items (JSONB), customer_info (JSONB), delivery_agent_id, synced_to_sheet, created_at, delivered_at |
| `order_items` | Line items (relational) | id, order_id (FK→orders), menu_item_id (FK→menu_items), quantity, note |
| `profiles` | Staff/admin accounts | id (FK→auth.users), role, name, phone |
| `guest_customers` | Guest customer records | id, name, phone, visit_count |
| `app_config` | Key-value config store | key, value (JSONB) |
| `delivery_agents` | Delivery staff roster | id, name, phone |
| `order_rate_limit` | Anti-flood rate limiting | id, ip, phone, created_at |
| `audit_log` | Security/monitoring | event, ip, detail (JSONB) |

### Gold Membership Tables
| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `gym_membership_plans` | Membership tiers | id, name, price, duration_days, discount_percent, free_delivery, delivery_enabled, max_free_orders_per_day, compare_at_price |
| `gym_memberships` | Active memberships | id, auth_user_id, plan_id, customer_name, phone, status (active/expired), start_date, end_date |

### Subscription Tables
| Table | Purpose |
|-------|---------|
| `subscription_plans` | Meal subscription plans |
| `subscriptions` | Active subscriptions |
| `subscription_meals` | Daily meal records |
| `subscription_responses` | WhatsApp meal preference responses |
| `meal_groups` | Meal grouping config |

### Config Keys (`app_config` table)
| Key | Purpose | Value Fields |
|-----|---------|--------------|
| `bill_config` | Billing settings | gst_percent, delivery_charge, cod_geofence_enabled, cod_center_lat, cod_center_lng, cod_radius_m |
| `service_hours` | Operating hours | open_time, close_time, delivery_enabled, off_days[] |
| `featured_section_label` | Homepage featured header | (string) |
| `promo_banners` | Homepage banner images | (array of URLs) |

### Storage Buckets
| Bucket | Purpose |
|--------|---------|
| `menu-images` | Menu item images |

---

## 7. Edge Functions (Supabase Deno)

### Order Flow
| Function | Purpose | Trigger |
|----------|---------|---------|
| `razorpay-create-order` | Create order — computes server-side price, handles online/COD/free payment, rate limiting, geofence check, Gold discount | User places order |
| `razorpay-verify-payment` | Verify Razorpay payment signature, update order status | After Razorpay checkout |
| `razorpay-webhook` | Handle Razorpay server-to-server webhooks | Razorpay callback |
| `cancel-order` | Cancel a pending order | User cancels |
| `get-order-status` | Check order status | Polling from user app |
| `export-orders-to-sheets` | Sync orders to Google Sheets (rows where synced_to_sheet=false) | pg_cron nightly + manual trigger |

### Subscription Flow
| Function | Purpose |
|----------|---------|
| `subscription-create-order` | Create subscription order with Razorpay |
| `subscription-verify-payment` | Verify subscription payment |
| `subscription-submit-details` | Submit subscription onboarding details |
| `send-food-preference-whatsapp` | Send meal preference question via WhatsApp |
| `send-daily-meal-whatsapp` | Send daily meal notification via WhatsApp |
| `whatsapp-webhook` | Receive WhatsApp message replies |
| `whatsapp-flow-endpoint` | WhatsApp Flows data exchange |
| `export-subscription-meals-to-sheets` | Export subscription meals to Sheets |
| `export-manual-entries-to-sheets` | Export manual entries to Sheets |
| `admin-confirm-meal` | Admin confirms meal delivery |

### Membership & Staff
| Function | Purpose |
|----------|---------|
| `gym-membership-create-order` | Create Razorpay order for Gold membership |
| `gym-membership-activate` | Activate Gold membership after payment |
| `gym-membership-reset-password` | Reset Gold member password |
| `admin-manage-member` | Admin CRUD for Gold members |
| `admin-manage-staff` | Admin CRUD for staff accounts |
| `submit-guest-customer` | Submit guest customer info |
| `send-order-push-notification` | Send FCM push for new orders |

### Shared Utilities (`_shared/`)
| File | Purpose |
|------|---------|
| `whatsapp.ts` | WhatsApp Cloud API wrapper (send template/text messages) |
| `firebase.ts` | Firebase Admin SDK init + FCM push |
| `geofence.ts` | Haversine distance calculation for COD geofence |
| `security.ts` | Admin role verification |
| `push.ts` | Push notification helpers |
| `meals-balance.ts` | Subscription meal balance calculator |

---

## 8. Order Flow (Critical Path)

### User Places Order
```
User App                          Edge Function                       Database
────────                          ─────────────                       ────────
CartProvider.total > 0?
  ├── Yes → OrderFormPage
  │         ├── Payment: online → placeOnlineOrder()
  │         ├── Payment: cod    → placeCodOrder()      
  │         └── Payment: free   → placeFreeOrder()     
  │                                    │
  │                         razorpay-create-order
  │                              │
  │                    ┌─────────┼─────────────┐
  │                    │         │             │
  │               online    cod/free      validate
  │                    │         │         items, price,
  │              Razorpay API    │         rate limit,
  │              create order    │         geofence (COD)
  │                    │         │             │
  │              Return rzp_id   │         Gold discount
  │                    │         │         GST + delivery
  │              User pays       │             │
  │                    │         │             │
  │          razorpay-verify  Direct insert    │
  │                    │    status: pending     │
  │                    │         │             │
  │                    └─────────┼─────────────┘
  │                              │
  │                     orders table INSERT
  │                     order_items INSERT
  │                     bump daily counters
  │                              │
  └── ConfirmationPage ←── orderNumber returned
```

### Order Status Flow
```
pending → confirmed → preparing → completed (dine_in/takeaway)
                                → prepared → in_transit → delivered (delivery)
                    → cancelled (at any point)
awaiting_payment (online orders before Razorpay confirms)
```

### Free Order Rules
- `price = 0` on menu item → displayed as "FREE" (green) everywhere
- Payment section hidden → green "FREE ORDER" banner shown
- Button: "PLACE FREE ORDER" (green) instead of "PLACE ORDER" (red)
- Edge function: `payment_method: "free"` skips Razorpay, direct insert
- Total validation: `total <= 0 && paymentMethod !== "free"` blocks non-free zero orders
- Spreadsheet export: included normally with `payment_method: "free"`

---

## 9. Payment Methods

| Method | Flow | Edge Function Behavior |
|--------|------|----------------------|
| `online` | Razorpay checkout → verify signature → update order status | Creates Razorpay order, returns `razorpayOrderId` to client |
| `cod` | Direct order placement, requires geofence verification | Checks `cod_geofence_enabled`, validates customer GPS within radius |
| `free` | Direct order placement, no payment | Validates `total <= 0`, inserts with `status: pending` |

---

## 10. Theming

### User App — Bauhaus Theme (`user/lib/theme/bauhaus_theme.dart`)
- **Design System**: Bauhaus-inspired with terracotta/black/white palette
- **Primary Colors**: `primaryBlack (#1A1A1A)`, `accentRed (#C75B39)` (terracotta), `white`
- **Typography**: Google Fonts — `Inter` for body, `Chivo` for headers
- **Constants**: `radiusSm`, `radiusMd`, `radiusLg`, `radiusPill`
- **Surfaces**: `surfaceBlack`, `patternGrey`, `mediumGrey`

### Admin App — (`admin/lib/theme/app_theme.dart`)
- Clean Material theme with `Chivo` font

---

## 11. Key Patterns & Conventions

### State Management
- **Provider** (ChangeNotifier) — both apps
- Providers registered in `main.dart` via `MultiProvider`
- Admin has singleton `adminAuth` for auth state

### Routing
- **go_router** — both apps
- Admin: role-based redirect guard in `router.dart` (`_authGuard`)
- User: simple redirect (skip customer-info if already filled)

### Database Access
- `SupabaseService.client` — static accessor in both apps
- Edge functions use `createClient()` from `@supabase/supabase-js`
- Tables accessed via `.from('table_name').select()/insert()/update()`

### Platform-Specific Code
- Conditional imports: `*_web.dart` / `*_io.dart` / `*_stub.dart`
- Examples: `razorpay_service_web.dart`, `bill_service_web.dart`, `new_order_sound_web.dart`

### Edge Function Conventions
- All functions use `Deno.serve()` with CORS headers
- JSON helper: `json(body, status)` for responses
- Shared code in `_shared/` imported via relative paths
- Deploy: `npx supabase functions deploy <function-name>`

### Order Number Format
- 6-digit sequential via `get_next_order_number()` RPC
- Fallback: DB trigger generates if RPC unavailable

### New Order Sound
- Web Audio API plays `/sounds/new_order.mp3` on KDS/Gym Chef pages
- `AdminOrdersProvider.onNewOrder` callback detects new pending orders
- Autoplay promise rejection handled with `.catchError()`

### Anti-Patterns to Avoid
- Never call `notifyListeners()` synchronously from `initState()` — use `Future.microtask()`
- Never skip CORS headers in edge functions
- Never trust client-side prices — always compute from DB in edge function

---

## 12. Build & Deploy Commands

```bash
# Run user app (dev)
cd user && flutter run

# Run admin app (dev)
cd admin && flutter run

# Build for web
cd user && flutter build web
cd admin && flutter build web

# Deploy edge function
npx supabase functions deploy <function-name>

# Deploy all edge functions
npx supabase functions deploy

# Run SQL migration
# Paste into Supabase Dashboard > SQL Editor
```

---

## 13. Environment Variables (Edge Functions)

| Variable | Purpose |
|----------|---------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key (full DB access) |
| `RAZORPAY_KEY_ID` | Razorpay API key |
| `RAZORPAY_KEY_SECRET` | Razorpay API secret |
| `WHATSAPP_TOKEN` | Meta WhatsApp Cloud API token |
| `WHATSAPP_PHONE_NUMBER_ID` | WhatsApp Business phone number ID |
| `GOOGLE_SHEETS_*` | Google Sheets API credentials |
| `FIREBASE_*` | Firebase service account for FCM |

---

## 14. Google Sheets Export

| Edge Function | Sheet | Trigger |
|--------------|-------|---------|
| `export-orders-to-sheets` | Orders sheet | pg_cron nightly + manual from admin Settings |
| `export-subscription-meals-to-sheets` | Subscription meals | Manual/scheduled |
| `export-manual-entries-to-sheets` | Manual entries | Manual |

- Uses `synced_to_sheet` boolean flag to avoid duplicates
- Idempotent — safe to call multiple times

---

## 15. WhatsApp Integration

- **Provider**: Meta WhatsApp Cloud API
- **Functions**: `send-food-preference-whatsapp`, `send-daily-meal-whatsapp`, `whatsapp-webhook`, `whatsapp-flow-endpoint`
- **Shared**: `_shared/whatsapp.ts` — template/text message sender
- **Config**: Admin can set reminder time, cutoff, skip Sundays/off-days via `app_config`

---

## 16. Changelog (Update this section with every change)

| Date | Change | Files Modified |
|------|--------|----------------|
| 2026-08-21 | Free order flow — hide payment for ₹0 items, green FREE banner, `placeFreeOrder()`, edge function `free` payment method | `order_form_page.dart`, `product_detail_page.dart`, `order_provider.dart`, `razorpay-create-order/index.ts`, `orders_page.dart` |
| 2026-08-21 | Remove "Order submitted to business API" / "Bill printing to thermal printer" from confirmation page | `confirmation_page.dart` |
| 2026-08-21 | New order sound fix — handle autoplay promise rejection | `new_order_sound_web.dart` |
| 2026-08-21 | Admin orders page — show "FREE" for ₹0 items/totals | `orders_page.dart` |
| 2026-08-21 | Deploy WhatsApp + Razorpay edge functions | `send-daily-meal-whatsapp/index.ts`, `razorpay-create-order/index.ts` |
| 2026-08-21 | Replace subscription "Buy Now" with "ENQUIRE NOW" Google Form redirect — admin-configurable URL via `app_config` key `subscription_enquiry_form_url`, editable in Subscription Settings → PLANS tab | `subscription_page.dart`, `subscription_provider.dart`, `subscription_settings_page.dart` |
| 2026-08-21 | Fix membership login — MemberChooserPage auto-detects Gold vs Elite and routes directly. Gold/Elite pages cross-check the other membership type and show redirect button instead of confusing "no active membership" | `member_chooser_page.dart`, `gold_membership_page.dart`, `member_page.dart` |
| 2026-08-22 | Gold plans — add `delivery_enabled` toggle and `max_free_orders_per_day` limit. Admin dialog updated, user plan cards and member dashboard show new info. SQL migration: `add_gold_plan_delivery_limits.sql` | `gym_membership_settings_page.dart`, `gold_membership_page.dart`, `gym_membership_provider.dart` |
| 2026-08-22 | Fix Razorpay mobile redirect — add confirm_close, retry on mobile, escape=false. Fix KDS sound for online orders — detect confirmed (not just pending). eBill: mobile-responsive viewport + CSS, delivery charge fallback to bill_config | `razorpay_service_web.dart`, `admin_orders_provider.dart`, `bill_service_web.dart`, `bill_calc.dart`, `bill_sheet.dart` |
| 2026-08-22 | Fix enquiry form URL not loading — RLS policy missing `subscription_enquiry_form_url` key. Migration: `MIGRATION_ENQUIRY_FORM_RLS.sql` | `subscription_provider.dart`, `subscription_page.dart`, `member_page.dart` |
| 2026-08-22 | Fix premature push notification for online orders — add AFTER UPDATE trigger that fires only when `awaiting_payment → pending` (after Razorpay payment verified). Migration: `MIGRATION_ONLINE_ORDER_PUSH_FIX.sql` — run in Supabase SQL Editor | `MIGRATION_ONLINE_ORDER_PUSH_FIX.sql` |
| 2026-08-22 | Subscription KDS — add CONFIRM button to silence looping new-meal sound (does not change meal status; chef still uses +/- stepper for prep tracking). Reappears when a new meal arrives | `subscription_chef_page.dart` |
| 2026-08-23 | Fix meal balance drift — when a manager overrides `meal_count` (e.g. 2→1) on Today's Meal edit-response, `meals_remaining` is now corrected by the delta via `adjust_meals_remaining` RPC. Previously only the plan's `meals_per_day` was deducted at confirmation time and the override was cosmetic-only | `subscription_today_page.dart`, `subscription_admin_provider.dart` |
| 2026-08-25 | Rebrand user app colors: updated accent color to Green (#007A3D), added tangerine yellow secondary accent (#FFCC00), changed background to Ivory (#FAF5E9). App title formatted to 'PROTI BOWLS' in uppercase without spaces. | `bauhaus_theme.dart`, `home_page.dart` |
| 2026-08-25 | Fix Razorpay checkout breaking due to iframe being blocked by cross-origin isolation. Removed `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers from `.htaccess`. Flutter falls back to dart2js+canvaskit. | `BUILD_Mithun/.htaccess`, `user/build/web/.htaccess`, `admin/build/web/.htaccess` |
| 2026-08-25 | Fix "setState() called during build" error in `AppBottomNav` when navigating tabs. Wrapped the `setState` callbacks in `addPostFrameCallback`. Force initial route to `/` on reload so users always land on home page. | `home_page.dart`, `router.dart` |
| 2026-08-28 | **Security audit — comprehensive fixes**: (1) Timing-safe HMAC comparison in `_shared/security.ts` + all 4 consumers (razorpay-verify-payment, razorpay-webhook, gym-membership-activate, whatsapp-webhook). (2) Security headers in both `.htaccess` (X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, X-XSS-Protection, Options -Indexes). (3) `X-Content-Type-Options: nosniff` added to all 24 edge function JSON responses. (4) Input validation: phone regex in razorpay-create-order + submit-guest-customer; email regex in admin-manage-staff + admin-manage-member (approve + add_manual). (5) Dead code cleanup: removed unused `_apiStatus`/`_apiSubmitted` in confirmation_page.dart, `_busy`/`_obscure`/`_login()` in member_page.dart, unused google_fonts import in logo_loader.dart. (6) Fixed `body_might_complete_normally_catch_error` lint in new_order_sound_web.dart. Both apps now pass `dart analyze` with 0 issues. | `_shared/security.ts`, `razorpay-verify-payment/index.ts`, `razorpay-webhook/index.ts`, `gym-membership-activate/index.ts`, `whatsapp-webhook/index.ts`, `razorpay-create-order/index.ts`, `submit-guest-customer/index.ts`, `admin-manage-staff/index.ts`, `admin-manage-member/index.ts`, all 24 edge function `index.ts` files, `user/build/web/.htaccess`, `admin/build/web/.htaccess`, `new_order_sound_web.dart`, `confirmation_page.dart`, `member_page.dart`, `logo_loader.dart` |
| 2026-08-28 | Fix 403 white-screen crash: removed `flutter_dotenv` entirely from admin app. Apache/cPanel blocks all dotfiles globally, so `assets/.env` fetch always 403'd. Credentials were already hardcoded in `SupabaseService`, so dotenv was dead code. Simplified `SupabaseService` to use `const` fields instead of runtime dotenv lookups. | `admin/lib/main.dart`, `admin/lib/services/supabase_service.dart`, `admin/pubspec.yaml` |
| 2026-08-28 | Fix 403 + black screen in user app: (1) Removed `flutter_dotenv` (same 403 issue as admin). (2) Rewrote `_forceRepaint()` to aggressively remove Razorpay's leftover DOM overlays (`.razorpay-container`, `.razorpay-backdrop`, iframes), reset `body.overflow`, and force Flutter canvas repaint via opacity toggle. (3) Added `visibilitychange` listener to handle mobile UPI app returns where Razorpay dismiss callback doesn't fire. | `user/lib/main.dart`, `user/lib/services/supabase_service.dart`, `user/pubspec.yaml`, `user/lib/services/razorpay_service_web.dart` |
| 2026-08-28 | Fix admin `FormatException: "<!DOCTYPE" is not valid JSON` — migrated `index.html` from deprecated `loadEntrypoint` API to modern `flutter_bootstrap.js` async loader. Removed stale `.env` access rule from `.htaccess`. Added security headers. Clean rebuild resolves asset loading errors. | `admin/web/index.html`, `admin/build/web/.htaccess` |
| 2026-08-29 | Subscription KDS fixes: (1) Sound acknowledgment now survives auto-refresh — `_stopSoundIfNothingPending` listener respects `_soundAcknowledged` flag so the ringtone doesn't restart every 20s after the chef taps CONFIRM. (2) Dedicated green ✓ PREPARED button on each kitchen card — single-meal orders (`total==1`) show only the button (no +/- stepper clutter); multi-meal orders keep the stepper plus a "mark all done" shortcut. (3) Marking a meal prepared immediately stops the sound (doesn't wait for async fetchMeals → listener chain). (4) CONFIRM button recolored to orange to visually distinguish it from the green PREPARED action. | `subscription_chef_page.dart` |
| 2026-09-01 | **Auto-confirm unanswered meal responses**: At a manager-configurable IST time (default 11:00 AM), all `awaiting` meal_confirmations for today are automatically promoted to `confirmed` (treat no-reply as YES). Runs BEFORE the existing cutoff sweep (which skips anything still awaiting). Admin panel: WHATSAPP SEND → AUTO-CONFIRM section with enable/disable toggle + time picker. Edge function: new sweep in `send-daily-meal-whatsapp` with `meal_auto_confirm_time` and `meal_auto_confirm_last_run` app_config keys. | `subscription_admin_provider.dart`, `subscription_settings_page.dart`, `send-daily-meal-whatsapp/index.ts` |
| 2026-09-01 | **Subscription KDS & Workflow Improvements**: (1) **Manual Entry to KDS**: Added dish and date pickers to the "Add manual entry" dialog. Selecting dishes now creates a `meal_confirmations` row so manual entries flow into Today's Meal and can be pushed to the kitchen. (2) **KDS Timer**: Added `pushed_at` timestamp to `pushToKitchen()` and an elapsed timer (`⏱ 5m`) on the chef page cards. (3) **Gym Menu Import**: Added "IMPORT FROM GYM MENU" button to quickly bulk-copy active dishes from the gym menu into the subscription library, deduplicating by name. (4) **WhatsApp Off-Day Bug**: Fixed IST day-of-week calculation in edge function. `Date.getDay()` was evaluating midnight IST as the previous day in UTC, causing Monday to be wrongly treated as Sunday (off-day). | `subscription_admin_provider.dart`, `subscriptions_page.dart`, `subscription_chef_page.dart`, `subscription_meals_page.dart`, `send-daily-meal-whatsapp/index.ts` |
| 2026-09-01 | **Delivery Dispatch Tabs, Payment Confirmation & Schema Resilience**: (1) Upgraded `DeliveryOrdersList` into a tabbed view with **ACTIVE DELIVERIES** (`prepared`, `out_for_delivery`) and **COMPLETED** (`delivered`). (2) Fixed `recordPayment` in `subscription_admin_provider.dart` with schema-resilient fallback so marking UPI / Cash payments never fails if payment columns are missing from `meal_confirmations`. (3) Fixed `PaymentCollectionDialog` async modal lifecycle and added inline spinners. (4) Fixed delivery time JSON header formatting across cards (`_formatDeliveryTimeHeader`). `flutter analyze` clean (0 issues). | `delivery_orders_list.dart`, `subscription_admin_provider.dart`, `subscription_today_page.dart`, `subscription_delivery_page.dart`, `ARCHITECTURE.md` |
| 2026-09-01 | **Fix Today's Meal card squished layout on mobile**: Replaced rigid `ListTile` horizontal layout with a structured, responsive `Card` (`Column`/`Row` with full-width dish slots and bottom action row for priority & PUSH). Added `manualEntries` fallback lookup in `SubscriptionTodayPage`. `flutter analyze` clean (0 issues). | `subscription_today_page.dart`, `ARCHITECTURE.md` |

