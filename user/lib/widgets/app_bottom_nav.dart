import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/bauhaus_theme.dart';

enum AppTab { menu, search, premium, orders }

/// The persistent bottom nav — Menu / Search / Premium / Orders — shared by
/// every top-level page so a member never loses access to the rest of the
/// app while inside the Premium/member area.
class AppBottomNav extends StatelessWidget {
  final AppTab active;
  final VoidCallback? onMenu;
  final VoidCallback? onSearch;

  const AppBottomNav({
    super.key,
    required this.active,
    this.onMenu,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final isMember = context.watch<SubscriptionProvider>().isMemberLoggedIn;
    const gold = Color(0xFFD4AF37);
    return Container(
      decoration: BoxDecoration(
        color: BauhausTheme.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _item('Menu', active == AppTab.menu, const Icon(Icons.menu_book),
                  onMenu ?? () => context.go('/')),
              _item('Search', active == AppTab.search, const Icon(Icons.search),
                  onSearch ?? () => context.go('/')),
              _item(
                'Premium',
                active == AppTab.premium,
                // Both branches are literal Icon(Icons.x) calls so the web
                // build's icon tree-shaker can still find and keep them —
                // passing IconData through a variable makes it invisible to
                // that static analysis and the glyph silently disappears.
                isMember
                    ? const Icon(Icons.workspace_premium)
                    : const Icon(Icons.account_circle),
                () => context.go('/member'),
                activeColor: gold,
              ),
              _item('Orders', active == AppTab.orders,
                  const Icon(Icons.receipt_long), () => context.go('/menu')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(String label, bool isActive, Icon icon, VoidCallback onTap,
      {Color activeColor = BauhausTheme.accentRed}) {
    final color = isActive ? activeColor : BauhausTheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTheme.merge(
              data: IconThemeData(color: color, size: 24),
              child: icon,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
