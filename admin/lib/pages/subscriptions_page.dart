import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_admin_provider.dart';
import '../providers/auth_provider.dart';

/// Subscription management: pending approvals + active members.
/// Approving creates the member's app login (email + password) via the
/// admin-manage-member edge function.
class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() => setState(() {})); // FAB switches with the active tab

  @override
  void initState() {
    super.initState();
    // Deferred to a microtask — fetchSubscriptions() notifies listeners
    // synchronously (before its first await), which trips Flutter's
    // "notify during build" assertion when called directly from initState.
    Future.microtask(() {
      if (!mounted) return;
      final p = context.read<SubscriptionAdminProvider>();
      p.fetchSubscriptions();
      p.fetchEditors(); // plans for the "add member" dialog
      p.fetchGroups();
      p.fetchFoodPreferences(); // dietary categories for the "add member" dialog
      p.fetchMealLibrary(); // dishes for the manual entry → KDS push dialog
      p.fetchManualEntries();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool ok = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green[700] : Colors.red[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionAdminProvider>();
    // Real (non-test) counts — a developer's test member never shows up in
    // what a manager reads as the actual pending/active headcount.
    final realPendingCount =
        p.pending.where((s) => s['is_test'] != true).length;
    final realMembersCount =
        p.members.where((s) => s['is_test'] != true).length;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('MEMBERS',
            style:
                GoogleFonts.chivo(fontSize: 22, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/subs'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () {
              p.fetchSubscriptions();
              p.fetchManualEntries();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.black87,
          indicatorColor: Colors.black87,
          labelStyle: GoogleFonts.chivo(fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: 'APPROVALS ($realPendingCount)'),
            Tab(text: 'MEMBERS ($realMembersCount)'),
            Tab(text: 'MANUAL ENTRIES (${p.manualEntries.length})'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 2
          ? FloatingActionButton.extended(
              onPressed: _addManualEntryDialog,
              icon: const Icon(Icons.note_add),
              label: Text('ADD ENTRY',
                  style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
            )
          : FloatingActionButton.extended(
              onPressed: _addMemberDialog,
              icon: const Icon(Icons.person_add),
              label: Text('ADD MEMBER',
                  style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
            ),
      body: p.isLoading && p.pending.isEmpty && p.members.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _list(p.pending, isPending: true),
                _list(p.members, isPending: false),
                _manualEntriesList(p.manualEntries),
              ],
            ),
    );
  }

  Widget _list(List<Map<String, dynamic>> rows, {required bool isPending}) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          isPending ? 'No subscriptions waiting for approval' : 'No members yet',
          style: GoogleFonts.chivo(fontSize: 16, color: Colors.grey[600]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          context.read<SubscriptionAdminProvider>().fetchSubscriptions(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        itemBuilder: (_, i) => _SubCard(
          sub: rows[i],
          isPending: isPending,
          onApprove: () => _approveDialog(rows[i]),
          onReject: () => _rejectDialog(rows[i]),
          onRemove: () => _removeDialog(rows[i]),
          onResetPassword: () => _resetPasswordDialog(rows[i]),
          onEdit: () => _editDialog(rows[i]),
        ),
      ),
    );
  }

  Widget _manualEntriesList(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Center(
        child: Text('No manual entries yet',
            style: GoogleFonts.chivo(fontSize: 16, color: Colors.grey[600])),
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          context.read<SubscriptionAdminProvider>().fetchManualEntries(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final e = rows[i];
          final name = (e['customer_name'] as String?) ?? '';
          final plan = (e['plan_name'] as String?) ?? '';
          final amount = (e['amount'] as num?) ?? 0;
          final notes = (e['notes'] as String?) ?? '';
          final createdAt = (e['created_at'] ?? '').toString().split('T').first;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(name.isEmpty ? 'Unnamed' : name,
                  style: GoogleFonts.chivo(fontWeight: FontWeight.w700)),
              subtitle: Text(
                [
                  if (plan.isNotEmpty) plan,
                  if (amount > 0) '₹$amount',
                  if ((e['phone'] as String?)?.isNotEmpty ?? false) e['phone'],
                  createdAt,
                  if (notes.isNotEmpty) notes,
                ].join(' · '),
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addManualEntryDialog() async {
    final p = context.read<SubscriptionAdminProvider>();
    final name = TextEditingController();
    final phone = TextEditingController();
    final amount = TextEditingController();
    final notes = TextEditingController();
    String? planName = p.plans.isNotEmpty ? p.plans.first['name'] as String? : null;
    // Dish pickers for KDS push
    int mealCount = 1;
    final activeDishes = p.mealLibrary.where((d) => d['active'] != false).toList();
    List<String?> dishIds = [null];
    DateTime mealDate = DateTime.now();
    String pref = p.foodPreferences.isNotEmpty
        ? p.foodPreferences.first['key'] as String
        : 'veg';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add manual entry'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Full name')),
                  TextField(
                      controller: phone,
                      decoration:
                          const InputDecoration(labelText: 'Phone (optional)')),
                  DropdownButtonFormField<String?>(
                    initialValue: planName,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ...p.plans.map((pl) => DropdownMenuItem(
                            value: pl['name'] as String,
                            child: Text(pl['name'] as String),
                          )),
                    ],
                    onChanged: (v) => setState(() => planName = v),
                    decoration:
                        const InputDecoration(labelText: 'Plan (optional)'),
                  ),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Amount (optional)'),
                  ),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                  const Divider(height: 24),
                  Text('PUSH TO KDS',
                      style: GoogleFonts.chivo(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    'Select dishes below to create a KDS order. '
                    'It will appear in Today\'s Meal for push.',
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  // Meal date
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, size: 18),
                    title: Text(
                      'Meal date: ${mealDate.day.toString().padLeft(2, '0')}/${mealDate.month.toString().padLeft(2, '0')}/${mealDate.year}',
                      style: GoogleFonts.chivo(fontSize: 13),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: mealDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 7)),
                        );
                        if (picked != null) setState(() => mealDate = picked);
                      },
                      child: const Text('CHANGE'),
                    ),
                  ),
                  // Food preference
                  if (p.foodPreferences.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: pref,
                      items: p.foodPreferences
                          .map((f) => DropdownMenuItem(
                                value: f['key'] as String,
                                child: Text(f['label'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => pref = v ?? pref),
                      decoration:
                          const InputDecoration(labelText: 'Food preference'),
                    ),
                  // Meal count
                  DropdownButtonFormField<int>(
                    initialValue: mealCount,
                    items: [1, 2, 3]
                        .map((n) => DropdownMenuItem(
                            value: n, child: Text('$n dish${n > 1 ? "es" : ""}')))
                        .toList(),
                    onChanged: (v) => setState(() {
                      mealCount = v ?? mealCount;
                      dishIds = List<String?>.generate(mealCount,
                          (i) => i < dishIds.length ? dishIds[i] : null);
                    }),
                    decoration:
                        const InputDecoration(labelText: 'Number of dishes'),
                  ),
                  // Dish pickers
                  for (int i = 0; i < mealCount; i++) ...[
                    const SizedBox(height: 4),
                    Builder(builder: (_) {
                      final options = [...activeDishes];
                      if (dishIds[i] != null &&
                          !options.any((d) => d['id'] == dishIds[i])) {
                        options.insert(
                            0, {'id': dishIds[i], 'name': '(unavailable)'});
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
                        decoration:
                            InputDecoration(labelText: 'Dish ${i + 1} (optional)'),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ADD')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || name.text.trim().isEmpty) return;
    final selectedDishIds = dishIds.whereType<String>().toList();
    final dateStr =
        '${mealDate.year.toString().padLeft(4, '0')}-${mealDate.month.toString().padLeft(2, '0')}-${mealDate.day.toString().padLeft(2, '0')}';
    final err = await p.addManualEntry({
      'customer_name': name.text.trim(),
      'phone': phone.text.trim(),
      'plan_name': planName ?? '',
      'amount': double.tryParse(amount.text.trim()) ?? 0,
      'notes': notes.text.trim(),
      // KDS fields — only used when dishes are selected
      if (selectedDishIds.isNotEmpty) 'selected_dish_ids': selectedDishIds,
      if (selectedDishIds.isNotEmpty) 'meal_date': dateStr,
      if (selectedDishIds.isNotEmpty) 'meal_count': mealCount,
      'food_preference': pref,
    });
    if (selectedDishIds.isNotEmpty && err == null) {
      _toast('Entry added & queued for KDS ✅');
      // Refresh Today's Meal data so the new entry shows up there too
      p.fetchMeals();
    } else {
      _toast(err ?? 'Entry added ✅', ok: err == null);
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _approveDialog(Map<String, dynamic> sub) async {
    final email = TextEditingController(text: (sub['email'] ?? '') as String);
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve & create login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This activates ${sub['customer_name']}\'s plan and creates their '
              'app login. Share the credentials with them on WhatsApp.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Login email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: password,
              decoration: const InputDecoration(
                  labelText: 'Password (min 8 characters)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('APPROVE')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<SubscriptionAdminProvider>().approve(
          subscriptionId: sub['id'] as String,
          email: email.text.trim(),
          password: password.text,
        );
    _toast(err ?? 'Member approved and login created ✅', ok: err == null);
  }

  Future<void> _rejectDialog(Map<String, dynamic> sub) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject subscription'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REJECT'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context
        .read<SubscriptionAdminProvider>()
        .reject(sub['id'] as String, reason.text.trim());
    _toast(err ?? 'Rejected', ok: err == null);
  }

  Future<void> _removeDialog(Map<String, dynamic> sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
            'This cancels ${sub['customer_name']}\'s subscription and disables '
            'their login. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context
        .read<SubscriptionAdminProvider>()
        .removeMember(sub['id'] as String);
    _toast(err ?? 'Member removed', ok: err == null);
  }

  Future<void> _resetPasswordDialog(Map<String, dynamic> sub) async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset member password'),
        content: TextField(
          controller: password,
          decoration:
              const InputDecoration(labelText: 'New password (min 8 chars)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('RESET')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context
        .read<SubscriptionAdminProvider>()
        .resetPassword(sub['id'] as String, password.text);
    _toast(err ?? 'Password updated', ok: err == null);
  }

  // Editing is only offered once the member has replied with their onboarding
  // details (customer_name gets filled by that reply) — nothing to edit before
  // then, and the edge function rejects it server-side too.
  Future<void> _editDialog(Map<String, dynamic> sub) async {
    final p = context.read<SubscriptionAdminProvider>();
    final name = TextEditingController(text: (sub['customer_name'] ?? '') as String);
    final phone = TextEditingController(text: (sub['phone'] ?? '') as String);
    final notes = TextEditingController(text: (sub['health_notes'] ?? '') as String);
    final address = (sub['delivery_address'] as Map?)?.cast<String, dynamic>() ?? {};
    final addressCtl = TextEditingController(text: (address['address'] ?? '') as String);
    String pref = (sub['food_preference'] ?? '').toString().isNotEmpty
        ? sub['food_preference'] as String
        : (p.foodPreferences.isNotEmpty ? p.foodPreferences.first['key'] as String : 'veg');
    String goal = (sub['health_goal'] ?? '').toString().isNotEmpty
        ? sub['health_goal'] as String
        : 'balanced_nutrition';
    // DropdownButtonFormField requires exactly one item matching its value —
    // a member's stored preference can be a legacy key no longer in the
    // admin-configurable list (e.g. 'veg', pre-dating food_preferences).
    // Make sure it's always selectable rather than crashing the dialog.
    final prefOptions = [...p.foodPreferences];
    if (!prefOptions.any((f) => f['key'] == pref)) {
      prefOptions.insert(0, {'key': pref, 'label': pref.replaceAll('_', ' ').toUpperCase()});
    }
    const knownGoals = {
      'weight_loss', 'muscle_gain', 'balanced_nutrition',
      'diabetic_friendly', 'general_fitness',
    };
    final unknownGoal = !knownGoals.contains(goal) ? goal : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Edit member details'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Full name')),
                  TextField(
                      controller: phone,
                      decoration:
                          const InputDecoration(labelText: 'WhatsApp number')),
                  TextField(
                      controller: addressCtl,
                      decoration:
                          const InputDecoration(labelText: 'Delivery address')),
                  DropdownButtonFormField<String>(
                    initialValue: pref,
                    items: prefOptions
                        .map((f) => DropdownMenuItem(
                              value: f['key'] as String,
                              child: Text(f['label'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => pref = v ?? pref),
                    decoration:
                        const InputDecoration(labelText: 'Food preference'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: goal,
                    items: [
                      if (unknownGoal != null)
                        DropdownMenuItem(
                            value: unknownGoal,
                            child: Text(unknownGoal.replaceAll('_', ' ').toUpperCase())),
                      const DropdownMenuItem(
                          value: 'weight_loss', child: Text('Weight loss')),
                      const DropdownMenuItem(
                          value: 'muscle_gain', child: Text('Muscle gain')),
                      const DropdownMenuItem(
                          value: 'balanced_nutrition',
                          child: Text('Balanced nutrition')),
                      const DropdownMenuItem(
                          value: 'diabetic_friendly',
                          child: Text('Diabetic friendly')),
                      const DropdownMenuItem(
                          value: 'general_fitness',
                          child: Text('General fitness')),
                    ],
                    onChanged: (v) =>
                        setState(() => goal = v ?? 'balanced_nutrition'),
                    decoration:
                        const InputDecoration(labelText: 'Health goal'),
                  ),
                  TextField(
                      controller: notes,
                      decoration:
                          const InputDecoration(labelText: 'Health notes')),
                ],
              ),
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
    final err = await context.read<SubscriptionAdminProvider>().editMemberDetails(
      sub['id'] as String,
      {
        'customer_name': name.text.trim(),
        'phone': phone.text.trim(),
        'food_preference': pref,
        // Not edited on this dialog — pass through unchanged so the edge
        // function (which writes these unconditionally) doesn't blank them.
        'morning_preference': sub['morning_preference'] ?? '',
        'evening_preference': sub['evening_preference'] ?? '',
        'health_goal': goal,
        'health_notes': notes.text.trim(),
        'delivery_address': {...address, 'address': addressCtl.text.trim()},
      },
    );
    _toast(err ?? 'Member details updated ✅', ok: err == null);
  }

  Future<void> _addMemberDialog() async {
    final p = context.read<SubscriptionAdminProvider>();
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final address = TextEditingController();
    String? planId = p.plans.isNotEmpty ? p.plans.first['id'] as String : null;
    String pref =
        p.foodPreferences.isNotEmpty ? p.foodPreferences.first['key'] as String : 'veg';
    String goal = 'balanced_nutrition';
    bool isTest = false;
    final isDeveloper = adminAuth.role == 'developer';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add member manually'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: planId,
                    items: p.plans
                        .map((pl) => DropdownMenuItem(
                              value: pl['id'] as String,
                              child: Text('${pl['name']} — ₹${pl['price']}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => planId = v),
                    decoration: const InputDecoration(labelText: 'Plan'),
                  ),
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Full name')),
                  TextField(
                      controller: phone,
                      decoration: const InputDecoration(
                          labelText: 'WhatsApp number')),
                  TextField(
                      controller: email,
                      decoration:
                          const InputDecoration(labelText: 'Login email')),
                  TextField(
                      controller: password,
                      decoration: const InputDecoration(
                          labelText: 'Password (min 8 chars)')),
                  TextField(
                      controller: address,
                      decoration: const InputDecoration(
                          labelText: 'Delivery address')),
                  DropdownButtonFormField<String>(
                    initialValue: pref,
                    items: p.foodPreferences
                        .map((f) => DropdownMenuItem(
                              value: f['key'] as String,
                              child: Text(f['label'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => pref = v ?? pref),
                    decoration:
                        const InputDecoration(labelText: 'Food preference'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: goal,
                    items: const [
                      DropdownMenuItem(
                          value: 'weight_loss', child: Text('Weight loss')),
                      DropdownMenuItem(
                          value: 'muscle_gain', child: Text('Muscle gain')),
                      DropdownMenuItem(
                          value: 'balanced_nutrition',
                          child: Text('Balanced nutrition')),
                      DropdownMenuItem(
                          value: 'diabetic_friendly',
                          child: Text('Diabetic friendly')),
                      DropdownMenuItem(
                          value: 'general_fitness',
                          child: Text('General fitness')),
                    ],
                    onChanged: (v) =>
                        setState(() => goal = v ?? 'balanced_nutrition'),
                    decoration:
                        const InputDecoration(labelText: 'Health goal'),
                  ),
                  if (isDeveloper)
                    CheckboxListTile(
                      value: isTest,
                      onChanged: (v) => setState(() => isTest = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mark as TEST member'),
                      subtitle: const Text(
                          'Excluded from real stats; plan starts today for '
                          'immediate testing of the reminder cycle.',
                          style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('CREATE')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || planId == null) return;
    final err = await p.addMember({
      'plan_id': planId,
      'customer_name': name.text.trim(),
      'phone': phone.text.trim(),
      'email': email.text.trim(),
      'password': password.text,
      'food_preference': pref,
      'health_goal': goal,
      'delivery_address': {'address': address.text.trim()},
      'is_test': isTest,
    });
    _toast(err ?? 'Member created ✅', ok: err == null);
  }
}

class _SubCard extends StatelessWidget {
  final Map<String, dynamic> sub;
  final bool isPending;
  final VoidCallback onApprove, onReject, onRemove, onResetPassword, onEdit;

  const _SubCard({
    required this.sub,
    required this.isPending,
    required this.onApprove,
    required this.onReject,
    required this.onRemove,
    required this.onResetPassword,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final plan =
        (sub['subscription_plans'] as Map?)?.cast<String, dynamic>() ?? {};
    final address =
        (sub['delivery_address'] as Map?)?.cast<String, dynamic>() ?? {};
    final incomplete = sub['status'] == 'payment_received';
    // Real remaining-meals balance — starts at plan total (duration_days ×
    // meals_per_day) and is decremented/restored by whatsapp-webhook /
    // admin-confirm-meal as each day's meal is actually confirmed/skipped.
    // Falls back to the old calendar estimate only for a row the backfill
    // migration never reached (shouldn't happen for anything created after
    // it, but costs nothing to keep as a safety net).
    int? mealsLeft = (sub['meals_remaining'] as num?)?.toInt();
    if (mealsLeft == null) {
      final endDate = DateTime.tryParse((sub['end_date'] ?? '').toString());
      if (endDate != null) {
        final today = DateTime.now();
        final daysLeft = endDate
                .difference(DateTime(today.year, today.month, today.day))
                .inDays +
            1;
        final mealsPerDay = (plan['meals_per_day'] as num?)?.toInt() ?? 1;
        mealsLeft = daysLeft > 0 ? daysLeft * mealsPerDay : 0;
      }
    }
    final chips = <String>[
      if ((sub['food_preference'] ?? '').toString().isNotEmpty)
        sub['food_preference'].toString().replaceAll('_', '-').toUpperCase(),
      if ((sub['health_goal'] ?? '').toString().isNotEmpty)
        sub['health_goal'].toString().replaceAll('_', ' ').toUpperCase(),
      if ((sub['member_code'] ?? '').toString().isNotEmpty)
        sub['member_code'].toString(),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (sub['customer_name'] ?? '').toString().isEmpty
                        ? '(details not submitted yet)'
                        : sub['customer_name'].toString(),
                    style: GoogleFonts.chivo(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                if (sub['is_test'] == true) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('TEST',
                        style: GoogleFonts.chivo(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.purple[900])),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: incomplete
                        ? Colors.orange[100]
                        : isPending
                            ? Colors.amber[100]
                            : Colors.green[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (sub['status'] ?? '')
                        .toString()
                        .replaceAll('_', ' ')
                        .toUpperCase(),
                    style: GoogleFonts.chivo(
                        fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${plan['name'] ?? 'Plan'} · ₹${sub['amount_paid'] ?? plan['price'] ?? '—'}'
              '${sub['phone'] != null && '${sub['phone']}'.isNotEmpty ? ' · ${sub['phone']}' : ''}'
              '${sub['email'] != null && '${sub['email']}'.isNotEmpty ? ' · ${sub['email']}' : ''}',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[800]),
            ),
            if ((address['address'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '📍 ${address['address']}'
                  '${(address['city'] ?? '').toString().isNotEmpty ? ', ${address['city']}' : ''}'
                  '${(address['pincode'] ?? '').toString().isNotEmpty ? ' — ${address['pincode']}' : ''}',
                  style:
                      GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[700]),
                ),
              ),
            if ((sub['health_notes'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('⚠ ${sub['health_notes']}',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: Colors.deepOrange[800])),
              ),
            if (chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  children: chips
                      .map((c) => Chip(
                            label: Text(c,
                                style: GoogleFonts.chivo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ),
            if (!isPending && sub['end_date'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Valid ${sub['start_date']} → ${sub['end_date']}'
                  '${mealsLeft != null ? '  ·  $mealsLeft meal${mealsLeft == 1 ? '' : 's'} left' : ''}',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight:
                          mealsLeft == 0 ? FontWeight.w800 : FontWeight.w400,
                      color: mealsLeft == 0
                          ? Colors.red[700]
                          : Colors.grey[600]),
                ),
              ),
            if (!isPending) ...[
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final p = context.watch<SubscriptionAdminProvider>();
                final matchingGroups = p.groups
                    .where((g) => g['food_preference'] == sub['food_preference'])
                    .toList();
                return SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: sub['group_id'] as String?,
                    isDense: true,
                    hint: const Text('No group'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('— No group —')),
                      ...matchingGroups.map((g) => DropdownMenuItem<String?>(
                            value: g['id'] as String,
                            child: Text(g['name'] as String),
                          )),
                    ],
                    onChanged: (v) => context
                        .read<SubscriptionAdminProvider>()
                        .setMemberGroup(sub['id'] as String, v),
                    decoration: const InputDecoration(
                      labelText: 'Group',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: isPending
                  ? [
                      TextButton(
                        onPressed: onReject,
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('REJECT'),
                      ),
                      const SizedBox(width: 8),
                      if (!incomplete)
                        TextButton(
                          onPressed: onEdit,
                          child: const Text('EDIT'),
                        ),
                      ElevatedButton.icon(
                        onPressed: incomplete ? null : onApprove,
                        icon: const Icon(Icons.check, size: 16),
                        label: Text(
                            incomplete ? 'AWAITING DETAILS' : 'APPROVE',
                            style: GoogleFonts.chivo(
                                fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white),
                      ),
                    ]
                  : [
                      TextButton(
                        onPressed: onEdit,
                        child: const Text('EDIT'),
                      ),
                      TextButton(
                        onPressed: onResetPassword,
                        child: const Text('RESET PASSWORD'),
                      ),
                      TextButton(
                        onPressed: onRemove,
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('REMOVE'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}
