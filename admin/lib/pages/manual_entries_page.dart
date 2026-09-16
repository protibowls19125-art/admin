import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_admin_provider.dart';

/// MANUAL ENTRIES — a dedicated full-screen page for the subscription model
/// where a manager can:
///   1. Select an existing customer or add a new one (name + phone)
///   2. Pick dishes from the subscription meal library
///   3. Choose plan pricing (from subscription_plans)
///   4. Set payment method (COD / Prepaid)
///   5. Add special instructions (displayed in RED BOLD on the subscription KDS)
///   6. Push the order directly to the subscription kitchen
///
/// This replaces the small "Add manual entry" dialog in the Members page with
/// a purpose-built workflow. Uses the same `addManualEntry()` provider method
/// with the new `auto_push: true` flag so entries appear on the KDS instantly.
class ManualEntriesPage extends StatefulWidget {
  const ManualEntriesPage({super.key});

  @override
  State<ManualEntriesPage> createState() => _ManualEntriesPageState();
}

class _ManualEntriesPageState extends State<ManualEntriesPage> {
  // ── Customer ───────────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _isNewCustomer = false;
  Map<String, String>? _selectedCustomer;

  // ── Dishes ─────────────────────────────────────────────────────────────────
  /// Selected dish ids → quantity.
  final Map<String, int> _dishQty = {};
  String? _categoryFilter; // null = show all categories
  final _dishSearchCtrl = TextEditingController();
  String _dishSearchQuery = '';

