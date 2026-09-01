import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/gym_membership_provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/bauhaus_theme.dart';
import '../widgets/app_bottom_nav.dart';

/// The member area: login gate → premium membership card + meal calendar.
///
/// UX psychology: the premium card leads the screen (ownership & status —
/// people keep what makes them feel valued), the single most important daily
/// action (confirm today's meal) sits directly under it as one big
/// yes / no choice, and everything else stays quiet.
class MemberPage extends StatefulWidget {
  const MemberPage({super.key});

  @override
  State<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends State<MemberPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<SubscriptionProvider>();
      if (p.isMemberLoggedIn) {
        p.loadMemberData();
      } else {
        // Not logged in — fetch plans so we can show them.
        p.fetchPlans();
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SubscriptionProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          if (provider.isMemberLoggedIn)
            IconButton(
              icon: const Icon(Icons.account_circle, size: 28),
              tooltip: 'Log out',
              onPressed: provider.memberLogout,
            ),
        ],
      ),
      body: provider.isMemberLoggedIn ? _memberView(provider) : _plansView(provider),
      bottomNavigationBar: const AppBottomNav(active: AppTab.premium),
    );
  }

  // ── Plans view (not logged in) ──────────────────────────────────────────
  Widget _plansView(SubscriptionProvider provider) {
    void openEnquiryForm() {
      // JSONB may wrap the URL in extra quotes — strip them.
      final url = provider.enquiryFormUrl.replaceAll('"', '').trim();
      if (url.isEmpty || !url.startsWith('http')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enquiry form not configured. Please contact us directly.'),
            backgroundColor: BauhausTheme.error,
          ),
        );
        return;
      }
      // Direct browser API — most reliable on Flutter Web.
      web.window.open(url, '_blank');
    }

    return provider.loadingPlans && provider.plans.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              // Hero banner
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: BauhausTheme.primaryBlack,
                  borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: BauhausTheme.accentSoft.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(BauhausTheme.radiusPill),
                      ),
                      child: Text('ELITE MEMBERSHIP',
                          style: BauhausTheme.body(
                              size: 11,
                              weight: FontWeight.w700,
                              color: BauhausTheme.accentSoft,
                              spacing: 1.2)),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Your health goal,\ncooked fresh every day.',
                      style: BauhausTheme.heading(
                          size: 24, weight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chef-crafted, protein-forward meals matched to your goal — '
                      'delivered to your door.',
                      style: BauhausTheme.body(
                          size: 13.5, color: Colors.white70, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Plan cards
              Text('Choose your plan', style: BauhausTheme.heading(size: 20)),
              const SizedBox(height: 12),
              if (provider.plans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: BauhausTheme.lightGrey,
                    borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
                  ),
                  child: Column(
                    children: [
                      Text('Plans are being updated',
                          style: BauhausTheme.body(size: 15, weight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: provider.fetchPlans,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              else
                ...provider.plans.map((plan) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ElitePlanCard(
                        plan: plan,
                        onEnquire: openEnquiryForm,
                      ),
                    )),

              // Existing member login
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _showLoginSheet,
                  child: const Text('Already a member? Log in'),
                ),
              ),
            ],
          );
  }

  void _showLoginSheet() {
    bool obscure = true;
    bool busy = false;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BauhausTheme.radiusLg)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> doLogin() async {
            if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
            setS(() { busy = true; errorText = null; });
            final error = await context
                .read<SubscriptionProvider>()
                .memberLogin(_email.text, _password.text);
            if (!ctx.mounted) return;
            if (error != null) {
              setS(() { busy = false; errorText = error; });
            } else {
              Navigator.pop(ctx);
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Member login', style: BauhausTheme.heading(size: 20)),
                const SizedBox(height: 6),
                Text(
                  'Use the login sent to you on WhatsApp when your membership '
                  'was approved.',
                  style: BauhausTheme.body(
                      size: 13, color: BauhausTheme.mediumGrey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: obscure,
                  onSubmitted: (_) => doLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20),
                      onPressed: () => setS(() => obscure = !obscure),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(errorText!,
                      style: BauhausTheme.body(
                          size: 13, color: BauhausTheme.error)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: busy ? null : doLogin,
                  child: busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Log In'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Member home ──────────────────────────────────────────────────────────
  Widget _memberView(SubscriptionProvider provider) {
    if (provider.loadingMember && provider.mySubscription == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final sub = provider.mySubscription;
    if (sub == null) {
      // Check if this user actually has a Gold membership instead.
      final gymProvider = context.read<GymMembershipProvider>();
      final hasGold = gymProvider.myMembership != null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_empty,
                  size: 56, color: BauhausTheme.mediumGrey),
              const SizedBox(height: 12),
              Text(
                  hasGold
                      ? 'You have a Gold membership'
                      : 'No active membership on this account',
                  textAlign: TextAlign.center,
                  style: BauhausTheme.heading(size: 20)),
              if (hasGold) ...[
                const SizedBox(height: 6),
                Text(
                    'This account is linked to a Gold (gym) plan, not Elite.',
                    textAlign: TextAlign.center,
                    style: BauhausTheme.body(
                        size: 13, color: BauhausTheme.mediumGrey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => context.go('/member/gold'),
                  icon: const Icon(Icons.workspace_premium, size: 18),
                  label: const Text('Go to Gold Dashboard'),
                ),
              ] else ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/subscribe'),
                  child: const Text('Explore Plans'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final plan =
        (sub['subscription_plans'] as Map?)?.cast<String, dynamic>() ?? {};
    return RefreshIndicator(
      onRefresh: provider.loadMemberData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          _premiumCard(sub, plan),
          const SizedBox(height: 24),
          _todaySection(provider),
          const SizedBox(height: 24),
          _calendar(provider),
        ],
      ),
    );
  }

  /// The PREMIUM CARD — brushed-gold gradient, "keep-worthy" membership pass.
  Widget _premiumCard(Map<String, dynamic> sub, Map<String, dynamic> plan) {
    final totalDays = (plan['duration_days'] as num?)?.toInt() ?? 0;
    final mealsPerDay = (plan['meals_per_day'] as num?)?.toInt() ?? 1;
    final totalMeals = totalDays * mealsPerDay;
    // The real balance (subscriptions.meals_remaining) — decremented/restored
    // by confirm_meal/whatsapp-webhook/admin-confirm-meal as each day is
    // actually confirmed/skipped, same source of truth the admin panel
    // reads (subscription_responses_page.dart). Falls back to a calendar
    // estimate only for a row a backfill migration never reached.
    int? remainingMeals = (sub['meals_remaining'] as num?)?.toInt();
    if (remainingMeals == null) {
      final endDate = DateTime.tryParse((sub['end_date'] ?? '').toString());
      if (endDate != null) {
        final today = DateTime.now();
        final daysLeft = endDate
                .difference(DateTime(today.year, today.month, today.day))
                .inDays +
            1;
        remainingMeals = daysLeft.clamp(0, totalDays) * mealsPerDay;
      } else {
        remainingMeals = 0;
      }
    }
    remainingMeals = remainingMeals.clamp(0, totalMeals);
    final consumedMeals = totalMeals - remainingMeals;
    final progress = totalMeals == 0 ? 0.0 : consumedMeals / totalMeals;

    final price = (plan['price'] as num?)?.toDouble() ?? 0;
    final compareAt = (plan['compare_at_price'] as num?)?.toDouble() ?? 0;
    final savings = compareAt > price ? compareAt - price : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF9D423), Color(0xFFD4A017), Color(0xFFB8860B)],
        ),
        borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
        boxShadow: BauhausTheme.floatingShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius:
                      BorderRadius.circular(BauhausTheme.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('PREMIUM MEMBER',
                        style: BauhausTheme.body(
                            size: 11,
                            weight: FontWeight.w700,
                            color: Colors.white,
                            spacing: 1.2)),
                  ],
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(BauhausTheme.radiusSm),
                onTap: () => _showManageSheet(sub, plan),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(BauhausTheme.radiusSm),
                  ),
                  child: const Icon(Icons.qr_code_2,
                      color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Meals Remaining',
              style: BauhausTheme.body(
                  size: 14, color: Colors.white.withValues(alpha: 0.9))),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$remainingMeals',
                  style: BauhausTheme.heading(
                      size: 44, weight: FontWeight.w700, color: Colors.white)),
              const SizedBox(width: 8),
              Text('Meals Left',
                  style: BauhausTheme.heading(
                      size: 18,
                      weight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85))),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(BauhausTheme.radiusPill),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$consumedMeals Consumed',
                  style: BauhausTheme.body(
                      size: 11,
                      weight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                      spacing: 0.5)),
              Text('$totalMeals Total',
                  style: BauhausTheme.body(
                      size: 11,
                      weight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                      spacing: 0.5)),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Savings',
                        style: BauhausTheme.body(
                            size: 11,
                            weight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        text: '₹${savings.round()} ',
                        style: BauhausTheme.heading(
                            size: 18,
                            weight: FontWeight.w700,
                            color: Colors.white),
                        children: [
                          TextSpan(
                            text: 'saved',
                            style: BauhausTheme.body(
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _showManageSheet(sub, plan),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BauhausTheme.surfaceBlack,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Manage Plan'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Membership details that don't fit on the gradient card — name, member
  /// code, goal, validity — surfaced from the "Manage Plan" / QR tap.
  void _showManageSheet(Map<String, dynamic> sub, Map<String, dynamic> plan) {
    final name = (sub['customer_name'] ?? '') as String;
    final code = (sub['member_code'] ?? '') as String;
    final end = (sub['end_date'] ?? '') as String;
    final goal = ((sub['health_goal'] ?? '') as String)
        .replaceAll('_', ' ')
        .toUpperCase();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(BauhausTheme.radiusLg)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name.isEmpty ? 'Your membership' : name,
                style: BauhausTheme.heading(size: 20)),
            const SizedBox(height: 4),
            if (code.isNotEmpty)
              Text(code,
                  style:
                      BauhausTheme.body(size: 13, color: BauhausTheme.mediumGrey)),
            const SizedBox(height: 20),
            _sheetRow('Plan', (plan['name'] ?? '—').toString()),
            if (goal.isNotEmpty) _sheetRow('Goal', goal),
            _sheetRow('Valid till', end.isEmpty ? '—' : end),
          ],
        ),
      ),
    );
  }

  Widget _sheetRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    BauhausTheme.body(size: 14, color: BauhausTheme.mediumGrey)),
            Text(value,
                style: BauhausTheme.body(size: 14, weight: FontWeight.w600)),
          ],
        ),
      );

  /// Today's meal — one glance, one tap.
  Widget _todaySection(SubscriptionProvider provider) {
    final today = provider.todayMeal;
    final status = today?.status ?? 'awaiting';
    final kitchenLocked = !['awaiting', 'confirmed', 'skipped'].contains(status);
    // In-app confirm window closes 1 PM IST — after that only a manager can
    // still override (11 AM–6 PM); computed from UTC rather than device
    // local time so it's correct regardless of the phone's timezone setting.
    final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final pastAppCutoff = nowIst.hour >= 13;
    final locked = kitchenLocked || pastAppCutoff;

    final (label, color) = switch (status) {
      'confirmed' => ('Confirmed — we\'re cooking for you', const Color(0xFF2E7D32)),
      'skipped' => ('Skipped — enjoy your day', BauhausTheme.mediumGrey),
      'preparing' || 'prepared' => ('In the kitchen', const Color(0xFFE65100)),
      'out_for_delivery' => ('On its way to you', const Color(0xFF1565C0)),
      'delivered' => ('Delivered', const Color(0xFF2E7D32)),
      _ => ('Awaiting your confirmation', BauhausTheme.accentRed),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BauhausTheme.white,
        borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
        boxShadow: BauhausTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today\'s meal', style: BauhausTheme.heading(size: 20)),
          // The actual dish the kitchen has planned for the member's
          // preference — seeing the food makes confirming much easier.
          if (provider.todayDish != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if ((provider.todayDish!['image_url'] ?? '')
                    .toString()
                    .isNotEmpty)
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(BauhausTheme.radiusMd),
                    child: Image.network(
                      provider.todayDish!['image_url'] as String,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (provider.todayDish!['name'] ?? '') as String,
                        style: BauhausTheme.heading(size: 16),
                      ),
                      if (((provider.todayDish!['kcal'] ?? 0) as num) > 0)
                        Text(
                          '${provider.todayDish!['kcal']} kcal',
                          style: BauhausTheme.body(
                              size: 12,
                              weight: FontWeight.w600,
                              color: BauhausTheme.accentRed),
                        ),
                      if ((provider.todayDish!['description'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Text(
                          provider.todayDish!['description'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BauhausTheme.body(
                              size: 12.5,
                              color: BauhausTheme.mediumGrey),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: BauhausTheme.body(
                        size: 14, weight: FontWeight.w600, color: color)),
              ),
            ],
          ),
          if (!locked) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: status == 'confirmed'
                        ? null
                        : () => _confirm(provider, true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Yes, I\'ll eat'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: status == 'skipped'
                        ? null
                        : () => _confirm(provider, false),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Skip today'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'You can also reply YES / NO to our WhatsApp message (before 11 AM).',
              style: BauhausTheme.body(
                  size: 12, color: BauhausTheme.mediumGrey),
            ),
          ] else if (pastAppCutoff && !kitchenLocked) ...[
            const SizedBox(height: 16),
            Text(
              'The app confirm window has closed for today (1 PM) — '
              'contact us if you need this changed.',
              style: BauhausTheme.body(
                  size: 12.5, color: BauhausTheme.mediumGrey),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(SubscriptionProvider provider, bool yes) async {
    final error = await provider.confirmToday(yes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ??
          (yes
              ? 'Confirmed! Your meal will be fresh today.'
              : 'Skipped — see you tomorrow.')),
      backgroundColor:
          error == null ? const Color(0xFF2E7D32) : BauhausTheme.error,
    ));
  }

  /// Simple history/upcoming list — reinforces the habit streak.
  Widget _calendar(SubscriptionProvider provider) {
    if (provider.mealDays.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your meals', style: BauhausTheme.heading(size: 20)),
        const SizedBox(height: 12),
        ...provider.mealDays.map((d) {
          final (icon, color) = switch (d.status) {
            'confirmed' => (Icons.check_circle, const Color(0xFF2E7D32)),
            'skipped' => (Icons.remove_circle_outline, BauhausTheme.mediumGrey),
            'preparing' ||
            'prepared' =>
              (Icons.soup_kitchen_outlined, const Color(0xFFE65100)),
            'out_for_delivery' =>
              (Icons.delivery_dining, const Color(0xFF1565C0)),
            'delivered' => (Icons.done_all, const Color(0xFF2E7D32)),
            'missed' => (Icons.cancel_outlined, BauhausTheme.error),
            _ => (Icons.schedule, BauhausTheme.outline),
          };
          final label = d.status.replaceAll('_', ' ');
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Text(
                  '${d.date.day}/${d.date.month}/${d.date.year}',
                  style: BauhausTheme.body(size: 14, weight: FontWeight.w600),
                ),
                const Spacer(),
                Text(label[0].toUpperCase() + label.substring(1),
                    style: BauhausTheme.body(size: 13, color: color)),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Elite Plan Card (shown when not logged in)
// ─────────────────────────────────────────────────────────────────────────────

class _ElitePlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final VoidCallback onEnquire;

  const _ElitePlanCard({required this.plan, required this.onEnquire});

  @override
  Widget build(BuildContext context) {
    final highlighted = plan.badge.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: BauhausTheme.white,
        borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
        border: Border.all(
          color:
              highlighted ? BauhausTheme.accentRed : BauhausTheme.patternGrey,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: BauhausTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(
                color: BauhausTheme.accentRed,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Text(
                plan.badge.toUpperCase(),
                textAlign: TextAlign.center,
                style: BauhausTheme.body(
                    size: 11,
                    weight: FontWeight.w700,
                    color: Colors.white,
                    spacing: 1.5),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name, style: BauhausTheme.heading(size: 20)),
                if (plan.tagline.isNotEmpty)
                  Text(plan.tagline,
                      style: BauhausTheme.body(
                          size: 13, color: BauhausTheme.mediumGrey)),
                const SizedBox(height: 12),
                if (plan.discountPercent > 0)
                  Row(
                    children: [
                      Text(
                        '₹${plan.compareAtPrice.toStringAsFixed(0)}',
                        style: BauhausTheme.body(
                          size: 15,
                          weight: FontWeight.w600,
                          color: BauhausTheme.mediumGrey,
                        ).copyWith(
                            decoration: TextDecoration.lineThrough,
                            decorationColor: BauhausTheme.mediumGrey),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius:
                              BorderRadius.circular(BauhausTheme.radiusPill),
                        ),
                        child: Text(
                          'SAVE ${plan.discountPercent}%',
                          style: BauhausTheme.body(
                              size: 11,
                              weight: FontWeight.w700,
                              color: Colors.white,
                              spacing: 0.8),
                        ),
                      ),
                    ],
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${plan.price.toStringAsFixed(0)}',
                        style: BauhausTheme.heading(
                            size: 30,
                            weight: FontWeight.w700,
                            color: BauhausTheme.accentRed)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '/ ${plan.durationDays} days',
                        style: BauhausTheme.body(
                            size: 13, color: BauhausTheme.mediumGrey),
                      ),
                    ),
                  ],
                ),
                Text(
                  '≈ ₹${plan.perMeal.toStringAsFixed(0)} per meal · '
                  '${plan.mealsPerDay} meal${plan.mealsPerDay > 1 ? 's' : ''}/day',
                  style: BauhausTheme.body(
                      size: 12,
                      weight: FontWeight.w600,
                      color: BauhausTheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                ...plan.features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 16, color: BauhausTheme.accentRed),
                          const SizedBox(width: 8),
                          Expanded(
                            child:
                                Text(f, style: BauhausTheme.body(size: 13.5)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onEnquire,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('ENQUIRE NOW'),
                    style: highlighted
                        ? null
                        : ElevatedButton.styleFrom(
                            backgroundColor: BauhausTheme.primaryBlack),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
