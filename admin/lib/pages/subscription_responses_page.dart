import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_admin_provider.dart';
import '../providers/auth_provider.dart';

/// SURVEY RESPONSES — the WhatsApp meal survey answers for a chosen date:
/// whether each member wants the meal, and if so, veg/non-veg/mixed
/// (+ morning/evening for mixed). Normally set by the survey reply itself;
/// a manager can also manually confirm/skip a NO RESPONSE row (e.g. the
/// member's reply was free text that didn't parse as yes/no) — that sends
/// the member the same WhatsApp confirmation a real yes/no reply would have.
class SubscriptionResponsesPage extends StatefulWidget {
  const SubscriptionResponsesPage({super.key});

  @override
  State<SubscriptionResponsesPage> createState() =>
      _SubscriptionResponsesPageState();
}

class _SubscriptionResponsesPageState
    extends State<SubscriptionResponsesPage> {
  // Same-day cycle: the reminder asks about today's meal, so responses for
  // today are what a manager checks by default (see send-daily-meal-whatsapp).
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    context.read<SubscriptionAdminProvider>().fetchResponseMeals(_date);
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

  Future<void> _manualDecision(
      SubscriptionAdminProvider p, String mealId, bool yes) async {
    final err = await p.confirmMealManually(mealId, yes: yes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ??
          (yes ? 'Confirmed — member notified ✅' : 'Marked skipped — member notified')),
      backgroundColor: err == null ? Colors.green[700] : Colors.red[700],
    ));
    if (err == null) p.fetchResponseMeals(_date);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionAdminProvider>();
    final isManager =
        ['admin', 'developer', 'sub_manager'].contains(adminAuth.role);
    // Manual override window: 11 AM–6 PM only — matches the server-side
    // check in admin-confirm-meal, which is the real enforcement (this is
    // just so the buttons don't sit there inviting a 403 outside it).
    final hour = DateTime.now().hour;
    final withinManualWindow = hour >= 11 && hour < 18;
    final rows = p.responseMeals;
    // Excluded from the summary counts — a developer's test member still
    // shows up as a card below (TEST badge), just not in the real tally.
    final statsRows = rows.where((m) {
      final sub = (m['subscriptions'] as Map?)?.cast<String, dynamic>();
      return sub?['is_test'] != true;
    });
    final noResponse = statsRows.where((m) => m['status'] == 'awaiting').length;
    final yes = statsRows
        .where((m) => ['confirmed', 'preparing', 'prepared',
                'out_for_delivery', 'delivered']
            .contains(m['status']))
        .length;
    final no = statsRows.where((m) => m['status'] == 'skipped').length;
    final dateLabel =
        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('SURVEY RESPONSES',
            style:
                GoogleFonts.chivo(fontSize: 20, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/subs'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (picked != null) {
                setState(() => _date = picked);
                p.fetchResponseMeals(picked);
              }
            },
            icon: const Icon(Icons.calendar_today,
                size: 18, color: Colors.black87),
            label: Text(dateLabel,
                style: GoogleFonts.chivo(
                    fontWeight: FontWeight.w800, color: Colors.black87)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () => p.fetchResponseMeals(_date),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip('NO RESPONSE × $noResponse', Colors.grey),
                  _chip('YES × $yes', Colors.green),
                  _chip('NO × $no', Colors.red),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(
                child: Text('No survey rows for $dateLabel yet',
                    style: GoogleFonts.chivo(
                        fontSize: 14, color: Colors.grey[600])),
              ),
            )
          else
            ...rows.map((m) {
              final sub =
                  (m['subscriptions'] as Map?)?.cast<String, dynamic>() ?? {};
              final status = m['status'] as String? ?? 'awaiting';
              final pref = (sub['food_preference'] ?? '') as String;
              final isYes = ['confirmed', 'preparing', 'prepared',
                      'out_for_delivery', 'delivered']
                  .contains(status);
              final mealLabel =
                  isYes ? 'YES' : (status == 'skipped' ? 'NO' : 'NO RESPONSE');
              final mealColor = isYes
                  ? Colors.green
                  : (status == 'skipped' ? Colors.red : Colors.grey);

              // Real remaining-meals balance (see Members page) — consumed
              // is derived as plan total minus that balance.
              final plan = (sub['subscription_plans'] as Map?)
                      ?.cast<String, dynamic>() ??
                  {};
              final durationDays = (plan['duration_days'] as num?)?.toInt();
              final mealsPerDay = (plan['meals_per_day'] as num?)?.toInt() ?? 1;
              int? mealsLeft = (sub['meals_remaining'] as num?)?.toInt();
              int? mealsConsumed;
              if (mealsLeft != null && durationDays != null) {
                mealsConsumed = durationDays * mealsPerDay - mealsLeft;
              } else {
                final endDate =
                    DateTime.tryParse((sub['end_date'] ?? '').toString());
                if (durationDays != null && endDate != null) {
                  final today = DateTime.now();
                  final daysLeft = endDate
                          .difference(
                              DateTime(today.year, today.month, today.day))
                          .inDays +
                      1;
                  final clampedDaysLeft = daysLeft.clamp(0, durationDays);
                  mealsLeft = clampedDaysLeft * mealsPerDay;
                  mealsConsumed = (durationDays - clampedDaysLeft) * mealsPerDay;
                }
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                                sub['customer_name'] as String? ?? 'Member',
                                style: GoogleFonts.chivo(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14)),
                          ),
                          if (sub['is_test'] == true) ...[
                            _chip('TEST', Colors.purple),
                            const SizedBox(width: 6),
                          ],
                          _chip('TODAY: $mealLabel', mealColor),
                        ],
                      ),
                      if ((m['reply_text'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('💬 "${m['reply_text']}"',
                              style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey[700])),
                        ),
                      if (pref.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            pref == 'mixed'
                                ? 'MIXED · Morning: '
                                    '${(sub['morning_preference'] ?? '—').toString().replaceAll('_', '-').toUpperCase()}'
                                    ', Evening: '
                                    '${(sub['evening_preference'] ?? '—').toString().replaceAll('_', '-').toUpperCase()}'
                                : pref.replaceAll('_', '-').toUpperCase(),
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                        ),
                      if (mealsLeft != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            _chip('CONSUMED: $mealsConsumed', Colors.blueGrey),
                            _chip(
                                'LEFT: $mealsLeft',
                                mealsLeft == 0
                                    ? Colors.red
                                    : Colors.indigo),
                          ],
                        ),
                      ],
                      if (isManager && status == 'awaiting') ...[
                        const SizedBox(height: 8),
                        if (withinManualWindow)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _manualDecision(
                                    p, m['id'] as String, false),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                child: const Text('MARK NO'),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton(
                                onPressed: () => _manualDecision(
                                    p, m['id'] as String, true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[700],
                                    foregroundColor: Colors.white),
                                child: const Text('CONFIRM'),
                              ),
                            ],
                          )
                        else
                          Text(
                            'Manual confirm available 11 AM–6 PM',
                            style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey[600]),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
