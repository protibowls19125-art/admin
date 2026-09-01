# 03 · Admin App (`admin/`)

**Package:** `mpro_dining_admin` — "M·PROTI Dining Admin — Supabase Authentication". Flutter web app for staff.
**Theme:** `AppTheme` (Material blue, `AppColors.primary = #1E88E5`).
**Entry:** `admin/lib/main.dart` → `MPROTIDiningAdminApp` → `MaterialApp.router`.
**Extra deps vs user app:** `image_picker` (menu photos), `fl_chart` (analytics).

## Authentication

`admin/lib/widgets/auth_gate.dart` (`AuthGate`) + `providers/auth_provider.dart` (`AuthProvider`).
`router.dart`'s `_authGuard` redirects any unauthenticated request to `/login`, and sends an
authenticated user away from `/login` to `/`. `AuthProvider.isAuthenticated` is keyed on `_userEmail`.

## Routes (`admin/lib/router.dart`)

| Path | Page |
|------|------|
| `/login` | `AuthGate` |
| `/` and `/dashboard` | `DashboardPage` |
| `/orders` | `OrdersPage` |
| `/orders/:orderId` | `OrderDetailPage` |
| `/menu` | `MenuPage` |
| `/analytics` | `AnalyticsPage` |
| `/customers` | `CustomersPage` |
| `/kds` | `KDSPage` (Kitchen Display System) |
| `/subs` | `SubscriptionDashboardPage` (stats + nav; sub_manager's landing page, confined to `/subs*`) |
| `/subs-members` | `SubscriptionsPage` (approvals + members) |
| `/subs-kds` | `SubscriptionKdsPage` (subscription kitchen + delivery assignment; chef can access) |
| `/subs-meals` | `SubscriptionMealsPage` (Meal Planner: dish library CRUD + daily menu per preference) |
| `/subs-settings` | `SubscriptionSettingsPage` (plans / banners / WhatsApp templates+creds / agents) |
| `/staff` | `StaffPage` (admin-only: invite/revoke/reactivate staff logins + reset password, via `admin-manage-staff` edge fn) |

## Pages (`admin/lib/pages/`)

| File | Lines | Role |
|------|-------|------|
| `menu_page.dart` | 1123 | **Menu management** (CRUD items, image upload, daily limits, featured). Contains `_MenuItemCard`. Largest file in the app. |
| `orders_page.dart` | 649 | Orders list with status tabs (`_OrderList`); status updates. |
| `dashboard_page.dart` | 312 | Landing: KPIs/stat cards (`_StatCard`). |
| `kds_page.dart` | 294 | Kitchen Display System — live order cards (`_OrderCard`) for kitchen staff. |
| `analytics_page.dart` | 283 | Charts/metrics via `fl_chart` (`_MetricCard`). |
| `customers_page.dart` | 89 | Guest customer list + export. |
| `order_detail_page.dart` | 21 | Thin single-order view (takes `orderId`). |

## Providers (`admin/lib/providers/`)

| File | Class | Responsibility |
|------|-------|----------------|
| `admin_menu_provider.dart` | `AdminMenuProvider` | Menu item list + category selection for admin CRUD. |
| `admin_order_provider.dart` | `AdminOrderProvider` | Order list + derived counts (`pendingOrders`, `preparingOrders`, `completedOrders`, `totalSales`). |
| `admin_orders_provider.dart` | `AdminOrdersProvider` | Like above **plus `startAutoRefresh`/`stopAutoRefresh`** (polling timer; disposes cleanly). Used for live views (KDS/orders). |
| `auth_provider.dart` | `AuthProvider` | Login/logout state; `isAuthenticated`. |
| `customer_info_provider.dart` | `CustomerInfoProvider` (+ `GuestCustomer`) | Loads guest customers for the customers page. |
| `subscription_admin_provider.dart` | `SubscriptionAdminProvider` | Whole subscription section: approvals/members (via `admin-manage-member` edge fn), KDS meals + auto-refresh, agents, and the no-code editors (plans/banners/templates/WhatsApp creds). |
| `staff_admin_provider.dart` | `StaffAdminProvider` | Staff (`profiles`) list + invite/revoke/reactivate/reset-password via `admin-manage-staff` edge fn; role-only changes go direct to `profiles` (RLS-gated to admins). |

> ⚠️ Note the two near-identical order providers (`AdminOrderProvider` vs `AdminOrdersProvider`).
> The plural one adds auto-refresh. Confirm which a page uses before editing.

## Services (`admin/lib/services/`)

| File | Class | Responsibility |
|------|-------|----------------|
| `supabase_service.dart` | `SupabaseService` | Same as user app: init + `client` + table-name constants + `bucketMenuImages`. |
| `shared_orders_service.dart` | `SharedOrdersService` | Local mirror of all orders (key `shared_all_orders`) — **mirror of the user app's copy**; sales/count helpers. |
| `guest_customer_service.dart` | `AdminGuestCustomerService` | Reads local guest customers (key `shared_guest_customers`); totals + CSV/JSON export. |

## Models
Shared with user app — see [05_DATA_MODELS.md](05_DATA_MODELS.md). Files: `models/menu_item.dart`, `models/order.dart`.

## Theme (`admin/lib/theme/app_theme.dart`)
`AppTheme.theme` (Material) + `AppColors` tokens (blue primary, success/error, greys).
