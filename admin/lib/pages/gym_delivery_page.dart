import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/admin_orders_provider.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/add_agent_dialog.dart';

/// GYM DELIVERY — prepared delivery orders wait here for a manager to assign
/// a delivery agent, then move through in_transit → delivered. Mirrors the
/// subscription model's Delivery page/DeliveryOrdersList, adapted to the
/// `orders` table. Fed by the KDS: a delivery order's final button there is
/// MARK PREPARED (not COMPLETE), which lands it here.
class GymDeliveryPage extends StatefulWidget {
  const GymDeliveryPage({super.key});

  @override
  State<GymDeliveryPage> createState() => _GymDeliveryPageState();
}

class _GymDeliveryPageState extends State<GymDeliveryPage> {
  // Same `service_hours.delivery.enabled` flag the customer order form
  // checks (ServiceHoursService.isAvailable('delivery')) — surfaced here too
  // so a delivery manager can kill delivery without hunting through Settings.
  bool _deliveryEnabled = true;
  bool _deliveryLoaded = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AdminOrdersProvider>();
    // Deferred to a microtask — fetchOrders() notifies listeners
    // synchronously (before its first await), which trips Flutter's
    // "notify during build" assertion when called directly from initState.
    Future.microtask(() {
      if (!mounted) return;
      p.fetchOrders();
      p.fetchAgents();
      _loadDeliveryEnabled();
    });
    p.startAutoRefresh();
  }

  Future<void> _loadDeliveryEnabled() async {
    try {
      final res = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', 'service_hours')
          .maybeSingle();
      final v = (res?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      final delivery = (v['delivery'] as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted) {
        setState(() {
          _deliveryEnabled = (delivery['enabled'] as bool?) ?? true;
          _deliveryLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _deliveryLoaded = true);
    }
  }

  Future<void> _toggleDelivery(bool v) async {
    setState(() => _deliveryEnabled = v); // optimistic
    try {
      final res = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', 'service_hours')
          .maybeSingle();
      final value = (res?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      final delivery = (value['delivery'] as Map?)?.cast<String, dynamic>() ?? {};
      delivery['enabled'] = v;
      value['delivery'] = delivery;
      await SupabaseService.client
          .from('app_config')
          .upsert({'key': 'service_hours', 'value': value}, onConflict: 'key');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(v ? 'Delivery enabled' : 'Delivery disabled'),
          backgroundColor: v ? Colors.green[700] : Colors.red[700],
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deliveryEnabled = !v); // revert
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  @override
  void dispose() {
    context.read<AdminOrdersProvider>().stopAutoRefresh();
    super.dispose();
  }

  Widget _addressBlock(Map<String, dynamic> addr) {
    final street = (addr['address'] ?? '').toString();
    final landmark = (addr['landmark'] ?? '').toString();
    final city = (addr['city'] ?? '').toString();
    final pincode = (addr['pincode'] ?? '').toString();
    final cityLine = [city, pincode].where((v) => v.isNotEmpty).join(' — ');
    final mapsUrl = () {
      final link = (addr['maps_link'] ?? '').toString();
      if (link.isNotEmpty) return link;
      final lat = (addr['latitude'] ?? '').toString();
      final lng = (addr['longitude'] ?? '').toString();
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
              Text('DELIVER TO',
                  style: GoogleFonts.chivo(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1565C0),
                      letterSpacing: 0.5)),
            ],
          ),
          if (street.isNotEmpty)
            Text(street,
                style: GoogleFonts.chivo(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          if (landmark.isNotEmpty)
            Text('Near: $landmark',
                style: GoogleFonts.chivo(fontSize: 11, color: Colors.black54)),
          if (cityLine.isNotEmpty)
            Text(cityLine,
                style: GoogleFonts.chivo(
                    fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
          if (mapsUrl.isNotEmpty) ...[
            const SizedBox(height: 5),
            InkWell(
              onTap: () =>
                  launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation, size: 13, color: Color(0xFF1565C0)),
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

  Widget _orderCard(AdminOrdersProvider p, Map<String, dynamic> order, bool isManager) {
    final customer = order['customer_info'] ?? {};
    final addr = (order['delivery_address'] as Map?)?.cast<String, dynamic>() ??
        (customer['delivery_address'] as Map?)?.cast<String, dynamic>() ??
        {};
    final status = (order['status'] ?? '') as String;
    final agentId = order['delivery_agent_id'] as String?;
    final activeAgents = p.agents.where((a) => a['active'] != false).toList();
    if (agentId != null && !activeAgents.any((a) => a['id'] == agentId)) {
      final match = p.agents.where((a) => a['id'] == agentId);
      if (match.isNotEmpty) activeAgents.add(match.first);
    }
    final statusColor = switch (status) {
      'prepared' => Colors.orange[800]!,
      'in_transit' => Colors.blue[800]!,
      _ => Colors.green[700]!,
    };
    final items = order['items'] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ORDER #${(order['order_number'] ?? order['id'].toString().substring(0, 8)).toString().toUpperCase()}'
                    '  ·  ${customer['name'] ?? 'Guest'}',
                    style: GoogleFonts.chivo(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status.replaceAll('_', ' ').toUpperCase(),
                      style: GoogleFonts.chivo(
                          fontSize: 10, fontWeight: FontWeight.w800, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...(items as List).map((item) {
              final name = item['name'] ?? 'Item';
              final qty = item['quantity'] ?? 1;
              return Text('${qty}x $name',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]));
            }),
            if (addr.isNotEmpty) ...[
              const SizedBox(height: 8),
              _addressBlock(addr),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: agentId,
                    hint: const Text('Assign delivery agent'),
                    isDense: true,
                    items: activeAgents
                        .map((a) => DropdownMenuItem(
                              value: a['id'] as String,
                              child: Text('${a['name']}'),
                            ))
                        .toList(),
                    onChanged: isManager && status != 'delivered'
                        ? (v) => p.assignAgent(order['id'] as String, v)
                        : null,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (status == 'prepared')
                  ElevatedButton(
                    onPressed: agentId == null
                        ? null
                        : () => p.updateOrderStatus(order['id'] as String, 'in_transit'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                    child: Text('SEND OUT', style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                  )
                else if (status == 'in_transit')
                  ElevatedButton(
                    onPressed: () => p.updateOrderStatus(order['id'] as String, 'delivered'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                    child: Text('DELIVERED', style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                  )
                else
                  const Icon(Icons.done_all, color: Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminOrdersProvider>();
    final isManager = ['admin', 'developer', 'gym_manager'].contains(adminAuth.role);

    final forDelivery = p.orders
        .where((o) =>
            (o['order_type'] ?? '').toString().toLowerCase() == 'delivery' &&
            ['prepared', 'in_transit', 'delivered'].contains(o['status']))
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('🚚 GYM DELIVERY',
            style: GoogleFonts.chivo(fontSize: 20, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: isManager
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => context.go('/'),
              )
            : null,
        actions: [
          if (isManager) ...[
            if (_deliveryLoaded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_deliveryEnabled ? 'DELIVERY ON' : 'DELIVERY OFF',
                        style: GoogleFonts.chivo(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _deliveryEnabled
                                ? Colors.green[700]
                                : Colors.red[700])),
                    Switch(
                      value: _deliveryEnabled,
                      activeTrackColor: Colors.green[700],
                      onChanged: _toggleDelivery,
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => showAddAgentDialog(context, onAdd: p.addAgent),
              icon: const Icon(Icons.person_add, size: 18, color: Colors.black87),
              label: Text('AGENT',
                  style: GoogleFonts.chivo(
                      fontWeight: FontWeight.w800, color: Colors.black87)),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: p.fetchOrders,
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
      body: forDelivery.isEmpty
          ? Center(
              child: Text('Nothing ready for delivery yet',
                  style: GoogleFonts.chivo(fontSize: 15, color: Colors.grey[600])),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: forDelivery.length,
              itemBuilder: (_, i) => _orderCard(p, forDelivery[i], isManager),
            ),
    );
  }
}
