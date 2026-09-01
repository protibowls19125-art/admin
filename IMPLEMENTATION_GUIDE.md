# Quick Implementation Guide

## 1. Test the Current Implementation

### Running the App
```bash
cd stitch_flutter_contactless_dining_screen/mpro_dining_app
flutter pub get
flutter run
```

### Features to Test:
1. **Menu Screen** - Logo should now be larger and responsive
   - Compare logo size on different screen widths
   - Test orientation changes

2. **Product Detail** - Product description gap should be fixed
   - Scroll through product details
   - Verify spacing between image and description
   - Test on small/medium/large screens

3. **Quantity Controls** - + and - buttons should work
   - Tap + button to increase quantity
   - Tap - button to decrease (minimum: 1)
   - Total price should update

4. **Order Confirmation** - Order should be sent to API
   - Place an order
   - Watch for "Submitting order..." message
   - Should show success message after 2 seconds
   - Order details printed to console

---

## 2. Integrate Your Business API

### Step 1: Update API Endpoint
Edit `lib/services/order_service.dart`:

```dart
class OrderService {
  // TODO: Replace with your actual API endpoint
  static const String apiBaseUrl = 'https://your-business-api.com/api';  // ← CHANGE THIS
  static const String orderEndpoint = '$apiBaseUrl/orders';
  static const String apiKey = 'YOUR_API_KEY_HERE';  // ← CHANGE THIS
```

### Step 2: Add HTTP Package
Edit `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  google_fonts: ^6.2.1
  fl_chart: ^0.69.0
  intl: ^0.19.0
  http: ^1.1.0  # ← ADD THIS LINE
```

Then run: `flutter pub get`

### Step 3: Implement Actual API Call
Replace the `sendOrderToBusinessAPI` method in `lib/services/order_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

static Future<Map<String, dynamic>> sendOrderToBusinessAPI(
  OrderAPIRequest request,
) async {
  try {
    // Create JSON request body
    final jsonBody = jsonEncode(request.toJson());
    
    // Send POST request to your API
    final response = await http.post(
      Uri.parse(orderEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',  // If your API requires Bearer token
      },
      body: jsonBody,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('Order submission timeout'),
    );
    
    // Handle response
    if (response.statusCode == 200 || response.statusCode == 201) {
      print('✓ Order submitted successfully');
      return jsonDecode(response.body);
    } else {
      print('✗ Server error: ${response.statusCode}');
      throw Exception('Failed to submit order: ${response.statusCode}');
    }
  } on http.ClientException catch (e) {
    print('✗ Network error: $e');
    rethrow;
  } catch (e) {
    print('✗ Error submitting order: $e');
    rethrow;
  }
}
```

---

## 3. Database Setup (Supabase)

### Create Tables for Order Tracking

```sql
-- Guests Table
CREATE TABLE guests (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  total_orders INTEGER DEFAULT 0,
  total_spent DECIMAL DEFAULT 0.0,
  api_synced BOOLEAN DEFAULT FALSE
);

-- Orders Table (update existing)
CREATE TABLE orders (
  id TEXT PRIMARY KEY,
  guest_id TEXT REFERENCES guests(id),
  status TEXT DEFAULT 'NEW',
  total DECIMAL NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  api_synced BOOLEAN DEFAULT FALSE
);

-- Order Items Table
CREATE TABLE order_items (
  id TEXT PRIMARY KEY,
  order_id TEXT REFERENCES orders(id),
  item_name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  price DECIMAL NOT NULL,
  add_ons TEXT[] DEFAULT '{}'
);
```

---

## 4. Enable Excel Export

### Step 1: Add Required Packages
Edit `pubspec.yaml`:

```yaml
dependencies:
  # ... existing packages ...
  path_provider: ^2.1.0
  file_picker: ^5.3.0
  permission_handler: ^11.4.0
```

Run: `flutter pub get`

### Step 2: Implement File Export
Edit `lib/services/excel_export_service.dart` - Update `exportToFile()`:

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

static Future<void> exportToFile(
  String data,
  String fileName,
) async {
  try {
    // Get application documents directory
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    
    // Write data to file
    await file.writeAsString(data);
    
    print('✓ File saved to: ${file.path}');
    
    // Optional: Share file
    // await Share.shareFiles([file.path]);
    
  } catch (e) {
    print('✗ Error saving file: $e');
    rethrow;
  }
}
```

### Step 3: Add Export Button to Admin Dashboard
In `lib/screens/admin/admin_dashboard_screen.dart`:

```dart
import '../../services/excel_export_service.dart';

