# Complete Customer Ordering Flow

## 🎯 End-to-End Customer Journey

### **Stage 1: App Entry → Menu**
```
User Opens App
    ↓
Home Page Loads
    ↓
Browse Menu Items
├─ Horizontal Category Filter (Snacks, Salads, Main, etc.)
├─ 1-Column Product Grid with Images
├─ VEG Badge, Price, Description
└─ Product Details with Customizations Available
```

**Features:**
- Real-time category filtering
- Product image with VEG badge
- Dynamic price display
- View nutritional information
- See standard ingredients

---

### **Stage 2: Add to Cart (With Loop Back)**
```
Customer Clicks "ADD TO CART"
    ↓
Product Added to Cart (with customizations)
    ↓
Snackbar Confirmation "Added to Cart"
    ↓
Customer Can:
├─ Continue Shopping (back to menu)
├─ Add More Items (loop back to menu)
├─ View Cart (proceed to checkout)
└─ Browse More Items
```

**Features:**
- Add multiple quantities
- Select customizations (Extra Avocado +₹20, Quinoa Base +₹50, etc.)
- Dynamic price calculation
- Quantity selector with +/- buttons
- Continue shopping without losing cart

---

### **Stage 3: Cart Review → Checkout**
```
Customer Clicks Cart Icon or "View Cart"
    ↓
Cart Summary Page Shows:
├─ All Items Listed
│  ├─ Product Name
│  ├─ Quantity (x)
│  ├─ Individual Price
│  └─ Subtotal per Item
├─ Total Price (Red bordered box)
├─ "CONTINUE SHOPPING" button
└─ "PROCEED TO PAY" button
```

**Cart Items Display:**
- Item name (UPPERCASE)
- Quantity × unit price = subtotal
- Visual separation with dividers
- Bold black borders (Bauhaus style)

---

### **Stage 4: Customer Details Form**
When user clicks "PROCEED TO PAY", modal dialog opens:

```
CUSTOMER INFORMATION Modal
    ↓
1. NAME FIELD
   └─ Text input with sharp corners
   
2. PHONE NUMBER FIELD
   └─ Text input for contact
   
3. DELIVERY ADDRESS FIELD
   └─ Multi-line textarea (3 lines)
   └─ Complete address with pin code
   
4. ORDER TYPE (Radio Buttons)
   ├─ 🏪 DINE-IN (eat at restaurant)
   ├─ 🛍️ TAKEAWAY (pickup from restaurant)
   └─ 🚚 DELIVERY (home delivery)
   
5. PAYMENT METHOD (Radio Buttons)
   ├─ 💵 CASH ON DELIVERY (COD)
   │  └─ Pay when order arrives
   ├─ 📱 UPI (GooglePay, PhonePe, Paytm)
   │  └─ Instant digital payment
   ├─ 💳 CREDIT/DEBIT CARD
   │  └─ Visa, Mastercard, RuPay
   └─ 👛 DIGITAL WALLET (Apple Pay, Google Wallet)
      └─ Stored payment method
```

**Validation:**
- Name: Required (not empty)
- Phone: Required (10 digits)
- Address: Required (not empty)
- Order Type: Must select one
- Payment Method: Must select one

---

### **Stage 5: Order Confirmation**
```
All validations pass
    ↓
Order is Created in Database:
├─ Guest Customer Record
│  ├─ name
│  ├─ phone
│  ├─ address
│  ├─ order_type
│  ├─ is_info_complete = true
│  └─ created_at timestamp
│
├─ Order Record
│  ├─ customer_id (FK)
│  ├─ total_price (with customizations)
│  ├─ payment_method
│  ├─ status = 'pending'
│  └─ created_at timestamp
│
└─ Order Items Records
   ├─ order_id (FK)
   ├─ menu_item_id (FK)
   ├─ quantity
   └─ price (including customizations)
    ↓
Redirect to Confirmation Page
    ↓
Display:
├─ ✅ Order Confirmed
├─ Order Number
├─ Order Summary
├─ Total Amount
└─ "View Your Orders" button
```

---

### **Stage 6: Live Order Tracking (User Side)**
```
User Goes to ORDERS Tab
    ↓
See All Their Orders
├─ Order ID (shortened)
├─ Customer Name
├─ Items List
├─ Total Price
├─ Payment Method
├─ Special Instructions (if any)
└─ Live Status Badge
   ├─ 🔴 PENDING (Just received)
   ├─ 🔵 PREPARING (Being made)
   └─ 🟢 CONFIRMED (Ready for pickup/delivery)
```

