import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/local_storage_service.dart';
import '../services/shared_orders_service.dart';
import '../services/guest_customer_tracking_service.dart';
import '../services/supabase_service.dart';
import '../services/razorpay_service.dart';

class OrderProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = false;
  final _localStorage = LocalStorageService();
  final _sharedOrders = SharedOrdersService();
  final _guestCustomerTracking = GuestCustomerTrackingService();

  List<Map<String, dynamic>> get orders => _orders;
  bool get isLoading => _isLoading;

  /// Online order: server computes the price, creates the Razorpay order,
  /// runs checkout, and finalizes the order after verifying the signature.
  /// The client never sends prices.
  Future<PlaceOrderResult> placeOnlineOrder({
    required String customerName,
    required String customerPhone,
    required String orderType,
    required List<Map<String, dynamic>> items, // [{menu_item_id, quantity}]
    Map<String, String>? deliveryAddress,
  }) async {
    final r = await RazorpayService().placeOnlineOrder(
      items: items,
      customerName: customerName,
      customerPhone: customerPhone,
      orderType: orderType,
      deliveryAddress: deliveryAddress,
    );
    if (!r.success) return r;

    await _mirrorLocal(
      orderNumber: r.orderNumber ?? '',
      dbOrderId: r.dbOrderId,
      lineItems: r.items ?? const [],
      totalPrice: r.totalPrice ?? 0,
      customerName: customerName,
      customerPhone: customerPhone,
      orderType: orderType,
      deliveryAddress: deliveryAddress,
      paymentMethod: 'online',
      paymentDetails: {'provider': 'razorpay', 'status': 'paid'},
    );
    await fetchOrders();
    return r;
  }

  /// Cash order: server computes the price and stores the order. No payment.
  Future<String> placeCodOrder({
    required String customerName,
    required String customerPhone,
    required String orderType,
    required List<Map<String, dynamic>> items, // [{menu_item_id, quantity}]
    Map<String, String>? deliveryAddress,
  }) async {
    return _placeDirectOrder(
      paymentMethod: 'cod',
      customerName: customerName,
      customerPhone: customerPhone,
      orderType: orderType,
      items: items,
      deliveryAddress: deliveryAddress,
    );
  }

  /// Free order (total = ₹0): no payment at all — order placed directly.
  Future<String> placeFreeOrder({
    required String customerName,
    required String customerPhone,
    required String orderType,
    required List<Map<String, dynamic>> items,
    Map<String, String>? deliveryAddress,
  }) async {
    return _placeDirectOrder(
      paymentMethod: 'free',
      customerName: customerName,
      customerPhone: customerPhone,
      orderType: orderType,
      items: items,
      deliveryAddress: deliveryAddress,
    );
  }

  /// Shared implementation for COD and free orders — both skip Razorpay.
  Future<String> _placeDirectOrder({
    required String paymentMethod,
    required String customerName,
    required String customerPhone,
    required String orderType,
    required List<Map<String, dynamic>> items,
    Map<String, String>? deliveryAddress,
  }) async {
    final Map<String, dynamic> data;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'razorpay-create-order',
        body: {
          'payment_method': paymentMethod,
          'order_type': orderType,
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'items': items,
          if (deliveryAddress != null) 'delivery_address': deliveryAddress,
        },
      );
      data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
    } on FunctionException catch (e) {
      throw Exception(cleanErrorMessage(e, 'Could not place order'));
    }
    if (data['orderNumber'] == null) {
      throw Exception(data['error']?.toString() ?? 'Could not place order');
    }
    final orderNumber = data['orderNumber'].toString();

    await _mirrorLocal(
      orderNumber: orderNumber,
      dbOrderId: data['dbOrderId']?.toString(),
      lineItems: (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
      totalPrice: (data['totalPrice'] as num?)?.toDouble() ?? 0,
      customerName: customerName,
      customerPhone: customerPhone,
      orderType: orderType,
      deliveryAddress: deliveryAddress,
      paymentMethod: paymentMethod,
      paymentDetails: null,
    );
    await fetchOrders();
    return orderNumber;
  }

  /// Mirror the server-created order into local storage so the confirmation
  /// and "my orders" screens (which read locally) keep working.
  Future<void> _mirrorLocal({
    required String orderNumber,
    required String? dbOrderId,
    required List<Map<String, dynamic>> lineItems,
    required double totalPrice,
    required String customerName,
    required String customerPhone,
    required String orderType,
    required Map<String, String>? deliveryAddress,
    required String paymentMethod,
    required Map<String, dynamic>? paymentDetails,
  }) async {
    final createdAt = DateTime.now().toIso8601String();
    final customerId = _guestCustomerTracking.generateCustomerId();

    await _localStorage.saveCustomerInfo(
      name: customerName,
      phone: customerPhone,
      orderType: orderType,
    );

    final orderData = {
      'id': orderNumber,
      'supabase_id': dbOrderId,
      'customer_id': customerId,
      'items': lineItems,
      'total_price': totalPrice,
      'order_type': orderType,
      'customer_info': {
        'name': customerName,
        'phone': customerPhone,
        'order_type': orderType,
        if (deliveryAddress != null) 'delivery_address': deliveryAddress,
        if (paymentDetails != null) 'payment': paymentDetails,
      },
      'payment_method': paymentMethod,
      'status': 'pending',
      'created_at': createdAt,
      if (deliveryAddress != null) 'delivery_address': deliveryAddress,
    };

    await _localStorage.saveOrder(
      orderId: orderNumber,
      items: lineItems,
      totalPrice: totalPrice,
      orderType: orderType,
    );
    await _sharedOrders.saveOrderToShared(
      orderId: orderNumber,
      orderData: orderData,
    );
    await _guestCustomerTracking.saveGuestCustomer(
      customerId: customerId,
      name: customerName,
      phone: customerPhone,
      email: '',
      orderType: orderType,
      totalSpent: totalPrice,
    );
  }

  Future<void> fetchOrders() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _sharedOrders.init();
      _orders = _sharedOrders.getAllOrders();
      _orders.sort((a, b) => DateTime.parse(b['created_at'] as String)
          .compareTo(DateTime.parse(a['created_at'] as String)));

      // Sync status from the server (orders are no longer anon-readable, so we
      // ask get-order-status for just our own order ids).
      final ids =
          _orders.map((o) => o['supabase_id']).whereType<String>().toList();
      if (ids.isNotEmpty) {
        try {
          final res = await SupabaseService.client.functions
              .invoke('get-order-status', body: {'ids': ids});
          final list = ((res.data as Map?)?['orders'] as List?) ?? const [];
          final statusById = <String, dynamic>{
            for (final r in list) (r as Map)['id']: r['status'],
          };
          for (var i = 0; i < _orders.length; i++) {
            final sid = _orders[i]['supabase_id'];
            if (sid != null && statusById[sid] != null) {
              _orders[i] = Map<String, dynamic>.from(_orders[i])
                ..['status'] = statusById[sid];
            }
          }
        } catch (_) {/* keep local statuses */}
      }
    } catch (e) {
      debugPrint('Error fetching orders: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    // Customer-side status is mirrored locally; the server is the source of
    // truth (admin updates it, and fetchOrders re-syncs from get-order-status).
    await _sharedOrders.updateOrderStatus(orderId, newStatus);
    await fetchOrders();
  }

  /// Customer-initiated cancel — calls the `cancel-order` edge function; the
  /// server is the source of truth on whether it's still allowed (only while
  /// still pending, before the kitchen confirms). Returns null on success, or
  /// a user-facing message explaining why it was rejected (or that the
  /// request failed).
  Future<String?> cancelOrder(Map<String, dynamic> order) async {
    final supabaseId = order['supabase_id'] as String?;
    final localId = order['id'] as String?;
    if (supabaseId == null || localId == null) {
      return 'This order can\'t be cancelled — try refreshing your orders.';
    }
    try {
      final res = await SupabaseService.client.functions
          .invoke('cancel-order', body: {'orderId': supabaseId});
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['cancelled'] == true) {
        await _sharedOrders.updateOrderStatus(localId, 'cancelled');
        await fetchOrders();
        return null;
      }
      return data['error']?.toString() ??
          'This order can no longer be cancelled.';
    } catch (e) {
      debugPrint('Error cancelling order: $e');
      return 'Could not reach the server — please try again.';
    }
  }

  Future<void> clearAllOrders() async {
    await _localStorage.clearAllOrders();
    await _sharedOrders.clearAllOrders();
    await fetchOrders();
  }
}
