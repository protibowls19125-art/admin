import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_admin_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/delivery_orders_list.dart';
import '../widgets/kds_empty_state.dart';

/// TODAY'S MEAL — the manager's review queue between the survey and the
/// kitchen. Confirmed orders sit here (customer, order/preference, delivery
/// time) until explicitly pushed to the Kitchen Display; pushing clears them
/// from this tab. Second tab is PREPARED — same agent-assignment flow as the
/// standalone Delivery page (DeliveryOrdersList), so a manager can go
/// straight from pushing to dispatching without leaving this page.
class SubscriptionTodayPage extends StatefulWidget {
  const SubscriptionTodayPage({super.key});

  @override
  State<SubscriptionTodayPage> createState() => _SubscriptionTodayPageState();
}

class _SubscriptionTodayPageState extends State<SubscriptionTodayPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final p = context.read<SubscriptionAdminProvider>();
    p.setKdsDate(DateTime.now());
    p.fetchMeals();
    p.fetchEditors(); // delivery agents for the PREPARED tab
    p.fetchFoodPreferences(); // dietary categories for the "edit response" dialog
    p.fetchMealLibrary(); // dish catalog for the "edit response" dialog
    p.startAutoRefresh();
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    context.read<SubscriptionAdminProvider>().stopAutoRefresh();
    super.dispose();
  }

  Future<void> _pickDeliveryTime(
      SubscriptionAdminProvider p, String mealId, String current,
      {int? dishIndex}) async {
    TimeOfDay initial = TimeOfDay.now();
    if (current.isNotEmpty) {
      final parsed = _parseTime(current);
      if (parsed != null) initial = parsed;
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    if (!mounted) return;
    if (dishIndex != null) {
      await p.setDishDeliveryTime(mealId, dishIndex, picked.format(context));
    } else {
      await p.setDeliveryTime(mealId, picked.format(context));
    }
  }

  TimeOfDay? _parseTime(String formatted) {
    // Best-effort parse of TimeOfDay.format's own output (e.g. "8:00 AM").
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*([AP]M)?$', caseSensitive: false)
        .firstMatch(formatted.trim());
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    final period = m.group(3)?.toUpperCase();
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  // Lets a manager correct a member's food preference (veg/non-veg/mixed,
  // + morning/evening for mixed) right here before pushing to the kitchen —
  // same admin-manage-member edit_details action the Members page uses,
  // scoped down to just the preference fields relevant at this stage.
  Future<void> _editResponseDialog(
      SubscriptionAdminProvider p, Map<String, dynamic> m) async {
    final sub = (m['subscriptions'] as Map?)?.cast<String, dynamic>() ?? {};
    final manual = (m['manual_subscription_entries'] as Map?)?.cast<String, dynamic>() ?? {};
    final subscriptionId = m['subscription_id'] as String?;
    final reply = (m['reply_text'] as String?)?.trim() ?? '';
    final rawName = (sub['customer_name'] as String?)?.trim() ??
        (manual['customer_name'] as String?)?.trim() ??
        (reply.isNotEmpty && reply.toLowerCase() != 'manual entry' ? reply : '');
    final isManual = manual.isNotEmpty || (m['manual_entry_id'] != null) || m['subscription_id'] == null;
    final customerName = rawName.isNotEmpty ? rawName : (isManual ? 'Walk-in Customer' : 'Member');
    final mealId = m['id'] as String;
    final replyText = (m['reply_text'] ?? '').toString();
    String pref = (sub['food_preference'] ?? '').toString().isNotEmpty
        ? sub['food_preference'] as String
        : (p.foodPreferences.isNotEmpty ? p.foodPreferences.first['key'] as String : 'veg');
    String morning = (sub['morning_preference'] ?? '') as String;
    String evening = (sub['evening_preference'] ?? '') as String;
    int mealCount = (m['meal_count'] as num?)?.toInt() ?? 2;
    // DropdownButtonFormField requires exactly one item matching its value —
    // a member's stored preference can be a legacy key no longer in the
    // admin-configurable list. Keep it selectable rather than crashing.
    final prefOptions = [...p.foodPreferences];
    if (!prefOptions.any((f) => f['key'] == pref)) {
      prefOptions.insert(0, {'key': pref, 'label': pref.replaceAll('_', ' ').toUpperCase()});
    }
    const mealPrefs = ['veg', 'non_veg', 'vegan', 'eggetarian'];
    // 2 is mandatory (the minimum), 3 is the "add a meal" option — but guard
    // against a stray out-of-range stored value the same way as pref above.
    final countOptions = {2, 3, mealCount}.toList()..sort();

    // One dish slot per meal — grows/shrinks with mealCount. Pre-filled from
    // whatever was already picked; extra slots start unset.
    final savedDishIds =
        ((m['selected_dish_ids'] as List?) ?? []).cast<String>();
    List<String?> dishIds = List<String?>.generate(
        mealCount, (i) => i < savedDishIds.length ? savedDishIds[i] : null);
    final activeDishes = p.mealLibrary.where((d) => d['active'] != false).toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text("Edit $customerName's response"),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyText.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CUSTOMER\'S MESSAGE',
                            style: GoogleFonts.chivo(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text('"$replyText"',
                            style: GoogleFonts.inter(
                                fontSize: 13, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<int>(
                  initialValue: mealCount,
                  items: countOptions
                      .map((n) => DropdownMenuItem(
                          value: n, child: Text('$n meals today')))
                      .toList(),
                  onChanged: (v) => setState(() {
                    mealCount = v ?? mealCount;
                    dishIds = List<String?>.generate(mealCount,
                        (i) => i < dishIds.length ? dishIds[i] : null);
                  }),
                  decoration: const InputDecoration(labelText: 'Meal count'),
                ),
                for (int i = 0; i < mealCount; i++) ...[
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    // Guard against a previously-picked dish that's since
                    // been deactivated/deleted — same crash risk as the
                    // preference dropdowns above if its value has no match.
                    final options = [...activeDishes];
                    if (dishIds[i] != null &&
                        !options.any((d) => d['id'] == dishIds[i])) {
                      options.insert(
                          0, {'id': dishIds[i], 'name': '(unavailable dish)'});
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: dishIds[i],
                      items: options
                          .map((d) => DropdownMenuItem(
                                value: d['id'] as String,
                                child: Text(d['name'] as String,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => dishIds[i] = v),
                      decoration: InputDecoration(labelText: 'Dish ${i + 1}'),
                    );
                  }),
                ],
                if (subscriptionId != null) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: pref,
                    items: prefOptions
                        .map((f) => DropdownMenuItem(
                              value: f['key'] as String,
                              child: Text(f['label'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => pref = v ?? pref),
                    decoration: const InputDecoration(labelText: 'Food preference'),
                  ),
                  if (pref == 'mixed') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: mealPrefs.contains(morning) ? morning : null,
                      items: mealPrefs
                          .map((k) => DropdownMenuItem(
                              value: k, child: Text(k.replaceAll('_', '-').toUpperCase())))
                          .toList(),
                      onChanged: (v) => setState(() => morning = v ?? morning),
                      decoration: const InputDecoration(labelText: 'Morning'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: mealPrefs.contains(evening) ? evening : null,
                      items: mealPrefs
                          .map((k) => DropdownMenuItem(
                              value: k, child: Text(k.replaceAll('_', '-').toUpperCase())))
                          .toList(),
                      onChanged: (v) => setState(() => evening = v ?? evening),
                      decoration: const InputDecoration(labelText: 'Evening'),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('SAVE')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    String? err;
    if (subscriptionId != null) {
      err = await p.editMemberDetails(subscriptionId, {
        'customer_name': sub['customer_name'] ?? '',
        'phone': sub['phone'] ?? '',
        'food_preference': pref,
        'morning_preference': pref == 'mixed' ? morning : '',
        'evening_preference': pref == 'mixed' ? evening : '',
        'health_goal': sub['health_goal'] ?? '',
        'health_notes': sub['health_notes'] ?? '',
        'delivery_address': sub['delivery_address'] ?? {},
      });
    }
    // meal_count / selected_dish_ids are per-day fields on meal_confirmations
    // itself, not the member's standing subscription — separate write,
    // RLS-permitted direct update (same path as delivery time / priority).
    if (err == null) {
      // What the member's balance was originally charged when they confirmed:
      // a previous meal_count override (if the manager already edited once),
      // else the plan's default meals_per_day.
      final plan = (sub['subscription_plans'] as Map?)
              ?.cast<String, dynamic>() ??
          {};
      final oldEffective = (m['meal_count'] as num?)?.toInt() ??
          (plan['meals_per_day'] as num?)?.toInt() ??
          1;

      await p.updateMeal(mealId, {
        'meal_count': mealCount,
        'selected_dish_ids': dishIds.whereType<String>().toList(),
      });

      // If the confirmed meal's count changed, correct the balance:
      // positive delta → restore over-deducted meals back to the member,
      // negative delta → deduct the additional meals.
      if (subscriptionId != null && m['status'] == 'confirmed' && mealCount != oldEffective) {
        await p.adjustMealsRemaining(subscriptionId, oldEffective - mealCount);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? 'Response updated ✅'),
      backgroundColor: err == null ? Colors.green[700] : Colors.red[700],
    ));
    if (err == null) p.fetchMeals();
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: GoogleFonts.chivo(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );

  Widget _priorityControl({
    required int priority,
    required ValueChanged<int> onChanged,
  }) {
    final effective = priority == 1 ? 1 : (priority == 3 ? 3 : 2);
    final label = 'P$effective';
    final (bg, border, textCol) = switch (effective) {
      1 => (Colors.red[50]!, Colors.red[300]!, Colors.red[800]!),
      2 => (Colors.orange[50]!, Colors.orange[300]!, Colors.orange[800]!),
      _ => (Colors.blueGrey[50]!, Colors.blueGrey[200]!, Colors.blueGrey[700]!),
    };

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrement (Higher priority -> P1)
          InkWell(
            onTap: effective > 1 ? () => onChanged(effective - 1) : null,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(7),
              bottomLeft: Radius.circular(7),
            ),
            child: Container(
              width: 28,
              height: double.infinity,
              decoration: BoxDecoration(
                color: effective > 1
                    ? border.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  bottomLeft: Radius.circular(7),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.remove,
                size: 14,
                color: effective > 1 ? textCol : Colors.grey[400],
              ),
            ),
          ),
          // Center label (cycles on tap: P1 -> P2 -> P3 -> P1)
          InkWell(
            onTap: () =>
                onChanged(effective == 1 ? 2 : (effective == 2 ? 3 : 1)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              child: Text(
                label,
                style: GoogleFonts.chivo(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: textCol,
                ),
              ),
            ),
          ),
          // Increment (Lower priority -> P3)
          InkWell(
            onTap: effective < 3 ? () => onChanged(effective + 1) : null,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(7),
              bottomRight: Radius.circular(7),
            ),
            child: Container(
              width: 28,
              height: double.infinity,
              decoration: BoxDecoration(
                color: effective < 3
                    ? border.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(7),
                  bottomRight: Radius.circular(7),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add,
                size: 14,
                color: effective < 3 ? textCol : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionAdminProvider>();
    final isManager =
        ['admin', 'developer', 'sub_manager'].contains(adminAuth.role);

    // Confirmed but not yet pushed to the kitchen — this page's review queue.
    final queue = p.meals
        .where((m) =>
            m['status'] == 'confirmed' && m['pushed_to_kitchen'] != true)
        .toList();
    _selected.removeWhere((id) => !queue.any((m) => m['id'] == id));

    // Counts exclude a developer's test member — it still shows up as a card
    // in the queue below (so pushing it to KDS for real testing still
    // works), just not in what a manager reads as the real headcount.
    int veg = 0, nonVeg = 0, mixed = 0, realTotal = 0;
    for (final m in queue) {
      final sub = (m['subscriptions'] as Map?)?.cast<String, dynamic>() ?? {};
      if (sub['is_test'] == true) continue;
      realTotal++;
      switch (sub['food_preference']) {
        case 'veg':
          veg++;
          break;
        case 'non_veg':
          nonVeg++;
          break;
        case 'mixed':
          mixed++;
          break;
      }
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("TODAY'S MEAL",
            style:
                GoogleFonts.chivo(fontSize: 20, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/subs'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: p.fetchMeals,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.black87,
          indicatorColor: Colors.black87,
          labelStyle: GoogleFonts.chivo(fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: 'TODAY\'S MEAL ($realTotal)'),
            const Tab(text: 'PREPARED'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _todayTab(p, isManager, queue, veg, nonVeg, mixed, realTotal),
          DeliveryOrdersList(provider: p, isManager: isManager),
        ],
      ),
    );
  }

  Widget _todayTab(SubscriptionAdminProvider p, bool isManager,
      List<Map<String, dynamic>> queue, int veg, int nonVeg, int mixed,
      int realTotal) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip('TOTAL × $realTotal', Colors.blueGrey),
                  _chip('VEG × $veg', Colors.green),
                  _chip('NON-VEG × $nonVeg', Colors.orange),
                  _chip('MIXED × $mixed', Colors.purple),
                ],
              ),
              if (isManager) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: queue.isEmpty
                          ? null
                          : () => setState(() {
                                if (_selected.length == queue.length) {
                                  _selected.clear();
                                } else {
                                  _selected
                                    ..clear()
                                    ..addAll(queue
                                        .map((m) => m['id'] as String));
                                }
                              }),
                      child: Text(
                          _selected.length == queue.length && queue.isNotEmpty
                              ? 'DESELECT ALL'
                              : 'SELECT ALL',
                          style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () async {
                              final ids = _selected.toList();
                              final err = await p.pushToKitchen(ids);
                              if (!mounted) return;
                              setState(() => _selected.clear());
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(err ??
                                      '${ids.length} pushed to kitchen ✅'),
                                  backgroundColor:
                                      err == null ? Colors.green[700] : Colors.red[700],
                                ),
                              );
                            },
                      icon: const Icon(Icons.send),
                      label: Text(
                          'PUSH ${_selected.isEmpty ? '' : '(${_selected.length}) '}TO KDS',
                          style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: queue.isEmpty
              ? const KdsEmptyState(message: 'No confirmed orders waiting')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: queue.length,
                  itemBuilder: (_, i) => _todayCard(p, isManager, queue[i]),
                ),
        ),
      ],
    );
  }

  Widget _todayCard(
      SubscriptionAdminProvider p, bool isManager, Map<String, dynamic> m) {
    final sub = (m['subscriptions'] as Map?)?.cast<String, dynamic>() ?? {};
    final manual = (m['manual_subscription_entries'] as Map?)?.cast<String, dynamic>() ?? {};
    final reply = (m['reply_text'] as String?)?.trim() ?? '';
    final rawName = (sub['customer_name'] as String?)?.trim() ??
        (manual['customer_name'] as String?)?.trim() ??
        (reply.isNotEmpty && reply.toLowerCase() != 'manual entry' ? reply : '');
    final isManual = manual.isNotEmpty || (m['manual_entry_id'] != null) || m['subscription_id'] == null;
    final customerName = rawName.isNotEmpty ? rawName : (isManual ? 'Walk-in Customer' : 'Member');
    final id = m['id'] as String;
    final pref = (sub['food_preference'] ?? '') as String;
    final deliveryTime = (m['delivery_time'] ?? '') as String;
    final mealCountOverride = (m['meal_count'] as num?)?.toInt();
    final pickedDishIds = ((m['selected_dish_ids'] as List?) ?? []).cast<String>();
    final assignedDish = (m['subscription_meals'] as Map?)?.cast<String, dynamic>();
    List<String> dishNames = [];
    if (pickedDishIds.isNotEmpty) {
      dishNames = pickedDishIds
          .map((dishId) => p.mealLibrary
              .firstWhere((d) => d['id'] == dishId, orElse: () => const {})['name'])
          .whereType<String>()
          .toList();
    } else if (assignedDish != null && assignedDish['name'] != null) {
      dishNames = [assignedDish['name'].toString()];
    } else if (mealCountOverride != null && mealCountOverride > 1) {
      for (int i = 0; i < mealCountOverride; i++) {
        dishNames.add('Meal ${i + 1}');
      }
    }

    final hasMultipleDishes = dishNames.length > 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: isManager
            ? Checkbox(
                value: _selected.contains(id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
              )
            : null,
        title: Row(
          children: [
            Flexible(
              child: Text(customerName,
                  style: GoogleFonts.chivo(fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis),
            ),
            if (isManual) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('MANUAL',
                    style: GoogleFonts.chivo(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.blue[900])),
              ),
            ],
            if (sub['is_test'] == true) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (isManual
                      ? ((manual['plan_name'] as String?)?.isNotEmpty == true
                          ? '${manual['plan_name']} (Manual Entry)'
                          : 'Manual Entry')
                      : (pref == 'mixed'
                          ? 'MIXED · Morning: '
                              '${(sub['morning_preference'] ?? '—').toString().replaceAll('_', '-').toUpperCase()}'
                              ', Evening: '
                              '${(sub['evening_preference'] ?? '—').toString().replaceAll('_', '-').toUpperCase()}'
                          : (pref.isEmpty
                              ? 'No preference on file'
                              : pref.replaceAll('_', '-').toUpperCase()))) +
                  (mealCountOverride != null ? ' · $mealCountOverride MEALS' : ''),
              style: GoogleFonts.inter(fontSize: 12),
            ),
            if (hasMultipleDishes) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < dishNames.length; i++) ...[
                      if (i > 0) const Divider(height: 10, thickness: 0.5),
                      Row(
                        children: [
                          const Icon(Icons.restaurant,
                              size: 13, color: Colors.blueGrey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              dishNames[i],
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _pickDeliveryTime(
                              p,
                              id,
                              p.getDishDeliveryTime(deliveryTime, i),
                              dishIndex: i,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.schedule,
                                      size: 12, color: Colors.blue),
                                  const SizedBox(width: 4),
                                  Text(
                                    p
                                            .getDishDeliveryTime(
                                                deliveryTime, i)
                                            .isEmpty
                                        ? 'SET TIME'
                                        : p.getDishDeliveryTime(
                                            deliveryTime, i),
                                    style: GoogleFonts.chivo(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.blue[900],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (dishNames.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(dishNames.join(', '),
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Colors.blueGrey[700])),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isManager) ...[
              _priorityControl(
                priority: (m['priority'] as num?)?.toInt() ?? 2,
                onChanged: (newPrio) => p.setPriority(id, newPrio),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: Colors.black54),
                tooltip: "Edit response",
                onPressed: () => _editResponseDialog(p, m),
              ),
            ],
            if (!hasMultipleDishes)
              Builder(builder: (_) {
                final displayTime = p.getDishDeliveryTime(deliveryTime, 0);
                return InkWell(
                  onTap: () => _pickDeliveryTime(p, id, displayTime, dishIndex: 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule, size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(displayTime.isEmpty ? 'SET TIME' : displayTime,
                            style: GoogleFonts.chivo(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.blue[900])),
                      ],
                    ),
                  ),
                );
              }),
            if (isManager) ...[
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final err = await p.pushToKitchen([id]);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err ?? 'Pushed to kitchen ✅'),
                      backgroundColor:
                          err == null ? Colors.green[700] : Colors.red[700],
                    ),
                  );
                },
                icon: const Icon(Icons.send, size: 13),
                label: Text('PUSH',
                    style: GoogleFonts.chivo(
                        fontSize: 11, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
