import 'dart:async';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class AdminOrdersProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  /// Delivery agent roster — shared with the subscription model's
  /// delivery_agents table (same delivery staff either way).
  List<Map<String, dynamic>> agents = [];

  /// Order ids seen on the previous fetch, used to detect newly arrived orders.
  Set<String> _knownOrderIds = {};

  /// True once the first fetch has established a baseline. The very first load
  /// must NOT fire [onNewOrder] for the orders that already exist.
  bool _baselineSet = false;

  /// Called when one or more brand-new (pending) orders appear between fetches.
  /// The KDS page uses this to play the kitchen notification sound.
  VoidCallback? onNewOrder;

  List<Map<String, dynamic>> get orders => _orders;
  bool get isLoading => _isLoading;

  void startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      fetchOrders();
    });
  }

  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchOrders() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await SupabaseService.client
          .from('orders')
          .select('*')
          .order('created_at', ascending: false);

      _orders = List<Map<String, dynamic>>.from(response);

      // Detect newly arrived ACTIVE orders. We track only the ids of orders
      // that are in actionable states (pending/confirmed). Online orders
      // start as 'awaiting_payment' and transition to 'pending' after
      // payment verification. By tracking only active ids, that transition
      // shows up as a "new" active order and triggers the kitchen alert.
      final activeIds = <String>{};
      bool hasNewOrder = false;
      for (final o in _orders) {
        final status = o['status']?.toString();
        final id = o['id']?.toString();
        if (id == null) continue;
        if (status == 'pending' || status == 'confirmed') {
          activeIds.add(id);
          if (!_knownOrderIds.contains(id)) {
            hasNewOrder = true;
          }
        }
      }
      _knownOrderIds = activeIds;
      if (_baselineSet && hasNewOrder) {
        onNewOrder?.call();
      }
      _baselineSet = true;
    } catch (e) {
      debugPrint('Error fetching orders: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      await SupabaseService.client.from('orders').update({
        'status': newStatus,
        // Recorded once, at the moment of delivery — this is what the
        // Agent Performance page groups by date/week/month.
        if (newStatus == 'delivered')
          'delivered_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      await fetchOrders();
    } catch (e) {
      debugPrint('Error updating order status: $e');
    }
  }

  /// Manual trigger of the nightly export ("Push to Sheet now" in Settings).
  /// Idempotent by design — export-orders-to-sheets only ever picks up rows
  /// where synced_to_sheet = false, so calling this right before or right
  /// after the nightly pg_cron run touches a disjoint set of orders either
  /// way. Never appends the same order to the sheet twice.
  Future<String?> pushOrdersToSheetNow() async {
    try {
      final res = await SupabaseService.client.functions
          .invoke('export-orders-to-sheets', body: {'source': 'manual'});
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['error'] != null) return data['error'].toString();
      final exported = data['exported'] ?? 0;
      final pruned = data['pruned'] ?? 0;
      return 'Pushed $exported order(s) to the sheet'
          '${pruned > 0 ? ', pruned $pruned old row(s) from Supabase' : ''}.';
    } catch (e) {
      return 'Push failed: $e';
    }
  }

  Future<void> fetchAgents() async {
    try {
      final rows = await SupabaseService.client
          .from('delivery_agents')
          .select()
          .order('name');
      agents = List<Map<String, dynamic>>.from(rows);
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching delivery agents: $e');
    }
  }

  /// Same roster the subscription model manages from Settings — added here
  /// too since gym_manager has no access to that developer-only page.
  Future<String?> addAgent(String name, String phone) async {
    try {
      await SupabaseService.client
          .from('delivery_agents')
          .insert({'name': name, 'phone': phone});
      await fetchAgents();
      return null;
    } catch (e) {
      return 'Could not add agent: $e';
    }
  }

  Future<void> assignAgent(String orderId, String? agentId) async {
    try {
      await SupabaseService.client
          .from('orders')
          .update({'delivery_agent_id': agentId})
          .eq('id', orderId);
      await fetchOrders();
    } catch (e) {
      debugPrint('Error assigning delivery agent: $e');
    }
  }

  int get totalOrders => _orders.length;
  int get pendingOrders => _orders.where((o) => o['status'] == 'pending').length;
  int get preparingOrders => _orders.where((o) => o['status'] == 'preparing').length;
  int get completedOrders => _orders.where((o) => o['status'] == 'completed').length;

  int _countByType(String type) => _orders
      .where((o) => (o['order_type'] ?? '').toString().toLowerCase() == type)
      .length;
  int get dineInOrders => _countByType('dine_in');
  int get takeawayOrders => _countByType('takeaway');
  int get deliveryOrders => _countByType('delivery');

  double get totalSales {
    return _orders
        .where((o) => o['status'] == 'completed')
        .fold(0.0, (sum, order) => sum + (order['total_price'] ?? 0.0));
  }
}
