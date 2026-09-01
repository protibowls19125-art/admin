import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/bauhaus_theme.dart';

/// Subscription sales page.
///
/// Conversion psychology, kept honest and official:
///  • Outcome-led headline (identity: "eat well every day", not "buy meals").
///  • Value anchoring — the per-meal price is shown under the plan price.
///  • Social proof + salience — one plan carries the "most popular" badge.
///  • Risk-reversal framing — "pause any day", "no auto-renewal" reduce the
///    fear of committing.
///  • A "how it works" strip lowers effort perception before the price ask.
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  @override
  void initState() {
    super.initState();
    // Refresh plans every visit — the manager edits them live from admin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionProvider>().fetchPlans();
    });
  }

  void _openEnquiryForm(String rawUrl) {
    // JSONB may wrap the URL in extra quotes — strip them.
    final url = rawUrl.replaceAll('"', '').trim();
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SubscriptionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Subscription'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/member'),
            child: const Text('Member Login'),
          ),
        ],
      ),
      body: provider.loadingPlans && provider.plans.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _hero(),
                const SizedBox(height: 28),
                _howItWorks(),
                const SizedBox(height: 28),
                Text('Choose your plan',
                    style: BauhausTheme.heading(size: 22)),
                const SizedBox(height: 4),
                Text(
                  'One payment. Fresh meals daily. Pause any day.',
                  style: BauhausTheme.body(
                      size: 14, color: BauhausTheme.mediumGrey),
                ),
                const SizedBox(height: 16),
                if (provider.plans.isEmpty)
                  _emptyPlans(provider)
                else
                  ...provider.plans.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _PlanCard(
                          plan: p,
                          onSelect: () => _openEnquiryForm(
                              provider.enquiryFormUrl),
                        ),
                      )),
                const SizedBox(height: 12),
                _trustStrip(),
              ],
            ),
    );
  }

  Widget _hero() {
    return Container(
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
            child: Text('MEMBERS ONLY',
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
                size: 26, weight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            'Chef-crafted, protein-forward meals matched to your goal — '
            'delivered to your door. You confirm each evening; we cook only '
            'what you\'ll actually eat.',
            style: BauhausTheme.body(
                size: 14, color: Colors.white70, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _howItWorks() {
    const steps = [
      (Icons.description_outlined, 'Fill the enquiry form', 'Tell us your goal, preferences & allergies.'),
      (Icons.chat_bubble_outline, 'We\'ll get in touch', 'Our team will reach out to customize your plan.'),
      (Icons.restaurant_menu, 'Confirm your plan', 'Pick your perfect plan and start eating right.'),
      (Icons.delivery_dining, 'Fresh meals, daily', 'Chef-cooked, delivered right to your doorstep.'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How it works', style: BauhausTheme.heading(size: 22)),
        const SizedBox(height: 12),
        ...List.generate(steps.length, (i) {
          final (icon, title, sub) = steps[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: BauhausTheme.lightGrey,
                    borderRadius:
                        BorderRadius.circular(BauhausTheme.radiusMd),
                  ),
                  child: Icon(icon, size: 22, color: BauhausTheme.accentRed),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. $title',
                          style: BauhausTheme.body(
                              size: 15, weight: FontWeight.w600)),
                      Text(sub,
                          style: BauhausTheme.body(
                              size: 13, color: BauhausTheme.mediumGrey)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _emptyPlans(SubscriptionProvider provider) {
    return Container(
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
    );
  }

  Widget _trustStrip() {
    const items = [
      (Icons.lock_outline, 'Secure payments via Razorpay'),
      (Icons.verified_outlined, 'Every membership personally reviewed'),
      (Icons.pause_circle_outline, 'Skip any day — just reply NO'),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: BauhausTheme.lightGrey,
        borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
      ),
      child: Column(
        children: items
            .map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(e.$1, size: 18, color: BauhausTheme.accentRed),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.$2,
                            style: BauhausTheme.body(
                                size: 13,
                                color: BauhausTheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final VoidCallback onSelect;

  const _PlanCard(
      {required this.plan, required this.onSelect});

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
                // Anchor pricing: the admin-set "normal" price is struck
                // through and the saving is shown as a % pill — the exact
                // discount is fully admin-editable (compare-at price).
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
                // Value anchor: the per-meal cost feels far smaller than the
                // plan total and re-frames the decision as a daily habit.
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
                            child: Text(f,
                                style: BauhausTheme.body(size: 13.5)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onSelect,
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