**Auto-Updates:**
- Status updates in real-time
- Refresh every 2-3 seconds
- User sees kitchen progress

---

### **Stage 7: Admin Order Management**
```
Admin Dashboard Shows:
├─ Today's Sales (₹) - auto-updating
├─ Pending Orders count
├─ Preparing Orders count
├─ Completed Orders count
└─ Updated: Just now (timestamp)

Admin Can:
├─ View ORDERS Page
│  └─ All orders with status dropdown
│  └─ Change status: pending → preparing → confirmed
├─ Kitchen Display System (KDS)
│  └─ Real-time order queue with prep timers
│  └─ Click START or READY buttons
└─ ANALYTICS Page
   └─ Pie chart of order statuses
   └─ Recent orders list
   └─ Total sales (including customization costs)
```

---

## 📊 Database Schema Updates

### **guest_customers Table**
```sql
CREATE TABLE guest_customers (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT,
  gender VARCHAR(50),
  preference VARCHAR(50),
  address TEXT,           -- NEW: Delivery address
  order_type VARCHAR(50), -- NEW: dine_in, takeaway, delivery
  is_info_complete BOOLEAN DEFAULT false,
  created_at TIMESTAMP,
  expires_at TIMESTAMP,
  UNIQUE(phone)
);
```

### **orders Table**
```sql
CREATE TABLE orders (
  id UUID PRIMARY KEY,
  customer_id UUID NOT NULL REFERENCES guest_customers(id),
  total_price DECIMAL(10,2),
  payment_method VARCHAR(50), -- cod, upi, card, wallet
  special_instructions TEXT,
  status VARCHAR(50) DEFAULT 'pending', -- pending, preparing, confirmed
  created_at TIMESTAMP,
  INDEX(customer_id),
  INDEX(status),
  INDEX(created_at)
);
```

---

## 🔄 Payment Methods Supported

| Method | Code | User Journey |
|--------|------|--------------|
| Cash on Delivery | `cod` | Order placed → Pay when delivered |
| UPI | `upi` | GooglePay, PhonePe, Paytm, etc. |
| Credit/Debit Card | `card` | Visa, Mastercard, RuPay |
| Digital Wallet | `wallet` | Apple Pay, Google Wallet, etc. |

---

## 🎨 UI/UX Flow - Bauhaus Design

### **Color Coding by Status:**
- 🔴 **Pending** (Red #E63946) - Order just received
- 🔵 **Preparing** (Blue) - Kitchen is making the order
- 🟢 **Confirmed** (Green) - Order ready for pickup/delivery

### **Typography:**
- All text: Chivo font family (geometric, bold)
- Headers: W800 (bold)
- Labels: W700 (semibold)
- Body: W500 (regular)

### **Layout:**
- All corners: 0° radius (sharp edges)
- Spacing: 8pt, 16pt, 24pt, 32pt grid
- Borders: 2pt solid black
- No shadows or elevation

---

## ✅ Complete Testing Checklist

### **User App:**
- [ ] Browse menu and filter by category
- [ ] Add item to cart with customizations
- [ ] Increase quantity and verify price updates
- [ ] Add multiple items and continue shopping
- [ ] View cart with all items
- [ ] Proceed to pay and fill all details
- [ ] Select order type (dine-in, takeaway, delivery)
- [ ] Select payment method
- [ ] Order is created and receives confirmation
- [ ] Can view order in ORDERS tab
- [ ] Order status updates in real-time

### **Admin App:**
- [ ] Dashboard shows real-time stats
- [ ] Can view orders with status dropdown
- [ ] Can change order status
- [ ] Kitchen Display System shows active orders
- [ ] KDS orders update with timer
- [ ] Analytics dashboard shows live data
- [ ] Sales calculation includes customization costs

---

## 🚀 Deployment Steps

1. **Update Supabase Schema:**
   ```bash
   # Run MIGRATION_UPDATE_CUSTOMER_FLOW.sql in Supabase SQL Editor
   ```

2. **Test User Flow:**
   - Add product with customizations
   - Place order with complete details
   - Verify in admin dashboard

3. **Go Live:**
   - User and Admin apps both deployed
   - Supabase connected and tested
   - Payment gateway ready (for future)

---

## 📱 Device Compatibility

- ✅ Web (Chrome, Edge, Safari)
- ✅ Mobile Web (iOS Safari, Android Chrome)
- ✅ Responsive design
- ✅ Touch-friendly buttons (44pt minimum)

---

**Last Updated:** 2026-05-30
**Status:** Complete & Ready for Testing 🎉
