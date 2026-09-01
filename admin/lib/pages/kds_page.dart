import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/admin_orders_provider.dart';
import '../providers/admin_menu_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/new_order_sound.dart';

class KDSPage extends StatefulWidget {
  const KDSPage({super.key});

  @override
  State<KDSPage> createState() => _KDSPageState();
}

class _KDSPageState extends State<KDSPage> {
  // Kitchen notification sound played when a new order arrives. Lives in
  // admin/web/sounds/ so it's served from the app's base href (e.g. /admin/).
  // Loops indefinitely — the only way to silence it is confirming the order
  // (see _stopSoundIfNoPending), by design: a chef who's stepped away should
  // come back to a ringing kitchen, not a silently-missed order.
  final NewOrderSound _newOrderSound = NewOrderSound();

  /// Whether the 15s background polling is active. Toggled from the app bar.
  bool _autoRefresh = true;

  /// Timer to tick elapsed order timers live every 1 second
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    final ordersProvider = context.read<AdminOrdersProvider>();
    ordersProvider.onNewOrder = _playNewOrderSound;
    // Stop the alert as soon as the chef confirms the order that triggered
    // it (updateOrderStatus refetches immediately, so this fires right away
    // rather than waiting for the next 15s poll).
    ordersProvider.addListener(_stopSoundIfNoPending);
    // Deferred to a microtask — fetchOrders() notifies listeners
    // synchronously (before its first await), which trips Flutter's
    // "notify during build" assertion when called directly from initState.
    Future.microtask(() {
      if (!mounted) return;
      ordersProvider.fetchOrders();
      context.read<AdminMenuProvider>().fetchAll();
    });
    ordersProvider.startAutoRefresh();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _playNewOrderSound() {
    try {
      // play() returns a promise that rejects if the browser blocks autoplay;
      // the chef has interacted (login/navigation) by now so it's unlocked.
      _newOrderSound.play(loop: true);
    } catch (_) {
      // Ignore audio failures — a silent KDS is better than a crash.
    }
  }

  void _stopSoundIfNoPending() {
    if (context.read<AdminOrdersProvider>().pendingOrders == 0) {
      _newOrderSound.stop();
    }
  }

  /// Fetch orders immediately, regardless of the auto-refresh timer.
  Future<void> _refreshNow() =>
      context.read<AdminOrdersProvider>().fetchOrders();