// Add button in admin dashboard
BauhausButton(
  label: 'Export Customers to Excel',
  backgroundColor: AppColors.primary,
  onPressed: () async {
    // Get guest customers (you'd fetch from Supabase)
    final customers = await getGuestCustomers();
    
    // Generate CSV
    final csvData = ExcelExportService.generateCSV(customers);
    
    // Export to file
    await ExcelExportService.exportToFile(
      csvData,
      'guest_customers_${DateTime.now().toString().split(' ')[0]}.csv',
    );
  },
)
```

---

## 5. Fix Order Updates in Admin Panel

### Issue: Orders not updating
### Solution: Use Supabase Realtime

Add to `lib/services/order_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

// Get real-time order updates
static Stream<List<Order>> getOrdersStream() {
  return Supabase.instance.client
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((maps) => maps
          .map((map) => Order.fromJson(map))
          .toList());
}

// Get real-time guest customer updates
static Stream<List<GuestCustomerData>> getGuestCustomersStream() {
  return Supabase.instance.client
      .from('guests')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((maps) => maps
          .map((map) => GuestCustomerData.fromJson(map))
          .toList());
}
```

### Usage in Admin Dashboard:

```dart
// Replace static list with StreamBuilder
StreamBuilder<List<Order>>(
  stream: OrderService.getOrdersStream(),
  builder: (context, snapshot) {
    if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    }
    
    if (!snapshot.hasData) {
      return CircularProgressIndicator();
    }
    
    final orders = snapshot.data!;
    return ListView.builder(
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _OrderRow(
          id: order.id,
          customer: order.customerName,
          item: order.itemsSummary,
        );
      },
    );
  },
)
```

---

## 6. Fix Guest Customer Updates

Add method to sync guest customers:

```dart
// Update guest customer after order
static Future<void> updateGuestCustomer(
  String guestId,
  Order order,
) async {
  try {
    await Supabase.instance.client
        .from('guests')
        .update({
          'total_orders': (await _getTotalOrders(guestId)) + 1,
          'total_spent': (await _getTotalSpent(guestId)) + order.total,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', guestId);
    
    print('✓ Guest customer ${guestId} updated');
  } catch (e) {
    print('✗ Error updating guest: $e');
  }
}
```

---

## 7. Add to pubspec.yaml

```yaml
name: mpro_dining_app
description: "M-PROTI Contactless Dining App - Bauhaus Modernist Design"
publish_to: 'none'

version: 1.0.0+1

environment:
  sdk: ^3.11.4

dependencies:
  flutter:
    sdk: flutter

  cupertino_icons: ^1.0.8
  google_fonts: ^6.2.1
  fl_chart: ^0.69.0
  intl: ^0.19.0
  
  # API & HTTP
  http: ^1.1.0
  
  # Database
  supabase_flutter: ^1.10.0
  
  # File & Export
  path_provider: ^2.1.0
  file_picker: ^5.3.0
  permission_handler: ^11.4.0
  share_plus: ^7.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

---

## 8. Testing Checklist

### Responsive Design
- [ ] Test logo on 320px width screen
- [ ] Test logo on 480px width screen
- [ ] Test logo on tablet (700px width)
- [ ] Test product description spacing
- [ ] Test quantity buttons on all sizes

### API Integration
- [ ] Add your API endpoint URL
- [ ] Add your API key
- [ ] Test with Postman/cURL first
- [ ] Place test order and check logs
- [ ] Verify order appears in your system
- [ ] Check customer details are saved

### Excel Export
- [ ] Generate CSV with sample data
- [ ] Open CSV in Excel
- [ ] Verify formatting
- [ ] Test with 100+ customers
- [ ] Check file location

### Admin Panel
- [ ] Verify orders appear in real-time
- [ ] Update order status in database
- [ ] Check admin dashboard updates
- [ ] Export guest customers to Excel
- [ ] Verify guest customer count

---

## 9. Troubleshooting

### Logo not responsive?
```dart
// Check screen width detection
print('Screen width: ${MediaQuery.of(context).size.width}');
```

### API not receiving data?
```dart
// Print request body
print('Sending: ${jsonEncode(request.toJson())}');
```

### Excel export not working?
```dart
// Check file permissions (Android)
// Check directory exists (iOS)
// Use path_provider to get correct path
```

### Orders not updating?
```dart
// Check Supabase connection
// Verify Stream is listening
// Check database rows exist
```

---

## 10. Quick Support Links

- **Supabase Docs**: https://supabase.com/docs/reference/dart
- **Flutter Documentation**: https://flutter.dev/docs
- **HTTP Package**: https://pub.dev/packages/http
- **Path Provider**: https://pub.dev/packages/path_provider
- **File Picker**: https://pub.dev/packages/file_picker

---

## Next Steps

1. ✅ Test current responsive design
2. ✅ Set up your database (Supabase)
3. ✅ Add API endpoint details
4. ✅ Implement actual HTTP calls
5. ✅ Set up Supabase realtime listeners
6. ✅ Test full order flow
7. ✅ Enable Excel export
8. ✅ Deploy to production

Good luck! 🚀