  // ── Order details ──────────────────────────────────────────────────────────
  String? _selectedPlanName;
  int _amount = 0;
  final _amountCtrl = TextEditingController();
  String _paymentMethod = 'cod'; // cod | prepaid
  final _instructionsCtrl = TextEditingController();
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<SubscriptionAdminProvider>();
    Future.microtask(() {
      if (!mounted) return;
      p.fetchExistingCustomers();
      p.fetchMealLibrary();
      p.fetchFoodPreferences();
      if (p.plans.isEmpty) p.fetchEditors();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _searchCtrl.dispose();
    _instructionsCtrl.dispose();
    _dishSearchCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green[700] : Colors.red[700],
    ));
  }

  String get _customerName =>
      _selectedCustomer?['name'] ?? _nameCtrl.text.trim();
  String get _customerPhone =>
      _selectedCustomer?['phone'] ?? _phoneCtrl.text.trim();
  int get _totalDishes => _dishQty.values.fold(0, (a, b) => a + b);

  Future<void> _pushToKitchen() async {
    if (_customerName.isEmpty) {
      _toast('Please select or add a customer', ok: false);
      return;
    }
    if (_dishQty.isEmpty) {
      _toast('Please select at least one dish', ok: false);
      return;
    }
    // Prepaid orders do NOT mandate amount. Only COD orders require an amount.
    if (_paymentMethod == 'cod' && _amount <= 0) {
      _toast('Please enter COD collection amount', ok: false);
      return;
    }
    setState(() => _isBusy = true);
    final p = context.read<SubscriptionAdminProvider>();

    // Build dish list — expand qty > 1 into multiple ids.
    final dishIds = <String>[];
    for (final e in _dishQty.entries) {
      for (int i = 0; i < e.value; i++) {
        dishIds.add(e.key);
      }
    }

    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final err = await p.addManualEntry({
      'customer_name': _customerName,
      'phone': _customerPhone,
      'plan_name': _selectedPlanName ?? '',
      'amount': _amount,
      'notes': _instructionsCtrl.text.trim(),
      'payment_method': _paymentMethod,
      'selected_dish_ids': dishIds,
      'meal_date': dateStr,
      'meal_count': dishIds.length,
      'auto_push': true,
    });

    if (!mounted) return;
    setState(() => _isBusy = false);
    if (err != null) {
      _toast(err, ok: false);
    } else {
      _toast('Pushed to kitchen ✅');
      // Reset form
      setState(() {
        _dishQty.clear();
        _instructionsCtrl.clear();
        _selectedCustomer = null;
        _nameCtrl.clear();
        _phoneCtrl.clear();
        _isNewCustomer = false;
        _selectedPlanName = null;
        _amount = 0;
        _amountCtrl.clear();
        _paymentMethod = 'cod';
        _categoryFilter = null;
        _dishSearchCtrl.clear();
        _dishSearchQuery = '';
      });
      // Refresh customer list to include the just-added one
      p.fetchExistingCustomers();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionAdminProvider>();
    final activeDishes =
        p.mealLibrary.where((d) => d['active'] != false).toList();
    final filtered = activeDishes.where((d) {
      if (_categoryFilter != null && _categoryFilter!.isNotEmpty) {
        final cat = (d['category'] ?? '').toString().trim();
        if (cat.toLowerCase() != _categoryFilter!.toLowerCase()) return false;
      }
      if (_dishSearchQuery.isNotEmpty) {
        final name = (d['name'] ?? '').toString().toLowerCase();
        final cat = (d['category'] ?? '').toString().toLowerCase();
        if (!name.contains(_dishSearchQuery) && !cat.contains(_dishSearchQuery)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('📋 MANUAL ENTRIES',
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
            onPressed: () {
              p.fetchExistingCustomers();
              p.fetchMealLibrary();
              p.fetchFoodPreferences();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Customer section ──────────────────────────────────────────
          _customerSection(p),
          const Divider(height: 1),
          // ── Category filter section ───────────────────────────────────
          _categorySection(p, activeDishes),
          // ── Dish grid ────────────────────────────────────────────────
          Expanded(child: _dishGrid(p, filtered)),
          // ── Bottom bar ───────────────────────────────────────────────
          _bottomBar(p),
        ],
      ),
    );
  }

  // ── Customer section ─────────────────────────────────────────────────────

  Widget _customerSection(SubscriptionAdminProvider p) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CUSTOMER',
                  style: GoogleFonts.chivo(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.grey[800])),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _isNewCustomer = !_isNewCustomer),
                icon: Icon(
                  _isNewCustomer ? Icons.search : Icons.person_add,
                  size: 16,
                ),
                label: Text(
                  _isNewCustomer ? 'SELECT EXISTING' : 'ADD NEW',
                  style: GoogleFonts.chivo(
                      fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_isNewCustomer) ...[
            // New customer fields
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Full name',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    style: GoogleFonts.inter(fontSize: 14),
                    onChanged: (_) => setState(() => _selectedCustomer = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.inter(fontSize: 14),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Customer search/select
            if (_selectedCustomer != null)
              Chip(
                label: Text(
                  '${_selectedCustomer!['name']}  ${_selectedCustomer!['phone']!.isNotEmpty ? '· ${_selectedCustomer!['phone']}' : ''}',
                  style: GoogleFonts.chivo(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () =>
                    setState(() => _selectedCustomer = null),
                backgroundColor: Colors.green[50],
                side: BorderSide(color: Colors.green[300]!),
              )
            else
              Autocomplete<Map<String, String>>(
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.toLowerCase().trim();
                  if (q.isEmpty) return p.existingCustomers.take(20);
                  return p.existingCustomers.where((c) =>
                      (c['name'] ?? '').toLowerCase().contains(q) ||
                      (c['phone'] ?? '').contains(q));
                },
                displayStringForOption: (c) =>
                    '${c['name']}${c['phone']!.isNotEmpty ? ' · ${c['phone']}' : ''}',
                onSelected: (c) => setState(() => _selectedCustomer = c),
                fieldViewBuilder: (ctx, ctrl, focusNode, onSubmitted) {
                  return TextField(
                    controller: ctrl,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Search customer by name or phone...',
                      prefixIcon:
                          const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    style: GoogleFonts.inter(fontSize: 14),
                    onSubmitted: (_) => onSubmitted(),
                  );
                },
                optionsViewBuilder: (ctx, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxHeight: 250, maxWidth: 400),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (ctx, i) {
                            final c = options.elementAt(i);
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.green[100],
                                child: Text(
                                  (c['name'] ?? '?')[0].toUpperCase(),
                                  style: GoogleFonts.chivo(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.green[900]),
                                ),
                              ),
                              title: Text(c['name'] ?? '',
                                  style: GoogleFonts.chivo(
                                      fontWeight: FontWeight.w700)),
                              subtitle: c['phone']!.isNotEmpty
                                  ? Text(c['phone']!,
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey[600]))
                                  : null,
                              onTap: () => onSelected(c),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  // ── Category filter tabs & search ───────────────────────────────────────

  Widget _categorySection(
      SubscriptionAdminProvider p, List<Map<String, dynamic>> activeDishes) {
    final categories = p.mealCategories;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search box
          SizedBox(
            height: 36,
            child: TextField(
              controller: _dishSearchCtrl,
              onChanged: (v) =>
                  setState(() => _dishSearchQuery = v.trim().toLowerCase()),
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search dishes...',
                hintStyle:
                    GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _dishSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _dishSearchCtrl.clear();
                          setState(() => _dishSearchQuery = '');
                        },
                        padding: EdgeInsets.zero,
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Colors.black87),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Category chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryChip(
                  label: 'ALL',
                  count: activeDishes.length,
                  isSelected: _categoryFilter == null,
                  onTap: () => setState(() => _categoryFilter = null),
                ),
                ...categories.map((cat) {
                  final count = activeDishes
                      .where((d) =>
                          (d['category'] ?? '').toString().toLowerCase() ==
                          cat.toLowerCase())
                      .length;
                  return _categoryChip(
                    label: cat.toUpperCase(),
                    count: count,
                    isSelected:
                        _categoryFilter?.toLowerCase() == cat.toLowerCase(),
                    onTap: () => setState(() {
                      _categoryFilter =
                          _categoryFilter?.toLowerCase() == cat.toLowerCase()
                              ? null
                              : cat;
                    }),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black87 : Colors.grey[100],
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? Colors.black87 : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.chivo(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white24 : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.chivo(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dish grid ────────────────────────────────────────────────────────────

  Widget _dishGrid(
      SubscriptionAdminProvider p, List<Map<String, dynamic>> dishes) {
    if (dishes.isEmpty) {
      return Center(
        child: Text('No dishes available',
            style: GoogleFonts.chivo(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500])),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 200,
      ),
      itemCount: dishes.length,
      itemBuilder: (_, i) => _dishCard(dishes[i]),
    );
  }

  Widget _dishCard(Map<String, dynamic> dish) {
    final id = dish['id'] as String;
    final name = dish['name'] as String? ?? '';
    final imageUrl = dish['image_url'] as String?;
    final qty = _dishQty[id] ?? 0;
    final isSelected = qty > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? Colors.green : Colors.grey[300]!,
          width: isSelected ? 2.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                    color: Colors.green.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1)
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(9)),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _dishImageFallback())
                  : _dishImageFallback(),
            ),
          ),
          // Name + category badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.chivo(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if ((dish['category'] ?? '').toString().isNotEmpty &&
                        dish['category'] != 'General')
                      Expanded(
                        child: Text(
                          dish['category'].toString().toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.chivo(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.blueGrey[600],
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    if ((dish['badge'] ?? '').toString().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: dish['badge'].toString().contains('NON')
                              ? Colors.red[50]
                              : Colors.green[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: dish['badge'].toString().contains('NON')
                                ? Colors.red[200]!
                                : Colors.green[200]!,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          dish['badge'].toString(),
                          style: GoogleFonts.chivo(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: dish['badge'].toString().contains('NON')
                                ? Colors.red[700]
                                : Colors.green[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Qty stepper
          Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.green[50] : Colors.grey[100],
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.remove_circle_outline,
                      size: 22,
                      color: qty > 0 ? Colors.red[700] : Colors.grey[400]),
                  onPressed: qty > 0
                      ? () => setState(() {
                            if (qty <= 1) {
                              _dishQty.remove(id);
                            } else {
                              _dishQty[id] = qty - 1;
                            }
                          })
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36),
                ),
                Text('$qty',
                    style: GoogleFonts.chivo(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.green[800] : Colors.grey)),
                IconButton(
                  icon: Icon(Icons.add_circle,
                      size: 22, color: Colors.green[700]),
                  onPressed: () =>
                      setState(() => _dishQty[id] = qty + 1),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dishImageFallback() => Container(
        color: Colors.grey[200],
        child: Icon(Icons.fastfood, size: 40, color: Colors.grey[400]),
      );

  // ── Bottom bar ───────────────────────────────────────────────────────────

  Widget _bottomBar(SubscriptionAdminProvider p) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Plan + Amount + Payment
            Row(
              children: [
                // Plan picker
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedPlanName,
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text('— No plan —',
                              style: TextStyle(fontSize: 13))),
                      ...p.plans.map((pl) => DropdownMenuItem(
                            value: pl['name'] as String,
                            child: Text(
                              '${pl['name']} · ₹${pl['price']}',
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedPlanName = v;
                        if (v != null) {
                          final plan = p.plans.firstWhere(
                              (pl) => pl['name'] == v,
                              orElse: () => {});
                          final price =
                              (plan['price'] as num?)?.round() ?? 0;
                          _amount = price;
                          _amountCtrl.text = price > 0 ? '$price' : '';
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Plan',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                    isExpanded: true,
                  ),
                ),
                const SizedBox(width: 8),
                // Amount (Integer only, optional for prepaid)
                SizedBox(
                  width: 95,
                  child: TextField(
                    controller: _amountCtrl,
                    decoration: InputDecoration(
                      labelText:
                          _paymentMethod == 'cod' ? '₹ Amt *' : '₹ Amt',
                      hintText:
                          _paymentMethod == 'prepaid' ? 'Opt' : '0',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (v) => _amount = int.tryParse(v) ?? 0,
                    style: GoogleFonts.chivo(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                // Payment toggle
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _paymentButton('COD', 'cod'),
                      _paymentButton('PREPAID', 'prepaid'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: Special instructions
            TextField(
              controller: _instructionsCtrl,
              decoration: InputDecoration(
                labelText: '⚡ Special Instructions (shown in RED BOLD on KDS)',
                labelStyle: GoogleFonts.chivo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.red[700]),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.red[200]!)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.red[400]!, width: 2)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              style: GoogleFonts.chivo(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.red[900]),
              maxLines: 1,
            ),
            const SizedBox(height: 10),
            // Row 3: Push button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _pushToKitchen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: _isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isBusy
                      ? 'PUSHING...'
                      : 'PUSH TO KITCHEN${_totalDishes > 0 ? '  ($_totalDishes dish${_totalDishes > 1 ? 'es' : ''})' : ''}',
                  style: GoogleFonts.chivo(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentButton(String label, String value) {
    final selected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (value == 'cod' ? Colors.orange[700] : Colors.blue[700])
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: GoogleFonts.chivo(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }
}
