import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_admin_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/kds_empty_state.dart';
import '../utils/new_order_sound.dart';

/// Subscription kitchen/prep view — split out of the former combined
/// subscription_kds_page.dart. Confirmed meals for the selected date, sorted
/// by priority: header totals (to prepare / prepared / pending, split by
/// preference), per-meal checkbox marks it PREPARED, priority stepper.
///
/// No delivery/dispatch concerns here — see subscription_delivery_page.dart.
class SubscriptionChefPage extends StatefulWidget {
  const SubscriptionChefPage({super.key});

  @override
  State<SubscriptionChefPage> createState() => _SubscriptionChefPageState();
}

class _SubscriptionChefPageState extends State<SubscriptionChefPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  // New-meal alert — same ringtone/behavior as the main Kitchen Display
  // (kds_page.dart): loops until the chef taps CONFIRM to acknowledge.
  final NewOrderSound _newMealSound = NewOrderSound();

  /// True after the chef taps CONFIRM to silence the alert. Reset when a
  /// genuinely new meal arrives (onNewMeal fires again).
  bool _soundAcknowledged = false;

  /// Timer to periodically refresh KDS elapsed timers (⏱ Xm)
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    final p = context.read<SubscriptionAdminProvider>();
    p.onNewMeal = _playNewMealSound;
    p.addListener(_stopSoundIfNothingPending);
    p.fetchMeals();
    p.fetchMealLibrary(); // to resolve selected_dish_ids into names/descriptions
    p.startAutoRefresh();
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _playNewMealSound() {
    if (!mounted) return;
    try {
      _soundAcknowledged = false; // new arrival — show CONFIRM again
      _newMealSound.play(loop: true);
      if (mounted) setState(() {});
    } catch (_) {
      // Ignore audio failures — a silent KDS is better than a crash.
    }
  }

  /// Chef taps CONFIRM — silence the alert without changing meal status.
  void _acknowledgeSound() {
    _newMealSound.stop();
    if (mounted) setState(() => _soundAcknowledged = true);
  }

  void _stopSoundIfNothingPending() {
    if (!mounted) return;
    // Respect the chef's explicit acknowledge — don't re-trigger the sound
    // on the next auto-refresh (every 20s) just because meals are still in
    // the queue. The flag resets only when a genuinely NEW meal arrives
    // (_playNewMealSound sets _soundAcknowledged = false).
    if (_soundAcknowledged) return;
    if (!context.read<SubscriptionAdminProvider>().hasMealsAwaitingPrep) {
      _newMealSound.stop();
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _tabs.dispose();
    final p = context.read<SubscriptionAdminProvider>();
    p.onNewMeal = null;
    p.removeListener(_stopSoundIfNothingPending);
    p.stopAutoRefresh();
    super.dispose();
  }

  Widget _dishImageFallback() => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(Icons.fastfood, size: 20, color: Colors.grey[600]),
      );

  Widget _stepperControl({
    required String valueText,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    required bool canDecrement,
    required bool canIncrement,
    bool isCompleted = false,
  }) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green[50] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCompleted ? Colors.green[300]! : Colors.grey[300]!,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: canDecrement ? onDecrement : null,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(7),
              bottomLeft: Radius.circular(7),
            ),
            child: Container(
              width: 32,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green[100] : Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  bottomLeft: Radius.circular(7),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.remove,
                size: 16,
                color: canDecrement ? Colors.black87 : Colors.grey[400],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(
              valueText,
              style: GoogleFonts.chivo(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isCompleted ? Colors.green[900] : Colors.black87,
              ),
            ),
          ),
          InkWell(
            onTap: canIncrement ? onIncrement : null,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(7),
              bottomRight: Radius.circular(7),
            ),
            child: Container(
              width: 32,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green[100] : Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(7),
                  bottomRight: Radius.circular(7),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add,
                size: 16,
                color: canIncrement ? Colors.black87 : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _mealsOf(Map<String, dynamic> m) {
    // A manager can bump today's count above the plan's usual meals_per_day
    // (Today's Meal → edit response) — that per-day override wins here.
    final override = (m['meal_count'] as num?)?.toInt();
    if (override != null) return override;
    final sub = (m['subscriptions'] as Map?)?.cast<String, dynamic>() ?? {};
    final plan =
        (sub['subscription_plans'] as Map?)?.cast<String, dynamic>() ?? {};
    return (plan['meals_per_day'] as num?)?.toInt() ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionAdminProvider>();
    final isManager =
        ['admin', 'developer', 'sub_manager'].contains(adminAuth.role);

    // 'confirmed' orders only show up here once a manager has pushed them
    // from the Today's Meal review page — see subscription_today_page.dart.
    // 'preparing'/'prepared' are already past that gate by definition.
    final active = p.meals
        .where((m) =>
            ['confirmed', 'preparing', 'prepared'].contains(m['status']) &&
            (m['status'] != 'confirmed' || m['pushed_to_kitchen'] == true))
        .toList();
    // Once fully prepared, an order moves out of the working queue entirely
    // — into its own tab — instead of sitting mixed in with what's still
    // being cooked.
    final toPrepareList =
        active.where((m) => m['status'] != 'prepared').toList();
    final preparedList =
        active.where((m) => m['status'] == 'prepared').toList();

    // Totals for the kitchen header.
    int toPrepare = 0, prepared = 0;
    final byPref = <String, int>{};
    // Veg/non-veg headcount by mealtime — a whole-day veg/non-veg member
    // counts toward both morning and evening; a mixed member counts toward
    // whichever slot their morning_preference/evening_preference says.
    int morningVeg = 0, morningNonVeg = 0, eveningVeg = 0, eveningNonVeg = 0;
    int wholeDayVeg = 0, wholeDayNonVeg = 0;
    for (final m in active) {
      final sub = (m['subscriptions'] as Map?)?.cast<String, dynamic>() ?? {};
      // Excluded from the kitchen's aggregate totals — a developer's test
      // member still shows up as a card below (so the prep/dispatch flow is
      // actually exercisable), just not in the real prep-count math.
      if (sub['is_test'] == true) continue;
      final n = _mealsOf(m);
      toPrepare += n;
      prepared += (m['prepared_count'] as num?)?.toInt() ?? 0;
      final prefKey = (sub['food_preference'] ?? 'other') as String;
      byPref[prefKey] = (byPref[prefKey] ?? 0) + n;

      if (prefKey == 'mixed') {
        final morning = (sub['morning_preference'] ?? '') as String;
        final evening = (sub['evening_preference'] ?? '') as String;
        if (morning == 'veg') {
          morningVeg++;
        } else if (morning == 'non_veg') {
          morningNonVeg++;
        }
        if (evening == 'veg') {
          eveningVeg++;
        } else if (evening == 'non_veg') {
          eveningNonVeg++;
        }
      } else if (prefKey == 'veg') {
        wholeDayVeg++;
        morningVeg++;
        eveningVeg++;
      } else if (prefKey == 'non_veg') {
        wholeDayNonVeg++;
        morningNonVeg++;
        eveningNonVeg++;
      }
    }
    final pendingCount = toPrepare - prepared;

    final d = p.kdsDate;
    final dateLabel =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('🥗 SUBSCRIPTION KITCHEN',
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
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            tooltip: 'Logout',
            onPressed: () async {
              await adminAuth.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.black87,
          indicatorColor: Colors.black87,
          labelStyle: GoogleFonts.chivo(fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: 'TO PREPARE (${toPrepareList.length})'),
            Tab(text: 'PREPARED (${preparedList.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          Column(
            children: [
              _summaryBar(toPrepare, prepared, pendingCount, byPref, {
                'MORNING VEG': morningVeg,
                'MORNING NON-VEG': morningNonVeg,
                'EVENING VEG': eveningVeg,
                'EVENING NON-VEG': eveningNonVeg,
                'WHOLE-DAY VEG': wholeDayVeg,
                'WHOLE-DAY NON-VEG': wholeDayNonVeg,
              }),
              Expanded(
                child: toPrepareList.isEmpty
                    ? KdsEmptyState(message: 'No confirmed meals for $dateLabel')
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: toPrepareList.length,
                        itemBuilder: (_, i) => _kitchenCard(p, toPrepareList[i]),
                      ),
              ),
            ],
          ),
          preparedList.isEmpty
              ? KdsEmptyState(message: 'Nothing prepared yet for $dateLabel')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: preparedList.length,
                  itemBuilder: (_, i) => _kitchenCard(p, preparedList[i]),
                ),
        ],
      ),
    );
  }

  Widget _summaryBar(int toPrepare, int prepared, int pending,
      Map<String, int> byPref, Map<String, int> vegBreakdown) {
    Widget stat(String label, String value, Color color) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(value,
                    style: GoogleFonts.chivo(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text(label,
                    style: GoogleFonts.chivo(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[700],
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              stat('TO PREPARE', '$toPrepare', Colors.blue[800]!),
              stat('PREPARED', '$prepared', Colors.green[700]!),
              stat('PENDING', '$pending', Colors.red[700]!),
            ],
          ),
          if (byPref.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: byPref.entries.map((e) {
                  // Members can each have a different assigned dish now, so
                  // there's no single "the dish" for a preference — count only.
                  final label = e.key.replaceAll('_', '-').toUpperCase();
                  return Chip(
                    label: Text('$label × ${e.value}',
                        style: GoogleFonts.chivo(
                            fontSize: 11, fontWeight: FontWeight.w800)),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),
          if (vegBreakdown.values.any((v) => v > 0))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: vegBreakdown.entries
                    .where((e) => e.value > 0)
                    .map((e) => Chip(
                          label: Text('${e.key} × ${e.value}',
                              style: GoogleFonts.chivo(
                                  fontSize: 11, fontWeight: FontWeight.w800)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: e.key.contains('NON-VEG')
                              ? Colors.orange[50]
                              : Colors.green[50],
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _setPrepared(
      SubscriptionAdminProvider p, String id, int total, int newCount) {
    final clamped = newCount.clamp(0, total);
    final fullyDone = clamped >= total;
    p.updateMeal(id, {
      'prepared_count': clamped,
      'status': fullyDone ? 'prepared' : 'confirmed',
      if (fullyDone) 'prepared_at': DateTime.now().toIso8601String(),
    });
    // Immediately silence the ringtone when a meal is fully prepared —
    // don't wait for the async fetchMeals() → listener chain.
    if (fullyDone) _newMealSound.stop();
  }

  /// One-tap "mark all done" — sets prepared_count = total and status to
  /// 'prepared'. For single-meal orders this is the primary action; for
  /// multi-meal orders it's a shortcut to skip the +/- stepper.
  void _markAllPrepared(
      SubscriptionAdminProvider p, String id, int total) {
    _setPrepared(p, id, total, total);
  }

  Widget _kitchenCard(SubscriptionAdminProvider p, Map<String, dynamic> m) {
    final sub = (m['subscriptions'] as Map?)?.cast<String, dynamic>() ?? {};
    final manual = (m['manual_subscription_entries'] as Map?)?.cast<String, dynamic>() ?? {};
    final reply = (m['reply_text'] as String?)?.trim() ?? '';
    final rawName = (sub['customer_name'] as String?)?.trim() ??
        (manual['customer_name'] as String?)?.trim() ??
        (reply.isNotEmpty && reply.toLowerCase() != 'manual entry' ? reply : '');
    final isManual = manual.isNotEmpty || (m['manual_entry_id'] != null) || m['subscription_id'] == null;
    final customerName = rawName.isNotEmpty ? rawName : (isManual ? 'Walk-in Customer' : 'Member');
    final total = _mealsOf(m);
    final done = (m['prepared_count'] as num?)?.toInt() ?? 0;
    final priority = (m['priority'] as num?)?.toInt() ?? 0;
    final isPrepared = m['status'] == 'prepared';
    final pushedAtStr = (m['pushed_at'] ?? m['created_at']) as String?;
    final pushedAt = pushedAtStr != null ? DateTime.tryParse(pushedAtStr) : null;
    final prefKey = (sub['food_preference'] ?? '') as String;
    final pref = prefKey.replaceAll('_', '-').toUpperCase();
    final notes = (sub['health_notes'] ?? '') as String;
    final replyText = (m['reply_text'] ?? '').toString();
    // This member's own assigned dish (Meal Planner → ASSIGN tab) — a single
    // legacy default. Overridden by selected_dish_ids (Today's Meal → edit
    // response) when a manager picked specific dishes for this order.
    final assignedDish = (m['subscription_meals'] as Map?)?.cast<String, dynamic>();
    final pickedDishIds = ((m['selected_dish_ids'] as List?) ?? []).cast<String>();
    final rawDishes = pickedDishIds.isNotEmpty
        ? pickedDishIds
            // Never silently drop an id that fails to resolve (e.g. a dish
            // deactivated/deleted after being picked) — the chef still needs
            // to see *something* was ordered here, not a shorter list.
            .map((id) => p.mealLibrary.firstWhere((d) => d['id'] == id,
                orElse: () => {'id': id, 'name': 'Unknown dish', 'image_url': null}))
            .toList()
        : (assignedDish != null ? [assignedDish] : <Map<String, dynamic>>[]);
    // Group identical dishes into a qty (e.g. the same dish picked for both
    // of a member's 2 meals shows once as "2x", not two separate lines).
    final dishQty = <String, int>{};
    final dishById = <String, Map<String, dynamic>>{};
    for (final d in rawDishes) {
      final id = (d['id'] ?? d['name']).toString();
      dishQty[id] = (dishQty[id] ?? 0) + 1;
      dishById[id] = d;
    }
    final dishes = dishById.values.toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isPrepared
              ? Colors.green
              : priority > 0
                  ? Colors.red
                  : Colors.grey[300]!,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // DISH first — image + qty×name per item, same pattern as
                  // the Gym KDS order card — this is what the chef actually
                  // needs to read at a glance. Customer identity is
                  // secondary, pushed below for order/delivery matching only.
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: prefKey == 'non_veg'
                              ? Colors.orange[100]
                              : Colors.green[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(pref.isEmpty ? '—' : pref,
                            style: GoogleFonts.chivo(
                                fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                      if (priority == 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red[100],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red[300]!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.priority_high,
                                    size: 12, color: Colors.red[900]),
                                const SizedBox(width: 2),
                                Text('P1 HIGH',
                                    style: GoogleFonts.chivo(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.red[900])),
                              ],
                            ),
                          ),
                        )
                      else if (priority == 2)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('P2',
                                style: GoogleFonts.chivo(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.orange[900])),
                          ),
                        )
                      else if (priority == 3)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('P3',
                                style: GoogleFonts.chivo(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey[700])),
                          ),
                        ),
                      const Spacer(),
                      if (!isPrepared && pushedAt != null)
                        Builder(builder: (_) {
                          final utcNow = DateTime.now().toUtc();
                          final utcStart = pushedAt.isUtc ? pushedAt : pushedAt.toUtc();
                          final diff = utcNow.difference(utcStart);
                          final elapsed = diff.isNegative ? Duration.zero : diff;
                          final mins = elapsed.inMinutes;
                          final secs = elapsed.inSeconds % 60;
                          final isUrgent = mins >= 10;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isUrgent ? Colors.red[50] : Colors.amber[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: isUrgent
                                      ? Colors.red[300]!
                                      : Colors.amber[300]!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer,
                                    size: 11,
                                    color: isUrgent
                                        ? Colors.red[700]
                                        : Colors.amber[900]),
                                const SizedBox(width: 3),
                                Text(
                                  mins > 0
                                      ? '${mins}m ${secs.toString().padLeft(2, '0')}s'
                                      : '${secs}s',
                                  style: GoogleFonts.chivo(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: isUrgent
                                        ? Colors.red[800]
                                        : Colors.amber[950],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (dishes.isEmpty)
                    Text('No dish assigned',
                        style: GoogleFonts.chivo(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[500]))
                  else
                    for (int i = 0; i < dishes.length; i++) ...[
                      Builder(builder: (_) {
                        final d = dishes[i];
                        final dishTime = p.getDishDeliveryTime(m['delivery_time'], i);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: (d['image_url'] as String?) != null &&
                                        (d['image_url'] as String).isNotEmpty
                                    ? Image.network(
                                        d['image_url'] as String,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _dishImageFallback(),
                                      )
                                    : _dishImageFallback(),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${dishQty[(d['id'] ?? d['name']).toString()]}x ${d['name']}',
                                            style: GoogleFonts.chivo(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.black87),
                                          ),
                                        ),
                                        if (dishTime.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue[50],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: Colors.blue[200]!),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.schedule,
                                                    size: 10,
                                                    color: Colors.blue),
                                                const SizedBox(width: 3),
                                                Text(
                                                  dishTime,
                                                  style: GoogleFonts.chivo(
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: Colors.blue[900],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if ((d['description'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(d['description'] as String,
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.grey[700])),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  if (replyText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('📝 $replyText',
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              color: Colors.indigo[800])),
                    ),
                  if (notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('⚠ $notes',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.deepOrange[800])),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$customerName${(sub['member_code'] as String?)?.isNotEmpty == true ? '  ${sub['member_code']}' : (isManual ? '  (Manual)' : '')}'
                          ' · $total meal${total > 1 ? 's' : ''}',
                          style: GoogleFonts.inter(
                              fontSize: 11.5, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (sub['is_test'] == true)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple[100],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('TEST',
                                style: GoogleFonts.chivo(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.purple[900])),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Dish completion stepper & PREPARED action
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── CONFIRM button — silence the alert sound ──────────
                if (!isPrepared && !_soundAcknowledged)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: Colors.orange[700],
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: _acknowledgeSound,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Text('CONFIRM',
                              style: GoogleFonts.chivo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.5)),
                        ),
                      ),
                    ),
                  ),

                // ── Dish completion stepper (Image 1 style) ───────────
                _stepperControl(
                  valueText: '$done / $total',
                  onDecrement: () =>
                      _setPrepared(p, m['id'] as String, total, done - 1),
                  onIncrement: () =>
                      _setPrepared(p, m['id'] as String, total, done + 1),
                  canDecrement: done > 0,
                  canIncrement: done < total,
                  isCompleted: isPrepared,
                ),

                const SizedBox(height: 8),

                // ── PREPARED shortcut button / status ─────────────────
                if (!isPrepared)
                  Material(
                    color: Colors.green[700],
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () =>
                          _markAllPrepared(p, m['id'] as String, total),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle,
                                size: 15, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('PREPARED',
                                style: GoogleFonts.chivo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            size: 14, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text('READY',
                            style: GoogleFonts.chivo(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.green[800])),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
