import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LocalStorageService {
  static final _instance = LocalStorageService._internal();
  late SharedPreferences _prefs;

  factory LocalStorageService() {
    return _instance;
  }

  LocalStorageService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Customer Information
  Future<void> saveCustomerInfo({
    required String name,
    required String phone,
    required String orderType,
  }) async {
    final customerData = {
      'name': name,
      'phone': phone,
      'order_type': orderType,
      'saved_at': DateTime.now().toIso8601String(),
    };
    await _prefs.setString('customer_info', jsonEncode(customerData));
  }

  Map<String, dynamic>? getCustomerInfo() {
    final data = _prefs.getString('customer_info');
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  Future<void> clearCustomerInfo() async {
    await _prefs.remove('customer_info');
  }

  // Order Data
  Future<void> saveOrder({
    required String orderId,
    required List<Map<String, dynamic>> items,
    required double totalPrice,
    required String orderType,
  }) async {
    final orderData = {
      'id': orderId,
      'items': items,
      'total_price': totalPrice,
      'order_type': orderType,
      'customer_info': getCustomerInfo(),
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    };

    // Save current order
    await _prefs.setString('current_order', jsonEncode(orderData));

    // Also save to order history
    List<String> orderHistory = _prefs.getStringList('order_history') ?? [];
    orderHistory.add(jsonEncode(orderData));
    await _prefs.setStringList('order_history', orderHistory);
  }

  Map<String, dynamic>? getCurrentOrder() {
    final data = _prefs.getString('current_order');
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> getOrderHistory() {
    final orders = _prefs.getStringList('order_history') ?? [];
    return orders.map((order) => jsonDecode(order) as Map<String, dynamic>).toList();
  }

  Future<void> clearCurrentOrder() async {
    await _prefs.remove('current_order');
  }

  Future<void> clearAllOrders() async {
    await _prefs.remove('order_history');
    await _prefs.remove('current_order');
  }

  // Cart Data
  Future<void> saveCart(List<Map<String, dynamic>> cartItems) async {
    await _prefs.setString('cart', jsonEncode(cartItems));
  }

  List<Map<String, dynamic>> getCart() {
    final data = _prefs.getString('cart');
    if (data == null) return [];
    final list = jsonDecode(data) as List;
    return list.map((item) => item as Map<String, dynamic>).toList();
  }

  Future<void> clearCart() async {
    await _prefs.remove('cart');
  }

  // Generate order ID in format DDMMCC (day + month + per-customer count)
  // Count resets to 1 for each new customer (identified by phone number)
  Future<String> generateOrderId({String? customerPhone}) async {
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final lastDate = _prefs.getString('last_order_date') ?? '';
    final lastPhone = _prefs.getString('last_order_phone') ?? '';
    int count = _prefs.getInt('daily_order_count') ?? 0;

    final isNewDay = lastDate != todayKey;
    final isNewCustomer = customerPhone != null &&
        customerPhone.isNotEmpty &&
        customerPhone != lastPhone;

    if (isNewDay || isNewCustomer) {
      count = 0;
      await _prefs.setString('last_order_date', todayKey);
      if (customerPhone != null && customerPhone.isNotEmpty) {
        await _prefs.setString('last_order_phone', customerPhone);
      }
    }

    count++;
    await _prefs.setInt('daily_order_count', count);

    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final cc = count.toString().padLeft(2, '0');

    return '$dd$mm$cc';
  }

  // Get all stored data (for debugging)
  Future<Map<String, dynamic>> getAllData() async {
    return {
      'customer_info': getCustomerInfo(),
      'current_order': getCurrentOrder(),
      'order_history': getOrderHistory(),
      'cart': getCart(),
    };
  }
}
