import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

/// Wraps a routed page so hardware/gesture back always confirms before
/// exiting the app. This app only ever calls context.go() (never .push()),
/// which replaces the nav stack instead of pushing onto it — so every route
/// is a dead end with nothing left to pop, and without this guard, back
/// silently exits instead of asking. PopScope only intercepts the pop of
/// its own enclosing ModalRoute, so it has to be applied per-route (here,
/// once per GoRoute in router.dart) rather than once above the Navigator.
class ExitGuard extends StatelessWidget {
  final Widget child;
  const ExitGuard({super.key, required this.child});

  static Future<void> _confirmExit(BuildContext context) async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit app?'),
        content: const Text('Are you sure you want to exit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (shouldExit == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit(context);
      },
      child: child,
    );
  }
}
