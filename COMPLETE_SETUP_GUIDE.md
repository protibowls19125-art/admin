# Complete Setup Guide: Order Management with WhatsApp & Thermal Printer

## 📋 Overview

This guide covers the complete setup for:
1. **WhatsApp Business API** - Send real-time order notifications to admin
2. **Thermal Printer Integration** - Print bills immediately upon order creation
3. **Order Management** - 2-hour order retention for guest customers
4. **Supabase Edge Functions** - Backend services for notifications and printing

---

## 🔑 Step 1: WhatsApp Business Setup

### 1.1 Create Meta Business Account
1. Go to [Meta for Developers](https://developers.facebook.com/)
2. Click **My Apps** → **Create App**
3. Choose **Business** as app type
4. Fill in app details:
   - App Name: "M·PROTI Dining"
   - App Contact Email: your-email@domain.com
   - App Purpose: Business messaging

### 1.2 Set Up WhatsApp Product
1. In your app dashboard, click **Add Product**
2. Find **WhatsApp** and click **Set Up**
3. Choose **WhatsApp Business Account** or **Create New Account**
4. Verify your phone number:
   - You'll receive a code via SMS
   - Enter the 6-digit code to verify

### 1.3 Get Access Token
1. Go to **Settings** → **User Roles**
2. Add yourself as admin
3. Generate a **System User Access Token**:
   - Go to **Settings** → **System Users**
   - Create new system user: "M-PROTI-API"
   - Assign admin role
   - Generate access token (valid for 60 days)
4. **Save this token** - you'll need it

### 1.4 Create Message Template
1. Go to **WhatsApp Manager** → **Message Templates**
2. Create new template:
   - **Name**: `order_notification`
   - **Category**: `ORDER_UPDATE`
   - **Language**: English
   - **Content**:
   ```
   🍽️ NEW ORDER RECEIVED

   Order ID: {{1}}
   Customer: {{2}}
   Phone: {{3}}
   Order Type: {{4}}

   📦 ITEMS:
   {{5}}

   💰 Total: {{6}}
   ⏰ Time: {{7}}
   ```
3. Submit for approval (usually 5-15 minutes)
4. Once approved, copy the **Template Name**

### 1.5 Get Phone Number ID
1. In WhatsApp settings, go to **Phone Numbers**
2. You'll see your business phone number with an ID
3. **Save this Phone Number ID**

---

## 🖨️ Step 2: Thermal Printer Setup

### 2.1 Printer Hardware Requirements
- **Supported Models**: Zebra ZPL, Epson TM Series, Star Micronics
- **Connection**: Ethernet (TCP/IP on port 9100)
- **Thermal Paper**: 80mm width

### 2.2 Network Configuration
1. **Connect printer to local network**:
   - Use printer's setup menu or web interface
   - Set static IP: `192.168.1.100` (or your network range)
   - Note the IP address

2. **Verify connection**:
   ```bash
   # From restaurant computer
   ping 192.168.1.100
   ```

3. **Test print command**:
   ```bash
   # Send test ESC/POS command to printer
   echo -e "\x1B\x40\x1B\x61\x01TEST PRINT\x1D\x56\x42\x00" | nc 192.168.1.100 9100
   ```

### 2.3 Printer Configuration in App
The printer is configured in `MIGRATION_APP_CONFIG.sql` with:
```json
{
  "printer_ip": "192.168.1.100",
  "printer_port": 9100,
  "printer_model": "Zebra ZPL",
  "paper_width_mm": 80,
  "auto_cut": true
}
```

**Update** `printer_ip` with your actual printer's IP address.

---

## 🚀 Step 3: Supabase Configuration

### 3.1 Run Migrations
1. Open **Supabase Dashboard** → **SQL Editor**
2. Create new query
3. Copy and run `MIGRATION_APP_CONFIG.sql`:
   ```sql
   -- Create app_config table
   CREATE TABLE IF NOT EXISTS app_config (
     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     ...
   );
   ```

### 3.2 Update Configuration Values
1. In Supabase, go to **app_config** table
2. Update `whatsapp_credentials`:
   - `access_token`: Your Meta access token from Step 1.3
   - `phone_number_id`: From Step 1.5
   - `admin_phone_number`: Restaurant admin's WhatsApp number (+91XXXXXXXXXX)
   - `business_account_id`: From Meta Business Account

3. Update `thermal_printer_config`:
   - `printer_ip`: Your printer's IP address
   - `printer_port`: 9100 (default)

### 3.3 Deploy Edge Functions
1. In your Flutter project root, ensure `/supabase/functions` exists
2. Create function files:
   - `supabase/functions/send-whatsapp-notification/index.ts`
   - `supabase/functions/print-to-thermal-printer/index.ts`

3. Deploy using Supabase CLI:
   ```bash
   supabase functions deploy send-whatsapp-notification --project-id YOUR_PROJECT_ID
   supabase functions deploy print-to-thermal-printer --project-id YOUR_PROJECT_ID
   ```

---

## 📱 Step 4: Order Flow Integration

### 4.1 Order Creation Flow
```
User Places Order
    ↓
1. Guest customer record created (with 2-hour expiration)
    ↓
2. Order record created (status: pending)
    ↓
3. Order items added to database
    ↓
4. Edge Function: Send WhatsApp notification to admin
    ↓
5. Edge Function: Print bill to thermal printer
    ↓
6. User sees confirmation page with status messages
```

### 4.2 What Happens in Background

**WhatsApp Notification:**
- Message sent to admin's WhatsApp
- Contains: Order ID, Customer name, Phone, Items, Total, Time
- Delivered in real-time (< 1 second)

**Thermal Printer:**
- Bill formatted as ESC/POS commands
- Sent to printer via TCP/IP
- Paper cut automatically (if configured)
- If printer offline, job is queued for manual processing

**Order Retention:**
- Guest customers expire after 2 hours
- Expired orders can be manually archived
- Completed orders are kept indefinitely

---

## ✅ Step 5: Testing the Complete Flow

### 5.1 Test WhatsApp Integration
1. Place a test order in the user app
2. Check the restaurant admin's WhatsApp
3. You should receive an order notification within 5 seconds

**Expected message:**
```
🍽️ NEW ORDER RECEIVED

Order ID: #ABC12345
Customer: John Doe
Phone: +91XXXXXXXXXX
Order Type: DINE-IN

📦 ITEMS:
• Quinoa Salad: x1 @ ₹250
• Protein Smoothie: x1 @ ₹150

💰 Total: ₹400
⏰ Time: 2026-05-30 14:30:45
```

### 5.2 Test Thermal Printer
1. Place a test order
2. Check if printer prints bill
3. Verify bill format is correct
4. If offline, check Supabase logs for queued jobs

### 5.3 Test Order Retention
1. Place an order
2. Wait 2 hours (or manually update `expires_at`)
3. Check if guest customer record is still accessible
4. (Optional) Set up cron job to auto-delete expired records

---

## 🛠️ Step 6: Troubleshooting

### WhatsApp Not Sending
1. **Check credentials** in Supabase `app_config` table
2. **Verify phone number** is correct format: +91XXXXXXXXXX
3. **Check message template** is approved in Meta
4. **Review Supabase logs**: Functions → send-whatsapp-notification → Logs

### Printer Not Printing
1. **Ping printer**: `ping 192.168.1.100`
2. **Test connection**: `nc -zv 192.168.1.100 9100`
3. **Check printer IP** in app_config matches actual IP
4. **Check paper** is loaded in printer
5. **Review Supabase logs**: Functions → print-to-thermal-printer → Logs

### Orders Not Appearing in Admin
1. **Check Supabase connection** in app
2. **Verify guest_customers table** has new records
3. **Check RLS policies** on orders and guest_customers tables
4. **Review Flutter app logs** for database errors

---

## 📊 Database Schema

### app_config Table
```sql
id          | UUID (PK)
key         | VARCHAR (unique) - "whatsapp_credentials" or "thermal_printer_config"
value       | JSONB
description | TEXT
updated_at  | TIMESTAMP
created_at  | TIMESTAMP
```

### guest_customers Table (Updated)
```sql
id              | UUID (PK)
name            | TEXT
phone           | TEXT (unique)
order_type      | VARCHAR - "dine_in" or "takeaway"
is_info_complete| BOOLEAN
expires_at      | TIMESTAMP - 2 hours from creation
created_at      | TIMESTAMP
```

### orders Table (No Changes)
```sql
id              | UUID (PK)
customer_id     | UUID (FK → guest_customers)
total_price     | DECIMAL
payment_method  | VARCHAR - "cod", "upi", "card"
status          | VARCHAR - "pending", "preparing", "confirmed"
created_at      | TIMESTAMP
```

---

## 🔐 Security Considerations

1. **Access Token**: Stored in Supabase app_config (not in app code)
2. **Phone Numbers**: Guest customers auto-delete after 2 hours
3. **Edge Functions**: Only call from trusted backend
4. **RLS Policies**: Restrict admin config access

---

## 📝 Configuration Checklist

- [ ] Meta Business Account created
- [ ] WhatsApp Business product set up
- [ ] Phone number verified with Meta
- [ ] Message template created and approved
- [ ] Access token generated and saved
- [ ] Phone Number ID obtained
- [ ] Thermal printer network connected
- [ ] Printer IP address noted
- [ ] Supabase migrations run
- [ ] app_config table populated with credentials
- [ ] Edge Functions deployed
- [ ] Test order placed and WhatsApp received
- [ ] Test order printed to thermal printer
- [ ] Admin dashboard shows new order

---

## 🚀 Deployment Steps

1. **Update Supabase:**
   ```bash
   # Run MIGRATION_APP_CONFIG.sql in Supabase SQL Editor
   ```

2. **Deploy Edge Functions:**
   ```bash
   supabase functions deploy send-whatsapp-notification
   supabase functions deploy print-to-thermal-printer
   ```

3. **Update Flutter App:**
   - Pull latest `notification_service.dart`
   - Pull latest `order_provider.dart`
   - Run `flutter pub get`

4. **Test End-to-End:**
   - Place test order
   - Verify WhatsApp notification
   - Verify thermal printer bill
   - Check admin dashboard updates

---

## 📞 Support

For issues, check:
1. **Supabase Logs** → Functions → See error messages
2. **Flutter Console** → See app-side errors
3. **WhatsApp Manager** → Message templates and delivery logs
4. **Printer** → Check paper, toner, network connection

---

**Last Updated:** 2026-05-30
**Status:** Production Ready ✅
