# Implementation Checklist — Customer Info System

## Step 1: Database Setup
- [ ] Open Supabase SQL Editor
- [ ] Copy entire contents of `SUPABASE_SETUP.sql`
- [ ] Paste into Supabase SQL Editor
- [ ] Run the script
- [ ] Verify these tables created:
  - [ ] `profiles`
  - [ ] `menu_items`
  - [ ] `orders`
  - [ ] `guest_customers` (NEW)
  - [ ] `analytics_events`
  - [ ] `order_items`

## Step 2: User App Configuration

### Update Environment
- [ ] Copy `.env.example` to `.env` in `/user` folder
- [ ] Add `SUPABASE_URL`:
  ```
  SUPABASE_URL=https://your-project.supabase.co
  ```
- [ ] Add `SUPABASE_ANON_KEY`:
  ```
  SUPABASE_ANON_KEY=your_anon_key_from_supabase
  ```

### Install Dependencies
- [ ] Open terminal in `/user` folder
- [ ] Run: `flutter pub get`
- [ ] Verify no errors

### Test User App
- [ ] Run: `flutter run`
- [ ] Should see **Customer Info Form** page first
- [ ] Fill in form:
  - Name: "Test User"
  - Phone: "1234567890"
  - Gender: Select from dropdown
  - Preference: Select from dropdown
- [ ] Click "Continue to Menu"
- [ ] Should redirect to **Home/Menu page**
- [ ] Verify can browse menu (if menu data exists)

## Step 3: Admin App Configuration

### Update Environment
- [ ] Copy `.env.example` to `.env` in `/admin` folder
- [ ] Add `SUPABASE_URL`:
  ```
  SUPABASE_URL=https://your-project.supabase.co
  ```
- [ ] Add `SUPABASE_ANON_KEY`:
  ```
  SUPABASE_ANON_KEY=your_anon_key_from_supabase
  ```
- [ ] Add `CLERK_PUBLISHABLE_KEY`:
  ```
  CLERK_PUBLISHABLE_KEY=pk_test_dG9sZXJhbnQtYWxwYWNhLTQ4LmNsZXJrLmFjY291bnRzLmRldiQ
  ```

### Install Dependencies
- [ ] Open terminal in `/admin` folder
- [ ] Run: `flutter pub get`
- [ ] Verify no errors

### Test Admin App
- [ ] Run: `flutter run`
- [ ] Login with Google OAuth (Clerk)
- [ ] Should see **Dashboard** with 4 cards:
  - [ ] Orders
  - [ ] Menu
  - [ ] Customers (NEW)
  - [ ] Analytics
- [ ] Click "Customers" card
- [ ] Should see **Customers Page**
- [ ] Table should show customer(s) submitted from user app:
  - [ ] Name
  - [ ] Phone
  - [ ] Gender
  - [ ] Preference (color-coded)
  - [ ] Created time
  - [ ] Expires In (countdown timer)
  - [ ] Delete button

## Step 4: End-to-End Testing

### Test Flow 1: User Submission
- [ ] Run user app on device/emulator
- [ ] Fill customer info form
- [ ] Submit
- [ ] Verify redirects to menu

### Test Flow 2: Admin Visibility
- [ ] Run admin app
- [ ] Login
- [ ] Navigate to Customers page
- [ ] Verify new customer appears in table
- [ ] Check expiry timer (should show ~24h remaining)
- [ ] Wait a moment and refresh (click refresh button)
- [ ] Verify timer counts down

### Test Flow 3: Delete
- [ ] Click delete button on a customer record
- [ ] Confirm deletion in dialog
- [ ] Verify customer removed from table

## Step 5: Verification Checklist

### User App
- [ ] ✅ No Clerk login required
- [ ] ✅ Customer info form appears on startup
- [ ] ✅ Phone number validation works (10 digits)
- [ ] ✅ Form submission saves to Supabase
- [ ] ✅ Redirect to menu after form submission works
- [ ] ✅ Clerk dependency removed from pubspec.yaml

### Admin App
- [ ] ✅ Dashboard shows 4 management cards
- [ ] ✅ Customers page accessible from dashboard
- [ ] ✅ Customer table displays all records
- [ ] ✅ Expiry timer shows correct countdown
- [ ] ✅ Expired records shown with red background
- [ ] ✅ Delete button removes records
- [ ] ✅ Refresh button reloads data

### Database
- [ ] ✅ `guest_customers` table exists
- [ ] ✅ RLS policies allow public read/write
- [ ] ✅ `expires_at` field auto-set to 24 hours
- [ ] ✅ Records can be manually deleted via admin UI

## Troubleshooting

### "Failed to insert into guest_customers"
- [ ] Check Supabase RLS policies
- [ ] Verify table exists in database
- [ ] Check `.env` variables in user app

### "Customers page shows no data"
- [ ] Verify customer info was submitted from user app
- [ ] Check Supabase admin dashboard to confirm records exist
- [ ] Check admin app `.env` variables

### "Timer not updating"
- [ ] Timer is calculated on-demand, refresh page to see latest
- [ ] Use refresh button on customers page

### "Phone validation fails"
- [ ] Must be exactly 10 digits
- [ ] No spaces, dashes, or other characters allowed

## After Implementation

- [ ] Review `CHANGES_SUMMARY.md` for overview of all changes
- [ ] Backup your `.env` files (don't commit to git)
- [ ] Test with real users
- [ ] Monitor customer submissions in admin panel
- [ ] Verify 24-hour auto-deletion works

---

**Questions?** Check the following files:
- `CHANGES_SUMMARY.md` — What changed and why
- `SUPABASE_SETUP.sql` — Database schema
- `SETUP_GUIDE.md` — Original setup documentation