  /// Turn the 15s background polling on/off.
  void _toggleAutoRefresh() {
    final provider = context.read<AdminOrdersProvider>();
    setState(() => _autoRefresh = !_autoRefresh);
    if (_autoRefresh) {
      provider.startAutoRefresh();
      provider.fetchOrders(); // refresh straight away when re-enabled
    } else {
      provider.stopAutoRefresh();
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    final ordersProvider = context.read<AdminOrdersProvider>();
    ordersProvider.onNewOrder = null;
    ordersProvider.removeListener(_stopSoundIfNoPending);
    ordersProvider.stopAutoRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          '🔴 KITCHEN DISPLAY',
          style: GoogleFonts.chivo(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/'),
        ),
        actions: [
          // Manual refresh — pull the latest orders right now.
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            tooltip: 'Refresh now',
            onPressed: _refreshNow,
          ),
          // Auto-refresh toggle (15s polling on/off).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextButton.icon(
              onPressed: _toggleAutoRefresh,
              icon: Icon(
                _autoRefresh ? Icons.autorenew : Icons.sync_disabled,
                size: 20,
                color: _autoRefresh ? Colors.green.shade700 : Colors.grey,
              ),
              label: Text(
                _autoRefresh ? 'Auto ON' : 'Auto OFF',
                style: GoogleFonts.chivo(
                  fontWeight: FontWeight.w700,
                  color: _autoRefresh ? Colors.green.shade700 : Colors.grey,
                ),
              ),
            ),
          ),
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
      body: Consumer2<AdminOrdersProvider, AdminMenuProvider>(
        builder: (context, ordersProvider, menuProvider, _) {
          // Build image URL lookup map
          final imageMap = <String, String?>{};
          for (final item in menuProvider.items) {
            imageMap[item.id] = item.imageUrl;
          }

          final activeOrders = ordersProvider.orders
              .where((o) =>
                  o['status'] == 'pending' ||
                  o['status'] == 'confirmed' ||
                  o['status'] == 'preparing')
              .toList()
            // First-in-first-served: oldest order shown first.
            ..sort((a, b) => (DateTime.tryParse(
                        a['created_at']?.toString() ?? '') ??
                    DateTime.now())
                .compareTo(DateTime.tryParse(
                        b['created_at']?.toString() ?? '') ??
                    DateTime.now()));

          if (activeOrders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.done_all, size: 80, color: Colors.green),
                  const SizedBox(height: 16),
                  Text(
                    'ALL ORDERS COMPLETE!',
                    style: GoogleFonts.chivo(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            // Max-extent + fixed height instead of a fixed column count with a
            // width-derived aspect ratio — the old ratio made cells too short
            // for the (non-scrollable) header/timer/button chrome on a narrow
            // phone screen, regardless of how much was made scrollable inside.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 360,
            ),
            itemCount: activeOrders.length,
            itemBuilder: (context, index) {
              final order = activeOrders[index];
              final status = order['status'] as String? ?? 'pending';
              final items = order['items'] as List<dynamic>? ?? [];
              final customerName =
                  order['customer_name'] as String? ?? 'Guest';
              final orderType = (order['order_type'] as String?) ?? '';
              final customerInfo =
                  (order['customer_info'] as Map?)?.cast<String, dynamic>() ??
                      {};
              // Address can be top-level or nested in customer_info.
              final deliveryAddress = (order['delivery_address'] as Map?)
                      ?.cast<String, dynamic>() ??
                  (customerInfo['delivery_address'] as Map?)
                      ?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final createdAt =
                  DateTime.tryParse(order['created_at'] as String? ?? '');
              Duration waitDuration = Duration.zero;
              if (createdAt != null) {
                final utcNow = DateTime.now().toUtc();
                final utcStart = createdAt.isUtc ? createdAt : createdAt.toUtc();
                final diff = utcNow.difference(utcStart);
                waitDuration = diff.isNegative ? Duration.zero : diff;
              }

              return _OrderCard(
                orderId: order['order_number']?.toString() ??
                    order['id'].toString().substring(0, 8),
                customerName: customerName,
                status: status,
                items: items,
                imageMap: imageMap,
                waitDuration: waitDuration,
                orderType: orderType,
                deliveryAddress: deliveryAddress,
                onStatusChange: (newStatus) {
                  ordersProvider.updateOrderStatus(
                      order['id'] as String, newStatus);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final String orderId;
  final String customerName;
  final String status;
  final List<dynamic> items;
  final Map<String, String?> imageMap;
  final Duration waitDuration;
  final String orderType;
  final Map<String, dynamic> deliveryAddress;
  final Function(String) onStatusChange;

  const _OrderCard({
    required this.orderId,
    required this.customerName,
    required this.status,
    required this.items,
    required this.imageMap,
    required this.waitDuration,
    required this.onStatusChange,
    this.orderType = '',
    this.deliveryAddress = const {},
  });

  Color get statusColor {
    switch (status) {
      case 'pending':
        return Colors.red;
      case 'confirmed':
        return Colors.blue;
      case 'preparing':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  bool get isDelivery => orderType.toLowerCase() == 'delivery';

  /// White pill in the header showing the order type, emphasized for delivery.
  Widget _typeBadge() {
    IconData icon;
    String label;
    switch (orderType.toLowerCase()) {
      case 'delivery':
        icon = Icons.delivery_dining;
        label = 'DELIVERY';
        break;
      case 'takeaway':
        icon = Icons.takeout_dining;
        label = 'TAKEAWAY';
        break;
      default:
        icon = Icons.restaurant;
        label = 'DINE IN';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: statusColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: GoogleFonts.chivo(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: statusColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact address block for delivery orders (street / landmark / city — pincode).
  Widget _deliveryAddressBlock() {
    final street = (deliveryAddress['address'] ?? '').toString();
    final landmark = (deliveryAddress['landmark'] ?? '').toString();
    final city = (deliveryAddress['city'] ?? '').toString();
    final pincode = (deliveryAddress['pincode'] ?? '').toString();
    final cityLine =
        [city, pincode].where((v) => v.isNotEmpty).join(' — ');
    final mapsUrl = () {
      final link = (deliveryAddress['maps_link'] ?? '').toString();
      if (link.isNotEmpty) return link;
      final lat = (deliveryAddress['latitude'] ?? '').toString();
      final lng = (deliveryAddress['longitude'] ?? '').toString();
      if (lat.isNotEmpty && lng.isNotEmpty) {
        return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      }
      return '';
    }();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFFE3F2FD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 13, color: Color(0xFF1565C0)),
              const SizedBox(width: 4),
              Text(
                'DELIVER TO',
                style: GoogleFonts.chivo(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1565C0),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (street.isNotEmpty)
            Text(
              street,
              style: GoogleFonts.chivo(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (landmark.isNotEmpty)
            Text(
              'Near: $landmark',
              style: GoogleFonts.chivo(fontSize: 11, color: Colors.black54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (cityLine.isNotEmpty)
            Text(
              cityLine,
              style: GoogleFonts.chivo(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
          if (mapsUrl.isNotEmpty) ...[
            const SizedBox(height: 5),
            InkWell(
              onTap: () => launchUrl(Uri.parse(mapsUrl),
                  mode: LaunchMode.externalApplication),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation,
                      size: 13, color: Color(0xFF1565C0)),
                  const SizedBox(width: 4),
                  Text('OPEN IN MAPS',
                      style: GoogleFonts.chivo(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1565C0),
                          letterSpacing: 0.5,
                          decoration: TextDecoration.underline)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: statusColor, width: 4),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(8),
            color: statusColor,
            child: Column(
              children: [
                Text(
                  orderId,
                  style: GoogleFonts.chivo(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  customerName.toUpperCase(),
                  style: GoogleFonts.chivo(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (orderType.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  _typeBadge(),
                ],
              ],
            ),
          ),
          // Items + delivery address — scrollable so a short grid cell on a
          // narrow screen (e.g. a phone) never RenderFlex-overflows; it
          // scrolls internally instead.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: items.map((item) {
                  final name = item['name'] as String? ?? 'Item';
                  final qty = item['quantity'] ?? 1;
                  final note = item['note'] as String?;
                  final menuItemId = item['menu_item_id'] as String?;
                  final imageUrl =
                      menuItemId != null ? imageMap[menuItemId] : null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        if (imageUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              imageUrl,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 40,
                                height: 40,
                                color: Colors.grey[700],
                                child: const Icon(Icons.fastfood,
                                    size: 20, color: Colors.white54),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey[700],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.fastfood,
                                size: 20, color: Colors.white54),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${qty}x $name',
                                style: GoogleFonts.chivo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              if (note != null && note.isNotEmpty)
                                Text(
                                  '🌶 $note',
                                  style: GoogleFonts.chivo(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.deepOrange[700],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                      }).toList(),
                    ),
                  ),
                  // Delivery address (delivery orders only)
                  if (isDelivery && deliveryAddress.isNotEmpty)
                    _deliveryAddressBlock(),
                ],
              ),
            ),
          ),
          // Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: waitDuration.inMinutes >= 15
                ? Colors.red[100]
                : statusColor.withValues(alpha: 0.15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.timer,
                  size: 14,
                  color: waitDuration.inMinutes >= 15 ? Colors.red[900] : statusColor,
                ),
                const SizedBox(width: 4),
                Text(
                  waitDuration.inMinutes > 0
                      ? '⏱ ${waitDuration.inMinutes}m ${(waitDuration.inSeconds % 60).toString().padLeft(2, '0')}s'
                      : '⏱ ${waitDuration.inSeconds}s',
                  style: GoogleFonts.chivo(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: waitDuration.inMinutes >= 15 ? Colors.red[900] : statusColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // Action Button — 3 steps: confirm → start preparing → complete
          // (delivery orders stop at "prepared" instead — a manager assigns
          // a delivery agent from the Gym Delivery page from there).
          GestureDetector(
            onTap: () {
              if (status == 'pending') {
                onStatusChange('confirmed');
              } else if (status == 'confirmed') {
                onStatusChange('preparing');
              } else if (status == 'preparing') {
                onStatusChange(isDelivery ? 'prepared' : 'completed');
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.green,
              child: Text(
                status == 'pending'
                    ? 'CONFIRM'
                    : status == 'confirmed'
                        ? 'START PREPARING'
                        : (isDelivery ? 'MARK PREPARED' : 'COMPLETE'),
                style: GoogleFonts.chivo(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
