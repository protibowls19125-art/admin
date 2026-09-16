import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import '../services/supabase_service.dart';

/// Wraps a routed page so hardware/gesture back always requires the user's
/// Supabase password before exiting the app. This prevents unauthorized exits
/// on shared kitchen tablets.
///
/// The password is verified by re-authenticating the current session against
/// Supabase Auth — if the entered password matches the logged-in employee's
/// password, the app exits. Otherwise an error is shown.
class ExitGuard extends StatelessWidget {
  final Widget child;
  const ExitGuard({super.key, required this.child});

  static Future<void> _confirmExit(BuildContext context) async {
    final user = SupabaseService.currentUser;
    final email = user?.email;

    // If not logged in, just exit (login screen doesn't need protection).
    if (email == null) {
      SystemNavigator.pop();
      return;
    }

    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? errorText;
    bool busy = false;

    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Enter password to exit'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Please enter your account password to close the app.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                  onFieldSubmitted: (_) {
                    if (!busy) {
                      _verifyAndExit(ctx, setState, formKey,
                          passwordController, email, (e) => errorText = e, (b) => busy = b);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => _verifyAndExit(ctx, setState, formKey,
                      passwordController, email, (e) => errorText = e, (b) => busy = b),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.exit_to_app),
              label: const Text('Exit'),
            ),
          ],
        ),
      ),
    );

    if (shouldExit == true) SystemNavigator.pop();
  }

  static Future<void> _verifyAndExit(
    BuildContext ctx,
    void Function(void Function()) setState,
    GlobalKey<FormState> formKey,
    TextEditingController passwordController,
    String email,
    void Function(String?) setError,
    void Function(bool) setBusy,
  ) async {
    if (!formKey.currentState!.validate()) return;

    setState(() {
      setError(null);
      setBusy(true);
    });

    try {
      // Re-authenticate with the same credentials. If the password is
      // correct this returns successfully; if wrong, it throws.
      await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: passwordController.text,
      );
      if (ctx.mounted) Navigator.pop(ctx, true);
    } catch (e) {
      final msg = e
          .toString()
          .replaceAll('AuthException: ', '')
          .replaceAll('Exception: ', '')
          .trim();
      setState(() {
        setError(msg.isEmpty ? 'Wrong password' : msg);
        setBusy(false);
      });
    }
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
