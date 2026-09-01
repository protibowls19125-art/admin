import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/gym_membership_provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/bauhaus_theme.dart';
import '../widgets/app_bottom_nav.dart';

/// Thin entry point for the Premium tab — Gold (gym model) or Elite
/// (subscription model). Each stays strictly scoped to its own model.
///
/// **Auto-detection**: On load, if the user is already authenticated via
/// Supabase Auth we check both `gym_memberships` and `subscriptions` tables
/// to see which membership they hold. If exactly one match is found, we
/// skip the chooser and route directly. If neither or both match (edge
/// case) we show the manual chooser.
class MemberChooserPage extends StatefulWidget {
  const MemberChooserPage({super.key});

  @override
  State<MemberChooserPage> createState() => _MemberChooserPageState();
}

class _MemberChooserPageState extends State<MemberChooserPage> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoDetect());
  }

  Future<void> _autoDetect() async {
    final gymProvider = context.read<GymMembershipProvider>();
    final subProvider = context.read<SubscriptionProvider>();

    // If not logged in at all, skip detection — show chooser immediately.
    if (!gymProvider.isMemberLoggedIn && !subProvider.isMemberLoggedIn) {
      if (mounted) setState(() => _checking = false);
      return;
    }

    // Both providers listen to onAuthStateChange and load data automatically,
    // but here we force a parallel load to ensure data is fresh right now.
    await Future.wait([
      gymProvider.loadMemberData(),
      subProvider.loadMemberData(),
    ]);

    if (!mounted) return;

    final hasGold = gymProvider.myMembership != null;
    final hasElite = subProvider.mySubscription != null;

    if (hasGold && !hasElite) {
      context.go('/member/gold');
      return;
    }
    if (hasElite && !hasGold) {
      context.go('/member/elite');
      return;
    }
    // If both or neither, show the manual chooser.
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Choose your membership',
                    style: BauhausTheme.heading(size: 22)),
                const SizedBox(height: 4),
                Text('Two ways to get more out of Proti Bowls.',
                    style: BauhausTheme.body(
                        size: 14, color: BauhausTheme.mediumGrey)),
                const SizedBox(height: 20),
                _ChoiceCard(
                  title: 'Gold',
                  subtitle: 'Discount on every gym order',
                  icon: Icons.workspace_premium,
                  gradient: const [Color(0xFFF9D423), Color(0xFFD4A017)],
                  onTap: () => context.go('/member/gold'),
                ),
                const SizedBox(height: 16),
                _ChoiceCard(
                  title: 'Elite',
                  subtitle:
                      'Daily fresh meal subscription, delivered to your door',
                  icon: Icons.card_membership,
                  gradient: const [
                    BauhausTheme.primaryBlack,
                    Color(0xFF1B3A2D)
                  ],
                  onTap: () => context.go('/member/elite'),
                ),
              ],
            ),
      bottomNavigationBar: const AppBottomNav(active: AppTab.premium),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient),
          borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
          boxShadow: BauhausTheme.cardShadow,
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: BauhausTheme.heading(
                          size: 22,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          BauhausTheme.body(size: 13, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}
