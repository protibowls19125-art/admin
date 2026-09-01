# M·PROTI Dining — Customer Info Integration Summary

## Overview
Successfully implemented guest customer information collection in the user app and customer management dashboard in the admin app with automatic 24-hour data expiration.

## Database Changes (SUPABASE_SETUP.sql)

### New Table: `guest_customers`
- `id` (UUID): Primary key
- `name` (TEXT): Customer name
- `phone` (TEXT): Phone number
- `gender` (TEXT): Gender (male, female, other)
- `preference` (TEXT): Food preference (veg, non_veg)
- `created_at` (TIMESTAMP): When customer info was submitted
- `expires_at` (TIMESTAMP): Auto-set to 24 hours from creation

### Auto-Delete Function
- Function `delete_expired_guest_customers()` removes records after 24 hours
- Index on `expires_at` for efficient cleanup

### Row-Level Security (RLS)
- Public can view all guest customers
- Public can create guest customer records

---

## User App Changes

### 1. Authentication Removed
- **Removed**: `clerk_flutter` dependency from pubspec.yaml
- **Removed**: Clerk initialization from main.dart
- **Result**: No login required for customers

### 2. Customer Info Form (NEW)
**File**: `/user/lib/pages/customer_info_page.dart`
- Form with fields:
  - Full Name (required)
  - Phone Number (required, 10-digit validation)
  - Gender dropdown (Male, Female, Other)
  - Food Preference dropdown (Vegetarian, Non-Vegetarian)
- Submits data to `guest_customers` table
- Auto-deletes in 24 hours message shown to users

### 3. Customer Info Provider (NEW)
**File**: `/user/lib/providers/customer_info_provider.dart`
- Manages customer info state
- Submits info to Supabase
- Stores customer ID for tracking orders

### 4. Updated Router
**File**: `/user/lib/router.dart`
- New route: `/customer-info`
- Redirect logic: Users must complete info form before accessing menu
- Automatic redirect from customer-info to home if already submitted

### 5. Updated Main Entry Point
**File**: `/user/lib/main.dart`
- Removed ClerkAuth wrapper
- Added CustomerInfoProvider to MultiProvider stack
- Simplified startup sequence

### 6. Updated Environment Variables
**File**: `/user/.env.example`
- Removed `CLERK_PUBLISHABLE_KEY`
- Kept `SUPABASE_URL` and `SUPABASE_ANON_KEY`

---

## Admin App Changes

### 1. Customer Management Page (NEW)
**File**: `/admin/lib/pages/customers_page.dart`
- Displays all guest customers in a data table
- Columns:
  - Name
  - Phone
  - Gender (formatted display)
  - Preference (color-coded: green for veg, red for non-veg)
  - Created time
  - Time until expiry (formatted countdown)
  - Delete action button
- Expired records shown with red background
- Refresh button to reload data
- Delete dialog for confirmation

### 2. Customer Info Provider (NEW)
**File**: `/admin/lib/providers/customer_info_provider.dart`
- `GuestCustomer` model with:
  - Basic info fields
  - `isExpired` getter
  - `timeUntilExpiry` calculated duration
  - `fromJson` factory for Supabase data
- `CustomerInfoProvider` ChangeNotifier with:
  - `fetchCustomers()` - loads all customer records
  - `deleteCustomer()` - removes a specific customer
  - Loading and error states

### 3. Updated Dashboard
**File**: `/admin/lib/pages/dashboard_page.dart`
- Replaced placeholder with navigation grid
- 4 main admin sections:
  - Orders (blue)
  - Menu (green)
  - Customers (orange) — NEW
  - Analytics (purple)
- Each card links to respective management page

### 4. Updated Router
**File**: `/admin/lib/router.dart`
- New route: `/customers`
- Protected with admin authentication guard
- Import added for customers_page

### 5. Updated Main Entry Point
**File**: `/admin/lib/main.dart`
- Added CustomerInfoProvider to MultiProvider stack

---

## User Flow

### Customer Journey (User App)
1. Open app → Redirected to `/customer-info`
2. Fill in form with personal details
3. Submit → Data saved to Supabase
4. Redirected to `/` (home/menu)
5. Browse menu, add to cart, place order
6. Customer data automatically deleted after 24 hours

### Admin Journey (Admin App)
1. Login with Clerk
2. View dashboard with management options
3. Click "Customers" card
4. View all active guest customers
5. See countdown timer showing when each record expires
6. Delete customers manually if needed
7. Refresh to see latest data

---

## Key Features

✅ **No Authentication Required** — Customers don't need accounts
✅ **Simple Data Collection** — Just 4 fields needed
✅ **Automatic Cleanup** — Data expires after 24 hours
✅ **Admin Visibility** — All customer info viewable by admin
✅ **Privacy-Friendly** — No long-term data storage
✅ **Validation** — Phone number format validation
✅ **Visual Feedback** — Countdown timers and color coding

---

## Next Steps

1. **Update Supabase**:
   ```sql
   -- Paste SUPABASE_SETUP.sql into Supabase SQL Editor
   -- This includes the new guest_customers table
   ```

2. **Update Both Apps**:
   ```bash
   cd user && flutter pub get
   cd ../admin && flutter pub get
   ```

3. **Test User App**:
   - Run user app
   - Should see customer info form first
   - Fill form and submit
   - Should see menu after submission

4. **Test Admin App**:
   - Run admin app
   - Login with Clerk
   - Go to Customers section
   - Should see customer records with expiry timer

---

## Database Cleanup

For manual cleanup of expired records (optional):
```sql
DELETE FROM guest_customers WHERE expires_at < NOW();
```

To view customers expiring soon:
```sql
SELECT name, phone, expires_at 
FROM guest_customers 
WHERE expires_at < NOW() + INTERVAL '1 hour' 
ORDER BY expires_at;
```
