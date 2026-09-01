import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_admin_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/new_order_sound.dart';
import '../widgets/delivery_orders_list.dart';

/// Subscription delivery/dispatch view — prepared meals: assign a delivery agent,
/// view items to deliver, collect payment (Cash / UPI QR), and move through
/// out_for_delivery → delivered.
///
/// Features sound alerting on new prepared meals ready for pickup and a CONFIRM
/// button to acknowledge and silence alerts.
class SubscriptionDeliveryPage extends StatefulWidget {
  const SubscriptionDeliveryPage({super.key});

  @override
  State<SubscriptionDeliveryPage> createState() =>
      _SubscriptionDeliveryPageState();
}

class _SubscriptionDeliveryPageState extends State<SubscriptionDeliveryPage> {
  final NewOrderSound _deliverySound = NewOrderSound();
  bool _soundAcknowledged = false;
  Set<String> _knownPreparedIds = {};
  bool _baselineSet = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<SubscriptionAdminProvider>();
    p.fetchMeals();
    p.fetchEditors(); // delivery agents for the assignment dropdown
    p.fetchManualEntries();
    p.fetchMealLibrary();
    p.addListener(_checkPreparedMeals);
    p.startAutoRefresh();
  }

  void _checkPreparedMeals() {
    if (!mounted) return;
    final p = context.read<SubscriptionAdminProvider>();
    final prepared = p.meals
        .where((m) => m['status'] == 'prepared')
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .toSet();

    if (!_baselineSet) {
      _knownPreparedIds = prepared;
      _baselineSet = true;
      if (prepared.isNotEmpty && !_soundAcknowledged) {
        _deliverySound.play(loop: true);
      }
      return;
    }

    final hasNewPrepared = prepared.any((id) => !_knownPreparedIds.contains(id));
    _knownPreparedIds = prepared;

    if (hasNewPrepared) {
      _soundAcknowledged = false;
      _deliverySound.play(loop: true);
      setState(() {});
    } else if (prepared.isEmpty) {
      _deliverySound.stop();
      _soundAcknowledged = false;
      setState(() {});
    }
  }

  void _acknowledgeSound() {
    setState(() => _soundAcknowledged = true);
    _deliverySound.stop();
  }

  @override
  void dispose() {
    _deliverySound.stop();
    final p = context.read<SubscriptionAdminProvider>();
    p.removeListener(_checkPreparedMeals);
    p.stopAutoRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionAdminProvider>();
    final isManager =
        ['admin', 'developer', 'sub_manager'].contains(adminAuth.role);

    final d = p.kdsDate;
    final dateLabel =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final preparedCount =
        p.meals.where((m) => m['status'] == 'prepared').length;
    final isAlerting = preparedCount > 0 && !_soundAcknowledged;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('🚚 SUBSCRIPTION DELIVERY',
            style:
                GoogleFonts.chivo(fontSize: 20, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: isManager
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => context.go('/subs'),
              )
            : null,
        actions: [
          if (isAlerting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _acknowledgeSound,
                icon: const Icon(Icons.volume_off, size: 16),
                label: Text('CONFIRM (STOP SOUND)',
                    style: GoogleFonts.chivo(
                        fontSize: 12, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: p.kdsDate,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 7)),
              );
              if (picked != null) p.setKdsDate(picked);
            },
            icon: const Icon(Icons.calendar_today,
                size: 18, color: Colors.black87),
            label: Text(dateLabel,
                style: GoogleFonts.chivo(
                    fontWeight: FontWeight.w800, color: Colors.black87)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: p.fetchMeals,
          ),
        ],
      ),
      body: DeliveryOrdersList(provider: p, isManager: isManager),
    );
  }
}
