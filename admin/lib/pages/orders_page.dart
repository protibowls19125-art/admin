import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/admin_orders_provider.dart';
import '../providers/auth_provider.dart';

/// All orders, regardless of type. Once a delivery order is marked PREPARED
/// on the KDS, it drops off here and moves to the Gym Delivery page for
/// agent assignment — see gym_delivery_page.dart.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<AdminOrdersProvider>();
    // Deferred to a microtask — fetchOrders() notifies listeners
    // synchronously (before its first await), which trips Flutter's
    // "notify during build" assertion when called directly from initState.
    Future.microtask(() {
      if (mounted) provider.fetchOrders();
    });
    provider.startAutoRefresh();
  }

  @override
  void dispose() {
    context.read<AdminOrdersProvider>().stopAutoRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ORDERS',
            style: GoogleFonts.chivo(
                fontSize: 24, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            tooltip: 'Logout',
            onPressed: () async {
              await adminAuth.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Consumer<AdminOrdersProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return _OrderList(
            orders: provider.orders,
            provider: provider,
            emptyMessage: 'No orders yet',
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// All orders list
// ─────────────────────────────────────────────────────────────────────────────

class _OrderList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final AdminOrdersProvider provider;
  final String emptyMessage;

  const _OrderList({
    required this.orders,
    required this.provider,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
          child: Text(emptyMessage,
              style: GoogleFonts.chivo(fontSize: 18, color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) =>
          _OrderCard(order: orders[index], provider: provider),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Standard order card
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final AdminOrdersProvider provider;

  const _OrderCard({required this.order, required this.provider});

  @override
  Widget build(BuildContext context) {
    final customer =
        order['customer_info'] ?? order['guest_customers'] ?? {};
    final items = order['items'] ?? order['order_items'] ?? [];
    final status = order['status'] ?? 'pending';
    final orderType = (order['order_type'] ?? '').toString().toLowerCase();
    final isDelivery = orderType == 'delivery';

    final createdAt = order['created_at'] ??
        order['timestamp'] ??
        DateTime.now().toIso8601String();
    final orderTime = DateTime.parse(createdAt);
    final timeDisplay =
        '${orderTime.hour}:${orderTime.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(
          color: isDelivery
              ? const Color(0xFF1565C0)
              : Colors.black,
          width: isDelivery ? 2 : 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isDelivery) ...[
                          const Icon(Icons.delivery_dining,
                              size: 16, color: Color(0xFF1565C0)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          'ORDER #${(order['order_number'] ?? order['id'].toString().substring(0, 8)).toString().toUpperCase()}',
                          style: GoogleFonts.chivo(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isDelivery
                                ? const Color(0xFF1565C0)
                                : Colors.black,
                          ),
                        ),
                      ],
                    ),
                    Text(timeDisplay,
                        style: GoogleFonts.chivo(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600])),
                  ],
                ),
                // Once a delivery order reaches "prepared" it's off the KDS
                // pipeline (agent assignment happens on the Gym Delivery
                // page) — the dropdown here only covers the kitchen steps.
                // awaiting_payment is read-only too: the online payment
                // hasn't actually completed yet, so there's nothing for
                // staff to confirm/advance until Razorpay finalizes it.
                if (['prepared', 'in_transit', 'delivered']
                        .contains(status) ||
                    status == 'awaiting_payment')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: status == 'awaiting_payment'
                          ? Colors.orange[100]
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status == 'awaiting_payment'
                          ? 'AWAITING PAYMENT'
                          : status.toString().toUpperCase().replaceAll('_', ' '),
                      style: GoogleFonts.chivo(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: status == 'awaiting_payment'
                              ? Colors.orange[900]
                              : null),
                    ),
                  )
                else
                  DropdownButton<String>(
                    value: status,
                    // Include the current status so old values don't crash the dropdown.
                    items: {..._statusOptions, status.toString()}
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.toUpperCase().replaceAll('_', ' ')),
                            ))
                        .toList(),
                    onChanged: status == 'cancelled'
                        ? null
                        : (newStatus) {
                            if (newStatus != null && newStatus != status) {
                              provider.updateOrderStatus(order['id'], newStatus);
                            }
                          },
                  ),
              ],
            ),
            const Divider(thickness: 1, height: 12),
            Text(
              '${customer['name'] ?? 'Guest'}  •  ${customer['phone'] ?? 'N/A'}',
              style: GoogleFonts.chivo(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ...items.map((item) {
              final itemName = item['name'] ??
                  (item['menu_items']?['name'] ?? 'Item');
              final quantity = item['quantity'] ?? 1;
              final price =
                  (item['price'] as num?)?.toDouble() ?? 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  price <= 0
                      ? '${quantity}x $itemName  —  FREE'
                      : '${quantity}x $itemName  —  ₹${(price * quantity).toStringAsFixed(0)}',
                  style: GoogleFonts.chivo(fontSize: 12),
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (order['total_price'] as num?)?.toDouble() == 0
                      ? 'TOTAL: FREE'
                      : 'TOTAL: ₹${(order['total_price'] as num?)?.toStringAsFixed(0) ?? '0'}',
                  style: GoogleFonts.chivo(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green),
                ),
                Text(
                  '${orderType.toUpperCase().replaceAll('_', ' ')}  •  ${(order['payment_method'] ?? 'COD').toString().toUpperCase()}',
                  style: GoogleFonts.chivo(
                      fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Kitchen-stage statuses only — 'prepared'/'in_transit'/'delivered' for
// delivery orders are set via the KDS button and the Gym Delivery page, not
// this raw dropdown (see the status container branch above).
const _statusOptions = [
  'pending',
  'confirmed',
  'preparing',
  'completed',
  'cancelled',
];
