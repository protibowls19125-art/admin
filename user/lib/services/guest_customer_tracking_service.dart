import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Guest Customer tracking service - stores customer details accessible to admin
class GuestCustomerTrackingService {
  static final _instance = GuestCustomerTrackingService._internal();
  late SharedPreferences _prefs;
  static const String _customersKey = 'shared_guest_customers';

  factory GuestCustomerTrackingService() {
    return _instance;
  }

  GuestCustomerTrackingService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Save guest customer after order creation
  Future<void> saveGuestCustomer({
    required String customerId,
    required String name,
    required String phone,
    required String email,
    required String orderType,
    required double totalSpent,
  }) async {
    try {
      List<String> allCustomers = _prefs.getStringList(_customersKey) ?? [];

      final customer = {
        'id': customerId,
        'name': name,
        'phone': phone,
        'email': email,
        'order_type': orderType,
        'total_spent': totalSpent,
        'created_at': DateTime.now().toIso8601String(),
      };

      allCustomers.add(jsonEncode(customer));
      await _prefs.setStringList(_customersKey, allCustomers);
      debugPrint('✅ Guest customer saved: $customerId - $name');
    } catch (e) {
      debugPrint('❌ Error saving guest customer: $e');
    }
  }

  /// Get all guest customers
  List<Map<String, dynamic>> getAllCustomers() {
    try {
      List<String> customersJson = _prefs.getStringList(_customersKey) ?? [];
      debugPrint('✅ Retrieved ${customersJson.length} guest customers');
      return customersJson
          .map((customer) => jsonDecode(customer) as Map<String, dynamic>)
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Error getting customers: $e');
      return [];
    }
  }

  /// Get customer by ID
  Map<String, dynamic>? getCustomerById(String customerId) {
    try {
      final customers = getAllCustomers();
      return customers.firstWhere(
        (c) => c['id'] == customerId,
        orElse: () => {},
      );
    } catch (e) {
      return null;
    }
  }

  /// Update customer spending
  Future<void> updateCustomerSpending(
      String customerId, double additionalSpent) async {
    try {
      List<String> allCustomers = _prefs.getStringList(_customersKey) ?? [];

      allCustomers = allCustomers.map((customerJson) {
        final customer = jsonDecode(customerJson) as Map<String, dynamic>;
        if (customer['id'] == customerId) {
          final currentSpent =
              (customer['total_spent'] as num?)?.toDouble() ?? 0.0;
          customer['total_spent'] = currentSpent + additionalSpent;
          customer['updated_at'] = DateTime.now().toIso8601String();
        }
        return jsonEncode(customer);
      }).toList();

      await _prefs.setStringList(_customersKey, allCustomers);
      debugPrint('✅ Customer spending updated: $customerId');
    } catch (e) {
      debugPrint('❌ Error updating customer spending: $e');
    }
  }

  /// Get total customers
  int getTotalCustomers() {
    try {
      return getAllCustomers().length;
    } catch (e) {
      return 0;
    }
  }

  /// Get total customer spending
  double getTotalCustomerSpending() {
    try {
      final customers = getAllCustomers();
      return customers.fold<double>(
        0.0,
        (sum, customer) =>
            sum + ((customer['total_spent'] as num?)?.toDouble() ?? 0.0),
      );
    } catch (e) {
      return 0.0;
    }
  }

  /// Generate unique customer ID
  String generateCustomerId() {
    return 'CUST_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Clear all customers (for testing)
  Future<void> clearAllCustomers() async {
    await _prefs.remove(_customersKey);
    debugPrint('All guest customers cleared');
  }

  /// Export customers as JSON
  String exportCustomersAsJson() {
    try {
      final customers = getAllCustomers();
      return jsonEncode({
        'total_customers': customers.length,
        'export_date': DateTime.now().toIso8601String(),
        'customers': customers,
      });
    } catch (e) {
      return '{"error": "$e"}';
    }
  }

  /// Export customers as CSV
  String exportCustomersAsCSV() {
    try {
      final customers = getAllCustomers();
      const header = 'ID,Name,Phone,Email,Order Type,Total Spent,Created At\n';

      final rows = customers.map((c) {
        return [
          c['id'] ?? '',
          c['name'] ?? '',
          c['phone'] ?? '',
          c['email'] ?? '',
          c['order_type'] ?? '',
          c['total_spent'] ?? '0',
          c['created_at'] ?? '',
        ].map((v) => '"$v"').join(',');
      }).join('\n');

      return header + rows;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Debug: Print all customers
  void debugPrintAllCustomers() {
    try {
      final customers = getAllCustomers();
      debugPrint('=== DEBUG: Total Guest Customers: ${customers.length} ===');
      for (var i = 0; i < customers.length; i++) {
        final customer = customers[i];
        debugPrint(
            'Customer $i: ${customer['name']} (${customer['phone']}) - Spent: ₹${customer['total_spent']}');
      }
      debugPrint('=== END DEBUG ===');
    } catch (e) {
      debugPrint('Error debugging customers: $e');
    }
  }
}
