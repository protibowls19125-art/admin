# 02 · Customer App (`user/`)

**Package:** `mpro_dining_user` — "M·PROTI Dining User". Flutter web app for diners.
**Theme:** `BauhausTheme` (the active "Epicurean Minimalist" look; class still named `BauhausTheme`).
**Entry:** `user/lib/main.dart` → `MPROTIDiningUserApp` → `MaterialApp.router`.

## Routes (`user/lib/router.dart`)

| Path | Page | Notes |
|------|------|-------|
| `/customer-info` | `CustomerInfoPage` | Collect name/phone; redirects to `/` once complete |
| `/` | `HomePage` | Landing + menu (tabbed) |
| `/menu` | `HomePage(initialTab: 1)` | Same page, menu tab preselected |
| `/product/:id?table=` | `ProductDetailPage` | Item detail; optional `table` query param |
| `/order` | `OrderFormPage` | Cart → checkout form |
| `/confirmation?orderId=` | `ConfirmationPage` | Post-order receipt |
| `/orders` | `OrdersPage` | (thin) |
| `/my-orders` | `OrderTrackingPage` | Live status of placed orders |
| `/subscribe` | `SubscriptionPage` | Meal-plan sales page → Razorpay |
| `/subscribe/details` | `SubscriptionOnboardingPage` | Post-payment preferences form |
| `/member` | `MemberPage` | Member login → premium card + meal confirm |

## Pages (`user/lib/pages/`)

| File | Lines | Role |
|------|-------|------|
| `home_page.dart` | 705 | Landing + menu browse. Contains `_HeroCard`. Tabbed (hero/menu). |
| `product_detail_page.dart` | 1080 | Full item page: nutrition, qty, add-to-cart. Largest customer page. |
| `order_form_page.dart` | 769 | Checkout: customer info, order type, payment, delivery address (`_DeliveryAddressSection`). |
| `confirmation_page.dart` | 496 | Order receipt / success screen. |
| `order_tracking_page.dart` | 308 | "My orders" live status tracking. |
| `customer_info_page.dart` | 246 | First-run name/phone capture. |
| `orders_page.dart` | 20 | Thin wrapper. |

## Providers (`user/lib/providers/`) — state via `ChangeNotifier`

| File | Class | Responsibility |
|------|-------|----------------|
| `menu_provider.dart` | `MenuProvider` | Loads menu items, category filter, **search query** (`setSearchQuery`, `filteredItems`), `getItemById`. |
| `cart_provider.dart` | `CartProvider` (+ `CartItem`) | In-memory cart: `addItem`, `removeItem`, `updateQuantity`, `clear`; derived `itemCount`, `total`. |
| `order_provider.dart` | `OrderProvider` | **Core order logic.** `createOrder` (3-layer order-number fallback, dual persistence), `fetchOrders` (re-syncs status from Supabase), `updateOrderStatus`, `cancelOrder`, `clearAllOrders`. See [01_ARCHITECTURE](01_ARCHITECTURE.md). |
| `customer_info_provider.dart` | `CustomerInfoProvider` | Holds current customer; `isInfoComplete` gates the `/customer-info` redirect; `reset`. |
| `subscription_provider.dart` | `SubscriptionProvider` (+ `SubscriptionPlan`, `PromoBanner`, `MealDay`) | Plans/banners fetch, pay→details flow, member auth + meal calendar, `confirm_meal` RPC. Banner carousel widget: `widgets/promo_banner_carousel.dart` (on home page). |

## Services (`user/lib/services/`)

| File | Class | Responsibility |
|------|-------|----------------|
| `supabase_service.dart` | `SupabaseService` | Singleton init of Supabase; exposes `client`, `currentUser`, and table-name constants. URL/anon key from `.env` with hardcoded web fallback. |
| `local_storage_service.dart` | `LocalStorageService` | `shared_preferences` wrapper: customer info, order ids, saved orders, order-id generation. |
| `shared_orders_service.dart` | `SharedOrdersService` | Local mirror of **all** orders (key `shared_all_orders`); sales/count helpers. Mirrored in admin app. |
| `guest_customer_tracking_service.dart` | `GuestCustomerTrackingService` | Tracks guest customers locally (key `shared_guest_customers`); `generateCustomerId`, CSV/JSON export. |
| `notification_service.dart` | `NotificationService` | Singleton for user-facing notifications. |
| `razorpay_service.dart` | `RazorpayService` (+ `RazorpayResult`) | **Online payment.** `payAndVerify` → create-order edge fn → opens Razorpay checkout.js (web JS interop) → verify-payment edge fn. Web-only. See `RAZORPAY_SETUP.md`. |
| `order_api_service.dart` | `UserOrderAPIService` (+ `OrderAPIRequest`, `OrderItemData`) | **Placeholder/stub** external order API (`api.your-business.com`, `YOUR_API_KEY_HERE`) — not wired to real backend. |

## Widgets (`user/lib/widgets/`) — the design system

| File | Widget(s) | Use |
|------|-----------|-----|
| `bauhaus_button.dart` | `BauhausButton`, `BauhausOutlineButton` | Primary / outline buttons |
| `bauhaus_card.dart` | `BauhausCard` | Standard surface container |
| `bauhaus_category_chip.dart` | `BauhausCategoryChip` | Menu category filter chips |
| `bauhaus_divider.dart` | `BauhausDivider` | Styled separators |
| `bauhaus_info_box.dart` | `BauhausInfoBox`, `BauhausBadge` | Callout boxes & badges |
| `floating_cart_bar.dart` | `FloatingCartBar` | Sticky bottom cart summary → `/order` |

## Theme (`user/lib/theme/`)

- **`bauhaus_theme.dart`** (316 lines) — the **active** theme. `BauhausTheme.theme`, color tokens
  (`primaryBlack`, `accentRed`, `background`…), radii (`radiusSm/Md/Lg/Pill`), shadows
  (`cardShadow`, `floatingShadow`), and text helpers (`heading()`, `body()`, `_textTheme`).
- `app_theme.dart` (40 lines) — older blue `AppTheme`/`AppColors`. Superseded by Bauhaus; check
  references before editing.

## Models
Shared shape with admin — see [05_DATA_MODELS.md](05_DATA_MODELS.md). Files: `models/menu_item.dart`, `models/order.dart`.
