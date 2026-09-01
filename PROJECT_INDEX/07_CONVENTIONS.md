# 07 · Conventions, Patterns & Gotchas

Read this before writing code so your changes match the existing style.

## State management pattern
- Every provider extends `ChangeNotifier`, exposes private `_field` + public getter, and calls
  `notifyListeners()` after mutations. Pages read via `context.read<X>()` / `context.watch<X>()` /
  `Consumer<X>`.
- Providers are registered in each app's `main.dart` `MultiProvider`. Add new ones there.

## Routing pattern
- One `GoRouter` per app in `router.dart`. Path params via `state.pathParameters['x']`,
  query params via `state.uri.queryParameters['x']`.
- Redirect logic is a top-level function passed to `GoRouter(redirect:)`.

## Supabase access pattern
- Always go through `SupabaseService.client` and the **table-name constants**
  (`SupabaseService.tableOrders`, `tableMenuItems`, …) — don't hardcode table strings.
- Wrap network calls in `try/catch`; the app is designed to **degrade gracefully** when Supabase is
  unreachable (local mirror keeps the UI alive). Follow the existing fallback style.

## Persistence pattern (the big one)
- Orders are written to **both** Supabase **and** `SharedOrdersService` (local
  `shared_preferences`, key `shared_all_orders`). Keep the local mirror in sync when you change
  order writes. The local copy stores the Supabase UUID as `supabase_id` for later status re-sync.
- `SharedOrdersService` and the guest-customer service are **duplicated across both apps** and share
  the same `shared_preferences` keys so the two apps see the same local data in one browser.

## Duplication to watch for
- `models/`, `supabase_service.dart`, and `shared_orders_service.dart` exist **separately in both
  `user/` and `admin/`**. A shared-shape change usually means editing **two files**.
- Admin has **two** order providers: `AdminOrderProvider` (plain) and `AdminOrdersProvider`
  (adds `startAutoRefresh`/`stopAutoRefresh`). Check which a page imports before editing.
- User app has both `app_theme.dart` (legacy blue) and `bauhaus_theme.dart` (**active**). Use
  `BauhausTheme`.

## Naming
- Order status strings: lowercase bare words — `pending`, `preparing`, `completed`, `cancelled`.
- Order types: dine-in / takeaway / delivery (stored in `order_type`).
- DB columns are `snake_case`; Dart fields are `camelCase`; models map between them in
  `fromJson`/`toJson`.
- Order numbers are **6-digit strings** (note the `.length == 6` checks), not ints.

## UI / theme
- Customer app = `BauhausTheme` ("Epicurean Minimalist"): use its color tokens, `radius*`,
  `cardShadow`/`floatingShadow`, and `heading()`/`body()` text helpers instead of raw values.
- Reuse the `Bauhaus*` widgets (`BauhausButton`, `BauhausCard`, `BauhausCategoryChip`, etc.) rather
  than building new primitives.
- Admin app = Material `AppTheme` with blue `AppColors`.

## Gotchas
- **`.env` is absent on web** — that's expected; fallbacks in `SupabaseService` handle it. Don't
  "fix" the try/catch around `dotenv.load`.
- `order_api_service.dart` (user) is a **stub** pointing at `api.your-business.com` with
  `YOUR_API_KEY_HERE` — not a live integration.
- The committed bundles in `gh-pages-deploy/` and inside `admin/` are **build output** — edit source
  and rebuild, never hand-patch them.
- RLS is wide open and the anon key is committed — fine for the demo, **not** production-safe.
- `print(...)` is used for logging throughout (e.g. order errors). Match that or upgrade
  deliberately.

## Where things live (quick map)
```
<app>/lib/
├── main.dart            # bootstrap + MultiProvider + MaterialApp.router
├── router.dart          # GoRouter routes + redirect/guard
├── models/              # MenuItem, Order (fromJson/toJson)
├── providers/           # ChangeNotifier state
├── services/            # Supabase + local storage + integrations
├── pages/               # screens (one class per route)
├── widgets/             # reusable UI components
└── theme/               # ThemeData + color/text tokens
```
