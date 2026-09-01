# 🔍 Debugging Guide - Order Sync Issues

## 📋 How to Debug the Order System

### Step 1: Open Browser Console
When you run the apps with `flutter run -d edge`, both apps print debug messages to the console.

**Open DevTools Console:**
1. Press **F12** (or right-click → Inspect)
2. Go to **Console** tab
3. Keep it open while testing

---

## 🧪 Test Sequence

### Customer App (Tab 1)
```
1. Add item to cart
2. Click "PROCEED TO PAY"
3. Fill: Name, Phone, Order Type
4. Click "PLACE ORDER"

WATCH CONSOLE FOR:
✅ "Generated Order ID: ORD-1234567890-5000-1"
✅ "✅ Order saved to shared storage: ORD-..."
✅ "DEBUG: Current orders count: 0"
✅ "DEBUG: New orders count: 1"
✅ "✅ Retrieved 1 orders from shared storage"
```

### Admin App (Tab 2)
```
1. Watch dashboard (should auto-refresh every 3 sec)
2. Or click ORDERS tab

WATCH CONSOLE FOR:
✅ "✅ Retrieved X orders from shared storage"
✅ "DEBUG: Orders loaded: [ORD-1234567890-5000-1]"

EXPECTED:
✅ PENDING ORDERS count increases
✅ TODAY'S SALES shows ₹XXX
✅ Orders tab shows the order
```

---

## 🐛 Common Issues & Solutions

### Issue 1: Order ID Still Same
**Symptom:** Both orders show `ORD-1780`

**Debug Check:**
```
Console should show:
"Generated Order ID: ORD-[timestamp]-[microsec]-1"
"Generated Order ID: ORD-[timestamp]-[microsec]-2"
```

**If not:**
- Reload browser (Ctrl+Shift+R)
- Ensure unique ID numbers increment
- Check console has ✅ "Generated" message

---

### Issue 2: Admin Shows 0 Orders
**Symptom:** Dashboard shows 0 pending orders

**Debug Check:**
```
Admin console should show:
"✅ Retrieved 1 orders from shared storage"
"DEBUG: Orders loaded: [ORD-...]"
```

**If it shows 0:**
- Customer console should show "✅ Order saved"
- If yes → data not syncing between tabs
- If no → customer app didn't save order

**Fix:**
1. Reload admin app (F5)
2. Wait 3 seconds (auto-refresh)
3. Check console again

---

### Issue 3: Status Not Updating
**Symptom:** Change status in admin, but customer doesn't see it

**Debug Check:**
```
Admin console should show:
"Order status updated: ORD-... → PREPARING"
```

**If not:**
- Click the dropdown to change status
- Check admin console for error message

---

## 📊 Complete Debug Output Example

### Customer App Console (When Placing Order)
```
Generated Order ID: ORD-1717154523982-456-1
DEBUG: Current orders count: 0
✅ Order saved to shared storage: ORD-1717154523982-456-1
DEBUG: New orders count: 1
DEBUG: Order data: {"id":"ORD-...","items":[...],...}
Order created successfully: ORD-1717154523982-456-1
✅ Retrieved 1 orders from shared storage
DEBUG: Orders loaded: [ORD-1717154523982-456-1]
```

### Admin App Console (Auto-refresh)
```
✅ Retrieved 1 orders from shared storage
DEBUG: Orders loaded: [ORD-1717154523982-456-1]
```

---

## 🔧 Manual Testing Steps

### Test 1: Place Single Order
1. Customer: Add item → Place order
2. **Check Console** for "✅ Order saved"
3. Admin: Click Orders
4. **Expected**: See 1 order listed

### Test 2: Place Multiple Orders Quickly
1. Customer: Place order #1
2. Customer: Place order #2 (different ID!)
3. **Check Console** for different order IDs
4. Admin: See 2 orders in PENDING

### Test 3: Update Status
1. Admin: Orders → Change status to "PREPARING"
2. **Check Console** for "Order status updated"
3. Admin: Refresh page
4. **Expected**: Status changed to PREPARING

---

## 🎯 What Should Happen

```
CUSTOMER APP                    ADMIN APP
═══════════════════════════════════════════
Places Order 1
    ↓
Console: ✅ Order saved
                                Dashboard auto-refreshes
                                    ↓
                                Console: ✅ Retrieved 1 orders
                                    ↓
                                PENDING ORDERS: 1 ✅
                                TODAY'S SALES: ₹100 ✅

Customer places Order 2
    ↓
Console: ✅ Order saved (different ID)
                                Dashboard auto-refreshes
                                    ↓
                                Console: ✅ Retrieved 2 orders
                                    ↓
                                PENDING ORDERS: 2 ✅
```

---

## 🐛 If Nothing Works

### Reset Everything
```bash
# Terminal 1 - Kill customer app
Press Ctrl+C

# Terminal 2 - Kill admin app
Press Ctrl+C

# Clear browser storage
Press F12 → Application → Local Storage → Clear All

# Restart both apps
flutter run -d edge (in both directories)
```

### Check These Things
1. ✅ Both apps show in browser tabs
2. ✅ Console shows debug messages (not blank)
3. ✅ Order ID changes each time (not same ID)
4. ✅ Order count increases in console
5. ✅ Dashboard auto-refreshes every 3 seconds

---

## 📝 Expected Console Messages

**Customer Placing Order:**
```
Generated Order ID: ORD-XXXX-YYY-1
✅ Order saved to shared storage: ORD-XXXX-YYY-1
DEBUG: New orders count: 1
```

**Admin Fetching Orders:**
```
✅ Retrieved 1 orders from shared storage
DEBUG: Orders loaded: [ORD-XXXX-YYY-1]
```

**Admin Changing Status:**
```
Order status updated: ORD-XXXX-YYY-1 → PREPARING
✅ Retrieved 1 orders from shared storage
```

---

## 🚀 If All Working

```
✅ Order ID is unique
✅ Admin sees order immediately
✅ Order count increases
✅ Status updates work
✅ Console shows all ✅ messages
✅ NO error messages
```

**Then system is working correctly!**

---

## 📞 Still Having Issues?

1. **Check console** for error messages (they start with ❌)
2. **Copy console output** and share it
3. **Check order count** in admin dashboard
4. **Reload admin app** and watch console

---

**Use this guide to verify data is flowing correctly between apps!**
