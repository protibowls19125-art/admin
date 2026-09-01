import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/theme_config_provider.dart';

/// Brief logo splash shown while opening a product page. Item data is
/// already in memory by the time this fires (no real fetch to cover) — this
/// is a deliberate transition beat, a pulse-in of the app logo, not a
/// progress indicator for actual loading work.
class _LogoPulse extends StatelessWidget {
  const _LogoPulse();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.15),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1.0),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) => Opacity(
            opacity: scale.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/logo.png', height: 72),
              const SizedBox(height: 8),
              Consumer<ThemeConfigProvider>(
                builder: (context, themeCfg, child) => Text(
                  'PROTI BOWLS',
                  style: themeCfg.getLogoStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF008039), // Subway green, darkened
                    letterSpacing: -0.2,
                    // Without a Material ancestor (this is an OverlayEntry,
                    // outside the page's Scaffold/Material tree), Text falls
                    // back to DefaultTextStyle.fallback()'s debug styling — a
                    // bright yellow double underline. Override explicitly.
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the logo pulse over the current screen, then navigates to
/// [routePath] (pushed via go_router) once the pulse-in finishes.
Future<void> pushWithLogoLoader(BuildContext context, String routePath) async {
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(builder: (_) => const _LogoPulse());
  overlay.insert(entry);

  await Future.delayed(const Duration(milliseconds: 500));
  entry.remove();
  if (context.mounted) context.push(routePath);
}
