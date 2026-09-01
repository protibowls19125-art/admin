import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/gym_membership_provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/bauhaus_theme.dart';

/// Gold membership: plan picker → Razorpay → set login details → status
/// card. Deliberately simpler than the Elite member area — a discount flag,
/// not a meal-planning commitment, so there's no calendar/WhatsApp UI here.
class GoldMembershipPage extends StatefulWidget {
  const GoldMembershipPage({super.key});

  @override
  State<GoldMembershipPage> createState() => _GoldMembershipPageState();
}

class _GoldMembershipPageState extends State<GoldMembershipPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<GymMembershipProvider>();
      if (p.isMemberLoggedIn) {
        p.loadMemberData();
      } else {
        p.fetchPlans();
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _loginEmail, _loginPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _buy(GymMembershipPlan plan) async {
    final provider = context.read<GymMembershipProvider>();
    final error = await provider.payForPlan(plan);
    if (!mounted) return;
    if (error != null && error != 'Payment cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: BauhausTheme.error),
      );
    }
  }

  Future<void> _activate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final error = await context.read<GymMembershipProvider>().activate(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: BauhausTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GymMembershipProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gold Membership'),
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
      body: provider.isMemberLoggedIn
          ? _memberView(provider)
          : provider.hasPaid
              ? _detailsForm(provider)
              : _plansView(provider),
    );
  }

  // ── Plans ────────────────────────────────────────────────────────────────
  Widget _plansView(GymMembershipProvider provider) {
    return provider.loadingPlans && provider.plans.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: BauhausTheme.primaryBlack,
                  borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Eat at the gym for less,\nevery single time.',
                        style: BauhausTheme.heading(
                            size: 24, weight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 10),
                    Text(
                      'One membership, a standing discount'
                      '${provider.plans.any((p) => p.freeDelivery) ? ' + free delivery' : ''} on '
                      'every regular order for the whole membership period.',
                      style: BauhausTheme.body(
                          size: 13.5, color: Colors.white70, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Choose your tier', style: BauhausTheme.heading(size: 20)),
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
                ...provider.plans.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _GoldPlanCard(
                        plan: p,
                        busy: provider.paying,
                        onSelect: () => _buy(p),
                      ),
                    )),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => _showLoginSheet(),
                  child: const Text('Already a Gold member? Log in'),
                ),
              ),
            ],
          );
  }

  void _showLoginSheet() {
    // Local to this sheet (not the page's setState) — showModalBottomSheet
    // pushes a separate route, so the enclosing State's setState doesn't
    // rebuild it. A StatefulBuilder scoped to the sheet is what actually
    // makes the obscure-toggle and the busy/loading state take effect.
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
            if (_loginEmail.text.trim().isEmpty ||
                _loginPassword.text.isEmpty) {
              return;
            }
            setS(() {
              busy = true;
              errorText = null;
            });
            final error = await context
                .read<GymMembershipProvider>()
                .memberLogin(_loginEmail.text, _loginPassword.text);
            if (!ctx.mounted) return;
            if (error != null) {
              setS(() {
                busy = false;
                errorText = error;
              });
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
                const SizedBox(height: 16),
                TextField(
                  controller: _loginEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _loginPassword,
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

  // ── Post-payment: set login details ─────────────────────────────────────
  Widget _detailsForm(GymMembershipProvider provider) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.workspace_premium,
                    size: 56, color: BauhausTheme.accentRed),
                const SizedBox(height: 16),
                Text('Payment successful',
                    textAlign: TextAlign.center,
                    style: BauhausTheme.heading(size: 22)),
                const SizedBox(height: 6),
                Text(
                  'Set up your login for ${provider.paidPlan?.name ?? 'Gold'}.',
                  textAlign: TextAlign.center,
                  style: BauhausTheme.body(
                      size: 13.5, color: BauhausTheme.mediumGrey),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 8 characters',
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'At least 8 characters'
                      : null,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _activate,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Activate Membership'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Logged-in member view ───────────────────────────────────────────────
  Widget _memberView(GymMembershipProvider provider) {
    if (provider.loadingMember && provider.myMembership == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final mem = provider.myMembership;
    if (mem == null) {
      // Check if this user actually has an Elite subscription instead.
      final subProvider = context.read<SubscriptionProvider>();
      final hasElite = subProvider.mySubscription != null;
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
                  hasElite
                      ? 'You have an Elite membership'
                      : 'No active Gold membership on this account',
                  textAlign: TextAlign.center,
                  style: BauhausTheme.heading(size: 20)),
              if (hasElite) ...[
                const SizedBox(height: 6),
                Text(
                    'This account is linked to an Elite (subscription) plan, not Gold.',
                    textAlign: TextAlign.center,
                    style: BauhausTheme.body(
                        size: 13, color: BauhausTheme.mediumGrey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => context.go('/member/elite'),
                  icon: const Icon(Icons.card_membership, size: 18),
                  label: const Text('Go to Elite Dashboard'),
                ),
              ] else ...[
                if ((provider.memberEmail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Logged in as ${provider.memberEmail}',
                      textAlign: TextAlign.center,
                      style: BauhausTheme.body(
                          size: 13, color: BauhausTheme.mediumGrey)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: provider.memberLogout,
                  child: const Text('Log out'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final plan = (mem['gym_membership_plans'] as Map?)?.cast<String, dynamic>() ?? {};
    final discount = (plan['discount_percent'] as num?)?.toDouble() ?? 0;
    final hasFreeDelivery = plan['free_delivery'] != false;
    final deliveryEnabled = plan['delivery_enabled'] != false;
    final maxFreeOrders = (plan['max_free_orders_per_day'] as num?)?.toInt() ?? 0;
    return RefreshIndicator(
      onRefresh: provider.loadMemberData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Container(
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(BauhausTheme.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.workspace_premium, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('GOLD MEMBER',
                          style: BauhausTheme.body(
                              size: 11, weight: FontWeight.w700, color: Colors.white, spacing: 1.2)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('${discount.toStringAsFixed(0)}% off every order',
                    style: BauhausTheme.heading(size: 26, weight: FontWeight.w700, color: Colors.white)),
                if (hasFreeDelivery) ...[
                  const SizedBox(height: 4),
                  Text('+ free delivery',
                      style: BauhausTheme.body(size: 14, color: Colors.white.withValues(alpha: 0.9))),
                ],
                if (maxFreeOrders > 0) ...[
                  const SizedBox(height: 4),
                  Text('$maxFreeOrders free order${maxFreeOrders > 1 ? 's' : ''} per day',
                      style: BauhausTheme.body(size: 14, color: Colors.white.withValues(alpha: 0.9))),
                ],
                if (!deliveryEnabled) ...[
                  const SizedBox(height: 4),
                  Text('Dine-in / takeaway only',
                      style: BauhausTheme.body(size: 14, color: Colors.white.withValues(alpha: 0.9))),
                ],
                const SizedBox(height: 20),
                Text('Valid till ${mem['end_date'] ?? '—'}',
                    style: BauhausTheme.body(size: 13, color: Colors.white.withValues(alpha: 0.85))),
                if ((mem['member_code'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(mem['member_code'].toString(),
                      style: BauhausTheme.body(size: 13, color: Colors.white.withValues(alpha: 0.85))),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.go('/menu'),
            child: const Text('Order Now'),
          ),
        ],
      ),
    );
  }
}

class _GoldPlanCard extends StatelessWidget {
  final GymMembershipPlan plan;
  final bool busy;
  final VoidCallback onSelect;

  const _GoldPlanCard({required this.plan, required this.busy, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final highlighted = plan.badge.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: BauhausTheme.white,
        borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
        border: Border.all(
          color: highlighted ? BauhausTheme.accentRed : BauhausTheme.patternGrey,
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
                    size: 11, weight: FontWeight.w700, color: Colors.white, spacing: 1.5),
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
                      style: BauhausTheme.body(size: 13, color: BauhausTheme.mediumGrey)),
                const SizedBox(height: 12),
                if (plan.compareAtPrice > plan.price && plan.compareAtPrice > 0)
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
                    ],
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${plan.price.toStringAsFixed(0)}',
                        style: BauhausTheme.heading(
                            size: 30, weight: FontWeight.w700, color: BauhausTheme.accentRed)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('/ ${plan.durationDays} days',
                          style: BauhausTheme.body(size: 13, color: BauhausTheme.mediumGrey)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(BauhausTheme.radiusPill),
                  ),
                  child: Text(
                    '${plan.discountPercent.toStringAsFixed(0)}% OFF EVERY ORDER'
                    '${plan.freeDelivery ? ' + FREE DELIVERY' : ''}',
                    style: BauhausTheme.body(
                        size: 11, weight: FontWeight.w700, color: Colors.white, spacing: 0.5),
                  ),
                ),
                if (plan.maxFreeOrdersPerDay > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(BauhausTheme.radiusPill),
                    ),
                    child: Text(
                      '${plan.maxFreeOrdersPerDay} FREE ORDER${plan.maxFreeOrdersPerDay > 1 ? 'S' : ''} PER DAY',
                      style: BauhausTheme.body(
                          size: 11, weight: FontWeight.w700, color: Colors.white, spacing: 0.5),
                    ),
                  ),
                ],
                if (!plan.deliveryEnabled) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: BauhausTheme.mediumGrey,
                      borderRadius: BorderRadius.circular(BauhausTheme.radiusPill),
                    ),
                    child: Text(
                      'DINE-IN / TAKEAWAY ONLY',
                      style: BauhausTheme.body(
                          size: 11, weight: FontWeight.w700, color: Colors.white, spacing: 0.5),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                ...plan.features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle, size: 16, color: BauhausTheme.accentRed),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f, style: BauhausTheme.body(size: 13.5))),
                        ],
                      ),
                    )),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: busy ? null : onSelect,
                    style: highlighted
                        ? null
                        : ElevatedButton.styleFrom(backgroundColor: BauhausTheme.primaryBlack),
                    child: busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Get ${plan.name}'),
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
