# 05 · Data Models

Dart models live in `<app>/lib/models/`. **`user/` and `admin/` each keep their own copy** of these
files — they're near-identical, so **change both** when editing a shared shape.

## `MenuItem` (`models/menu_item.dart`)

Represents a menu/catalog item. Has `fromJson`/`toJson` matching the `menu_items` table.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `String` | UUID |
| `name`, `description` | `String` | |
| `price` | `double` | |
| `category` | `String` | drives filter chips |
| `tags` | `List<String>` | |
| `kcal` | `int` | |
| `available` | `bool` | manual toggle |
| `imageUrl` | `String?` | from `menu-images` bucket |
| `badge` | `String?` | e.g. "New", "Popular" |
| `featured` | `bool` | homepage hero (added via migration) |
| `createdAt` | `DateTime?` | |
| **Nutrition:** `servingSize` `String`, `protein` `carbs` `fat` `fiber` `double` | | |
| **Availability:** `dailyLimit` `int?`, `ordersToday` `int`, `lastResetDate` `String` | | |

**Derived:** `isSoldOut` → `true` when `!available` **or** (`dailyLimit > 0 && ordersToday >= dailyLimit`).
JSON keys are snake_case (`image_url`, `serving_size`, `daily_limit`, `orders_today`, `last_reset_date`).

## `Order` (`models/order.dart`)

A simple/legacy order shape with `fromJson`/`toJson`.

| Field | Type | JSON key |
|-------|------|----------|
| `id` | `String` | `id` |
| `userId` | `String` | `user_id` |
| `status` | `String` | `status` — `pending`/`preparing`/`completed`/`cancelled` |
| `total` | `double` | `total` |
| `items` | `List<dynamic>` | `items` |
| `tableNumber` | `String?` | `table_number` |
| `createdAt` | `DateTime` | `created_at` |
| `completedAt` | `DateTime?` | `completed_at` |

> ⚠️ **The live order pipeline does NOT use this `Order` class.** `OrderProvider.createOrder`
> works with raw `Map<String, dynamic>` and a richer set of columns (`order_number`, `order_type`,
> `customer_name`, `customer_phone`, `customer_info`, `payment_method`, `total_price`,
> `delivery_address`). Treat `Order` as a typed helper / partial view, not the canonical schema.
> The canonical order shape is the DB row — see [04_BACKEND.md](04_BACKEND.md).

## Other typed shapes (not in `models/`)

- `CartItem` — in `user/lib/providers/cart_provider.dart` (wraps a `MenuItem` + `quantity`, `subtotal`).
- `GuestCustomer` — in `admin/lib/providers/customer_info_provider.dart`.
- `OrderAPIRequest` / `OrderItemData` — in `user/lib/services/order_api_service.dart` (stub API).
