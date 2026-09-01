import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/subscription_admin_provider.dart';
import 'add_agent_dialog.dart';
import 'kds_empty_state.dart';

/// Prepared meals ready for dispatch: assign a delivery agent, view items to deliver,
/// collect payment (Direct Dynamic UPI QR / Cash / Razorpay), and move through out_for_delivery → delivered.
///
/// Separated into ACTIVE DELIVERIES and COMPLETED tabs so completed orders automatically
/// move into the completed section once marked delivered.
class DeliveryOrdersList extends StatefulWidget {
  final SubscriptionAdminProvider provider;
  final bool isManager;

  const DeliveryOrdersList(
      {super.key, required this.provider, required this.isManager});

  @override
  State<DeliveryOrdersList> createState() => _DeliveryOrdersListState();
}

class _DeliveryOrdersListState extends State<DeliveryOrdersList>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  SubscriptionAdminProvider get provider => widget.provider;
  bool get isManager => widget.isManager;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeDeliveries = provider.meals
        .where((m) => ['prepared', 'out_for_delivery'].contains(m['status']))
        .toList();
    final completedDeliveries = provider.meals
        .where((m) => m['status'] == 'delivered')
        .toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.black87,
                  indicatorColor: Colors.black87,
                  indicatorWeight: 3,
                  labelStyle: GoogleFonts.chivo(
                      fontWeight: FontWeight.w800, fontSize: 12.5),
                  unselectedLabelColor: Colors.grey[600],
                  tabs: [
                    Tab(text: 'ACTIVE DELIVERIES (${activeDeliveries.length})'),
                    Tab(text: 'COMPLETED (${completedDeliveries.length})'),
                  ],
                ),
              ),
              if (isManager) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () =>
                      showAddAgentDialog(context, onAdd: provider.addAgent),
                  icon: const Icon(Icons.person_add, size: 18),
                  label: Text('NEW AGENT',
                      style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Active Deliveries (Prepared & Out for Delivery)
              activeDeliveries.isEmpty
                  ? const KdsEmptyState(
                      message: 'No active deliveries in queue')
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: activeDeliveries.length,
                      itemBuilder: (_, i) =>
                          _deliveryCard(context, activeDeliveries[i]),
                    ),
              // Completed Deliveries (Delivered)
              completedDeliveries.isEmpty
                  ? const KdsEmptyState(
                      message: 'No completed deliveries yet')
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: completedDeliveries.length,
                      itemBuilder: (_, i) =>
                          _deliveryCard(context, completedDeliveries[i]),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDeliveryTimeHeader(String raw) {
    final str = raw.trim();
    if (str.isEmpty) return '';
    if (str.startsWith('{')) {
      try {
        final map = jsonDecode(str) as Map;
        final times = map.values
            .map((v) => v?.toString().trim())
            .where((v) => v != null && v.isNotEmpty)
            .toList();
        if (times.isEmpty) return '';
        return times.join(', ');
      } catch (_) {}
    }
    return str;
  }

  /// Delivery-address block with street / landmark / city and maps navigation link.
  Widget _deliveryAddressBlock(Map<String, dynamic> deliveryAddress) {
    final street = (deliveryAddress['address'] ?? '').toString();
    final landmark = (deliveryAddress['landmark'] ?? '').toString();
    final city = (deliveryAddress['city'] ?? '').toString();
    final pincode = (deliveryAddress['pincode'] ?? '').toString();
    final cityLine = [city, pincode].where((v) => v.isNotEmpty).join(' — ');
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: Color(0xFF1565C0)),
              const SizedBox(width: 4),
              Text(
                'DELIVER TO',
                style: GoogleFonts.chivo(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1565C0),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (street.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              street,
              style: GoogleFonts.chivo(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
            const SizedBox(height: 6),
            InkWell(
              onTap: () => launchUrl(Uri.parse(mapsUrl),
                  mode: LaunchMode.externalApplication),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation,
                      size: 13, color: Color(0xFF1565C0)),
                  const SizedBox(width: 4),
                  Text('OPEN IN GOOGLE MAPS',
                      style: GoogleFonts.chivo(
                          fontSize: 10.5,
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

  Widget _deliveryCard(BuildContext context, Map<String, dynamic> m) {
    final sub = (m['subscriptions'] as Map?)?.cast<String, dynamic>() ?? {};
    final manual =
        (m['manual_subscription_entries'] as Map?)?.cast<String, dynamic>() ?? {};
    final reply = (m['reply_text'] as String?)?.trim() ?? '';

    // Match fallback from manualEntries
    final manualEntry = (manual.isEmpty && m['manual_entry_id'] != null)
        ? provider.manualEntries.firstWhere(
            (e) => e['id'] == m['manual_entry_id'],
            orElse: () => const {},
          )
        : (manual.isNotEmpty
            ? manual
            : (provider.manualEntries.isNotEmpty
                ? provider.manualEntries.firstWhere(
                    (e) => e['id'] == m['manual_entry_id'],
                    orElse: () => const {},
                  )
                : const {}));

    final rawName = (sub['customer_name'] as String?)?.trim() ??
        (manualEntry['customer_name'] as String?)?.trim() ??
        (reply.isNotEmpty && reply.toLowerCase() != 'manual entry' ? reply : '');
    final isManual = manualEntry.isNotEmpty ||
        (m['manual_entry_id'] != null) ||
        m['subscription_id'] == null;
    final customerName =
        rawName.isNotEmpty ? rawName : (isManual ? 'Walk-in Customer' : 'Member');
    final phone = (sub['phone'] as String?)?.trim() ??
        (manualEntry['phone'] as String?)?.trim() ??
        '';

    final address =
        (sub['delivery_address'] as Map?)?.cast<String, dynamic>() ?? {};
    final status = (m['status'] ?? '') as String;
    final agentId = m['delivery_agent_id'] as String?;
    final activeAgents =
        provider.agents.where((a) => a['active'] != false).toList();

    if (agentId != null && !activeAgents.any((a) => a['id'] == agentId)) {
      final match = provider.agents.where((a) => a['id'] == agentId);
      if (match.isNotEmpty) activeAgents.add(match.first);
    }

    final totalMeals = (m['meal_count'] as num?)?.toInt() ?? 1;
    final prefKey = (sub['food_preference'] ?? '') as String;
    final pref = prefKey.replaceAll('_', '-').toUpperCase();
    final healthNotes = ((sub['health_notes'] as String?) ??
            (manualEntry['notes'] as String?) ??
            '')
        .trim();
    final deliveryTime = (m['delivery_time'] ?? '') as String;
    final priority = (m['priority'] as num?)?.toInt() ?? 2;

    // Resolve dish names from library
    final pickedDishIds =
        ((m['selected_dish_ids'] as List?) ?? []).cast<String>();
    final assignedDish =
        (m['subscription_meals'] as Map?)?.cast<String, dynamic>();
    final dishNames = pickedDishIds.isNotEmpty
        ? pickedDishIds
            .map((dishId) => provider.mealLibrary.firstWhere(
                (d) => d['id'] == dishId,
                orElse: () => const {})['name'])
            .whereType<String>()
            .toList()
        : (assignedDish?['name'] != null
            ? [assignedDish!['name'].toString()]
            : <String>[]);

    // Payment details
    final amount = (manualEntry['amount'] as num?)?.toDouble() ??
        (m['payment_amount'] as num?)?.toDouble() ??
        (isManual ? 150.0 : 0.0);
    final paymentStatus =
        (m['payment_status'] ?? (isManual ? 'pending' : 'paid')).toString();
    final paymentMethod =
        (m['payment_method'] ?? (isManual ? 'unpaid' : 'subscription')).toString();
    final isPaid = paymentStatus == 'paid' || !isManual;

    final statusColor = switch (status) {
      'prepared' => Colors.orange[800]!,
      'out_for_delivery' => Colors.blue[800]!,
      _ => Colors.green[700]!,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card Header: Customer Name, Phone & Status Badge ──────
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          customerName,
                          style: GoogleFonts.chivo(
                              fontSize: 16, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isManual) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('MANUAL',
                              style: GoogleFonts.chivo(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.blue[900])),
                        ),
                      ],
                      if (priority == 1) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('P1 HIGH',
                              style: GoogleFonts.chivo(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.red[900])),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status.replaceAll('_', ' ').toUpperCase(),
                      style: GoogleFonts.chivo(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor)),
                ),
              ],
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.phone, size: 13, color: Colors.grey[700]),
                  const SizedBox(width: 4),
                  Text(phone,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800])),
                  Builder(builder: (_) {
                    final formattedTime =
                        _formatDeliveryTimeHeader(deliveryTime);
                    if (formattedTime.isEmpty) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 10),
                        Icon(Icons.schedule, size: 13, color: Colors.blue[800]),
                        const SizedBox(width: 4),
                        Text('Time: $formattedTime',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[900])),
                      ],
                    );
                  }),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // ── What They Are Delivering (Dishes & Items Block) ────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.restaurant,
                          size: 14, color: Colors.black87),
                      const SizedBox(width: 6),
                      Text(
                        'ITEMS TO DELIVER ($totalMeals MEAL${totalMeals > 1 ? 'S' : ''})',
                        style: GoogleFonts.chivo(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (pref.isNotEmpty) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(pref,
                              style: GoogleFonts.chivo(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (dishNames.isNotEmpty)
                    for (int i = 0; i < dishNames.length; i++) ...[
                      Builder(builder: (_) {
                        final d = dishNames[i];
                        final dishTime = provider.getDishDeliveryTime(
                            m['delivery_time'], i);
                        return Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(d,
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87)),
                              ),
                              if (dishTime.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    dishTime,
                                    style: GoogleFonts.chivo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.blue[900],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ]
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 2),
                      child: Text(
                        '• Standard Meal Package',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Colors.black87),
                      ),
                    ),
                  if (healthNotes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        '⚠ Notes: $healthNotes',
                        style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepOrange[800]),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (address.isNotEmpty) ...[
              const SizedBox(height: 8),
              _deliveryAddressBlock(address),
            ],

            const SizedBox(height: 10),

            // ── Payment Status Banner (For Manual Entries / COD) ───────
            if (isManual)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isPaid ? Colors.green[50] : Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isPaid ? Colors.green[200]! : Colors.amber[300]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPaid ? Icons.check_circle : Icons.payment,
                      size: 16,
                      color: isPaid ? Colors.green[800] : Colors.amber[900],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isPaid
                            ? 'PAID (₹${amount.toStringAsFixed(0)} via ${paymentMethod.toUpperCase()})'
                            : 'PAYMENT TO COLLECT: ₹${amount.toStringAsFixed(0)}',
                        style: GoogleFonts.chivo(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isPaid ? Colors.green[900] : Colors.amber[900],
                        ),
                      ),
                    ),
                    if (!isPaid)
                      ElevatedButton.icon(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => PaymentCollectionDialog(
                            provider: provider,
                            mealId: m['id'] as String,
                            customerName: customerName,
                            phone: phone,
                            amount: amount,
                            manualEntryId: m['manual_entry_id'] as String?,
                          ),
                        ),
                        icon: const Icon(Icons.qr_code, size: 14),
                        label: Text('COLLECT',
                            style: GoogleFonts.chivo(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                  ],
                ),
              ),

            // ── Bottom Action Row: Agent Assignment & Dispatch Buttons ─
            Row(
              children: [
                if (isManager)
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
                      onChanged: status != 'delivered'
                          ? (v) => provider.assignAgent(m['id'] as String, v)
                          : null,
                      decoration: const InputDecoration(
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.two_wheeler,
                            size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          agentId != null
                              ? 'Assigned: ${activeAgents.firstWhere((a) => a['id'] == agentId, orElse: () => {'name': 'Delivery Staff'})['name']}'
                              : 'Ready for Pickup',
                          style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 10),
                if (status == 'prepared')
                  ElevatedButton.icon(
                    onPressed: (isManager && agentId == null)
                        ? null
                        : () => provider.setMealStatus(
                            m['id'] as String, 'out_for_delivery'),
                    icon: const Icon(Icons.directions_bike, size: 16),
                    label: Text(isManager ? 'SEND OUT' : 'PICK UP',
                        style: GoogleFonts.chivo(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                  )
                else if (status == 'out_for_delivery')
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!isPaid) {
                        showDialog(
                          context: context,
                          builder: (_) => PaymentCollectionDialog(
                            provider: provider,
                            mealId: m['id'] as String,
                            customerName: customerName,
                            phone: phone,
                            amount: amount,
                            manualEntryId: m['manual_entry_id'] as String?,
                          ),
                        );
                      } else {
                        provider.setMealStatus(
                            m['id'] as String, 'delivered');
                      }
                    },
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: Text(isPaid ? 'DELIVERED' : 'PAY & DELIVER',
                        style: GoogleFonts.chivo(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                  )
                else
                  Builder(builder: (_) {
                    final deliveredAtStr = m['delivered_at'] as String?;
                    final deliveredAt = deliveredAtStr != null
                        ? DateTime.tryParse(deliveredAtStr)?.toLocal()
                        : null;
                    final timeStr = deliveredAt != null
                        ? '${deliveredAt.hour.toString().padLeft(2, '0')}:${deliveredAt.minute.toString().padLeft(2, '0')}'
                        : '';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green[300]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle,
                              size: 16, color: Colors.green[700]),
                          const SizedBox(width: 6),
                          Text(
                            timeStr.isNotEmpty
                                ? 'DELIVERED · $timeStr'
                                : 'DELIVERED',
                            style: GoogleFonts.chivo(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.green[900],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Direct Dynamic UPI QR & Cash Payment Collection Dialog
class PaymentCollectionDialog extends StatefulWidget {
  final SubscriptionAdminProvider provider;
  final String mealId;
  final String customerName;
  final String phone;
  final double amount;
  final String? manualEntryId;

  const PaymentCollectionDialog({
    super.key,
    required this.provider,
    required this.mealId,
    required this.customerName,
    required this.phone,
    required this.amount,
    this.manualEntryId,
  });

  @override
  State<PaymentCollectionDialog> createState() =>
      _PaymentCollectionDialogState();
}

class _PaymentCollectionDialogState extends State<PaymentCollectionDialog> {
  late TextEditingController _upiController;
  final TextEditingController _utrController = TextEditingController();
  bool _editingUpi = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _upiController = TextEditingController(text: widget.provider.storeUpiId);
    _loadStoreUpi();
  }

  Future<void> _loadStoreUpi() async {
    try {
      final upi = await widget.provider.fetchStoreUpiId();
      if (mounted && upi.isNotEmpty) {
        setState(() => _upiController.text = upi);
      }
    } catch (_) {}
  }

  Future<void> _saveUpi(String newUpi) async {
    final clean = newUpi.trim();
    if (clean.isEmpty) return;
    setState(() => _isSaving = true);
    await widget.provider.saveStoreUpiId(clean);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('delivery_merchant_upi_id', clean);
    if (mounted) {
      setState(() {
        _isSaving = false;
        _editingUpi = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Store UPI ID updated to $clean ✅'),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }

  @override
  void dispose() {
    _upiController.dispose();
    _utrController.dispose();
    super.dispose();
  }

  /// Standard NPCI compliant Direct UPI Payment String
  /// Directly opens GPay, PhonePe, Paytm, CRED with payee & exact amount pre-filled!
  String get _directUpiUrl {
    final vpa = _upiController.text.trim();
    final amt = widget.amount.toStringAsFixed(2);
    return 'upi://pay?pa=$vpa&pn=ProtiBowls&am=$amt&cu=INR&tn=MealDelivery';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.qr_code_scanner, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Collect Payment — ₹${widget.amount.toStringAsFixed(0)}',
                style: GoogleFonts.chivo(
                    fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 390,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Customer: ${widget.customerName}${widget.phone.isNotEmpty ? ' (${widget.phone})' : ''}',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800]),
              ),
              const SizedBox(height: 12),
              TabBar(
                labelColor: Colors.blue[900],
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: Colors.blue[900],
                labelStyle: GoogleFonts.chivo(
                    fontSize: 13, fontWeight: FontWeight.w800),
                tabs: const [
                  Tab(icon: Icon(Icons.qr_code_2), text: 'DIRECT UPI QR'),
                  Tab(icon: Icon(Icons.money), text: 'CASH'),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 340,
                child: TabBarView(
                  children: [
                    // ── Direct NPCI Dynamic UPI QR Tab ─────────────
                    SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // High-contrast Direct Dynamic UPI QR Code
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey[300]!),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: QrImageView(
                              data: _directUpiUrl,
                              version: QrVersions.auto,
                              size: 135.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('Scan with GPay / PhonePe / Paytm / CRED',
                              style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800])),

                          // Store UPI ID Display & Inline Edit Option
                          if (!_editingUpi)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Payee UPI: ${_upiController.text}',
                                    style: GoogleFonts.chivo(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.blue[900]),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 13, color: Colors.blueGrey),
                                    onPressed: () => setState(() => _editingUpi = true),
                                    tooltip: 'Change Store UPI ID',
                                    padding: const EdgeInsets.only(left: 4),
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _upiController,
                                      style: GoogleFonts.inter(fontSize: 12),
                                      decoration: const InputDecoration(
                                        hintText: 'Enter Store UPI (e.g. 8660368845@ybl)',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.check, size: 16, color: Colors.green),
                                    onPressed: () => _saveUpi(_upiController.text),
                                  ),
                                ],
                              ),
                            ),

                          // Action Buttons: Open UPI App & Copy Link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: () => launchUrl(
                                  Uri.parse(_directUpiUrl),
                                  mode: LaunchMode.externalApplication,
                                ),
                                icon: const Icon(Icons.open_in_new, size: 13),
                                label: Text('OPEN UPI APP',
                                    style: GoogleFonts.chivo(fontSize: 11, fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 6),
                              TextButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _directUpiUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('UPI Intent Link copied to clipboard 📋'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 13),
                                label: Text('COPY LINK',
                                    style: GoogleFonts.chivo(fontSize: 11, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving
                                  ? null
                                  : () async {
                                      setState(() => _isSaving = true);
                                      final nav = Navigator.of(context);
                                      final messenger = ScaffoldMessenger.of(context);
                                      final err = await widget.provider.recordPayment(
                                        widget.mealId,
                                        method: 'upi',
                                        amount: widget.amount,
                                        manualEntryId: widget.manualEntryId,
                                      );
                                      nav.pop();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(err ??
                                              'UPI payment of ₹${widget.amount.toStringAsFixed(0)} confirmed & order marked delivered ✅'),
                                          backgroundColor: err == null
                                              ? Colors.green[700]
                                              : Colors.red[700],
                                        ),
                                      );
                                    },
                              label: _isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : Text('CONFIRM UPI PAYMENT RECEIVED',
                                      style: GoogleFonts.chivo(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800)),
                              icon: _isSaving
                                  ? const SizedBox.shrink()
                                  : const Icon(Icons.verified, size: 16),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[800],
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Cash Payment Tab ───────────────────────────
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.payments_outlined,
                            size: 54, color: Colors.green[700]),
                        const SizedBox(height: 10),
                        Text('₹${widget.amount.toStringAsFixed(0)}',
                            style: GoogleFonts.chivo(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Colors.green[800])),
                        const SizedBox(height: 6),
                        Text('Collect exact cash amount from customer',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving
                                ? null
                                : () async {
                                    setState(() => _isSaving = true);
                                    final nav = Navigator.of(context);
                                    final messenger = ScaffoldMessenger.of(context);
                                    final err = await widget.provider.recordPayment(
                                      widget.mealId,
                                      method: 'cash',
                                      amount: widget.amount,
                                      manualEntryId: widget.manualEntryId,
                                    );
                                    nav.pop();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(err ??
                                            'Cash payment of ₹${widget.amount.toStringAsFixed(0)} recorded & order marked delivered ✅'),
                                        backgroundColor: err == null
                                            ? Colors.green[700]
                                            : Colors.red[700],
                                      ),
                                    );
                                  },
                            icon: _isSaving
                                ? const SizedBox.shrink()
                                : const Icon(Icons.check, size: 16),
                            label: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : Text('CONFIRM CASH RECEIVED',
                                    style: GoogleFonts.chivo(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL',
                style: GoogleFonts.chivo(
                    fontWeight: FontWeight.w800, color: Colors.grey[700])),
          ),
        ],
      ),
    );
  }
}
