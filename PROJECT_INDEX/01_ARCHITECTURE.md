# 01 · Architecture

## System overview

```
   ┌──────────────────┐                      ┌──────────────────┐
   │   CUSTOMER APP    │                      │    ADMIN APP      │
   │   (user/)         │                      │    (admin/)       │
   │  browse · order · │                      │  dashboard · KDS ·│
   │  track            │                      │  menu · analytics │
   └────────┬──────────┘                      └─────────┬─────────┘
            │                                            │
            │  supabase_flutter (anon key)               │
            ▼                                            ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                    SUPABASE PROJECT                          │
   │  Tables: menu_items, orders, order_items, guest_customers,  │
   │          profiles, analytics_events                         │
   │  Storage bucket: menu-images                                │
   │  RPCs: get_next_order_number, increment_item_order_count    │
   │  Edge functions: print-to-thermal-printer,                  │
   │                  send-whatsapp-notification                 │
   └─────────────────────────────────────────────────────────────┘
            ▲                                            ▲
            │  shared_preferences (browser localStorage) │
            └───────── "SharedOrdersService" ────────────┘
              (each app keeps a local mirror of orders)
```

## Two-layer persistence (important!)

Orders live in **two places at once**, and the app is written to tolerate the DB being unreachable:

1. **Supabase** (`orders` + `order_items` tables) — the canonical store.
2. **`shared_preferences`** local mirror (key `shared_all_orders`) via `SharedOrdersService` —
   present in **both** apps so the UI keeps working offline and across hot-reloads/refreshes.

When a customer places an order (`user/lib/providers/order_provider.dart` → `createOrder`):
- A 6-digit **order number** is obtained with a **3-layer fallback**:
  1. RPC `get_next_order_number` (atomic sequential),
  2. else a DB trigger sets `order_number` on insert,
  3. else a locally generated id.
- The row is inserted to Supabase; each line item inserted into `order_items`.
- The same order is mirrored to local `SharedOrdersService` (carrying the Supabase UUID as
  `supabase_id` so status can be re-synced later).
- Guest customer is recorded, and per-item daily order counts are incremented via RPC
  `increment_item_order_count` (used to enforce `daily_limit` "sold out").

On `fetchOrders`, the app reads the local mirror, then re-syncs each order's `status` from Supabase
using the stored `supabase_id`. This is how the **admin → customer status updates** propagate.

## Order status lifecycle

```
pending ──► preparing ──► completed
   │
   └──► cancelled   (customer or admin can cancel)
```
Status strings are bare lowercase: `pending`, `preparing`, `completed`, `cancelled`.

## App startup sequence

Both `main.dart` files do the same shape of work:
1. `WidgetsFlutterBinding.ensureInitialized()`
2. Lock to portrait (skipped on web for the user app)
3. `dotenv.load('.env')` (wrapped in try/catch — `.env` is absent on web, fallbacks kick in)
4. `SupabaseService.initialize()`
5. Init local services (`SharedOrdersService`; user app also inits `LocalStorageService` +
   `GuestCustomerTrackingService`)
6. `runApp` with a `MultiProvider` wrapping `MaterialApp.router`

## Provider wiring

**Admin** (`admin/lib/main.dart`): `AuthProvider`, `AdminMenuProvider`, `AdminOrderProvider`,
`AdminOrdersProvider`, `CustomerInfoProvider`.

**User** (`user/lib/main.dart`): `CustomerInfoProvider`, `MenuProvider`, `CartProvider`, `OrderProvider`.

## Routing

Each app has a single `router.dart` exporting a `GoRouter`. See per-app files for the route tables.
- **Admin** has an auth guard (`_authGuard`) redirecting to `/login` unless authenticated.
- **User** has a redirect that bounces away from `/customer-info` once info is complete.
