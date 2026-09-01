import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/bauhaus_theme.dart';
import '../widgets/location_picker.dart';

/// Post-payment onboarding: name, mobile, food preference, health goal and
/// delivery address. Ends in a "pending approval" success state that sets a
/// clear expectation of what happens next (the manager reviews and sends the
/// member's login on WhatsApp).
class SubscriptionOnboardingPage extends StatefulWidget {
  const SubscriptionOnboardingPage({super.key});

  @override
  State<SubscriptionOnboardingPage> createState() =>
      _SubscriptionOnboardingPageState();
}

class _SubscriptionOnboardingPageState
    extends State<SubscriptionOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();

  String _preference = '';
  String _goal = '';
  bool _submitting = false;
  bool _done = false;

  // Precise delivery pin (same map picker as the delivery checkout).
  double? _pickedLat, _pickedLng;
  String? _mapsLink;

  static const _preferences = [
    ('veg', 'Vegetarian', Icons.eco_outlined),
    ('non_veg', 'Non-Vegetarian', Icons.set_meal_outlined),
    ('eggetarian', 'Eggetarian', Icons.egg_outlined),
    ('vegan', 'Vegan', Icons.spa_outlined),
  ];
  static const _goals = [
    ('weight_loss', 'Lose weight', Icons.monitor_weight_outlined),
    ('muscle_gain', 'Build muscle', Icons.fitness_center),
    ('balanced_nutrition', 'Eat balanced', Icons.balance),
    ('diabetic_friendly', 'Diabetic friendly', Icons.favorite_outline),
    ('general_fitness', 'Stay fit', Icons.directions_run),
  ];

  @override
  void dispose() {
    for (final c in [
      _name, _phone, _email, _notes, _address, _landmark, _city, _pincode
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_preference.isEmpty || _goal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please choose your food preference and health goal')));
      return;
    }
    setState(() => _submitting = true);
    final error = await context.read<SubscriptionProvider>().submitDetails(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          foodPreference: _preference,
          healthGoal: _goal,
          healthNotes: _notes.text.trim(),
          address: {
            'address': _address.text.trim(),
            'landmark': _landmark.text.trim(),
            'city': _city.text.trim(),
            'pincode': _pincode.text.trim(),
            // Map pin is optional — extra precision for the delivery agent.
            if (_pickedLat != null)
              'latitude': _pickedLat!.toStringAsFixed(7),
            if (_pickedLng != null)
              'longitude': _pickedLng!.toStringAsFixed(7),
            if (_mapsLink != null) 'maps_link': _mapsLink!,
          },
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _done = error == null;
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: BauhausTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SubscriptionProvider>();

    if (_done) return _successView();

    // Deep-link / refresh protection: no verified payment in this session.
    if (!provider.hasPaid) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Almost there'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/subscribe'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline,
                  size: 56, color: BauhausTheme.mediumGrey),
              const SizedBox(height: 12),
              Text('Please choose a plan first',
                  style: BauhausTheme.heading(size: 20)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/subscribe'),
                child: const Text('View Plans'),
              ),
            ],
          ),
        ),
      );
    }

    final plan = provider.paidPlan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tell us about you'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/subscribe'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // Payment success reassurance FIRST — anxiety reduction before
            // asking for effort (the form).
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Payment received${plan != null ? ' for ${plan.name}' : ''}. '
                      'Now help our chefs cook exactly for you.',
                      style: BauhausTheme.body(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: const Color(0xFF1B5E20)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Your details', style: BauhausTheme.heading(size: 20)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp mobile number',
                helperText:
                    'We\'ll confirm your meal on this number every evening',
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 10 ? 'Enter a valid 10-digit number' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                helperText: 'Your member login will be created on this email',
              ),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: 24),
            Text('Food preference', style: BauhausTheme.heading(size: 20)),
            const SizedBox(height: 12),
            _chipGrid(_preferences, _preference,
                (v) => setState(() => _preference = v)),
            const SizedBox(height: 24),
            Text('What\'s your goal?', style: BauhausTheme.heading(size: 20)),
            const SizedBox(height: 4),
            Text('We portion and season your meals around this.',
                style: BauhausTheme.body(
                    size: 13, color: BauhausTheme.mediumGrey)),
            const SizedBox(height: 12),
            _chipGrid(_goals, _goal, (v) => setState(() => _goal = v)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Allergies or notes (optional)',
                hintText: 'e.g. no peanuts, low spice',
              ),
            ),
            const SizedBox(height: 24),
            Text('Delivery address', style: BauhausTheme.heading(size: 20)),
            const SizedBox(height: 12),
            // Pin-on-map — identical method to the delivery checkout.
            InkWell(
              onTap: () async {
                final result =
                    await Navigator.of(context).push<LocationPickerResult>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => LocationPickerPage(
                      initialLocation: _pickedLat != null
                          ? LatLng(_pickedLat!, _pickedLng!)
                          : null,
                    ),
                  ),
                );
                if (result != null) {
                  setState(() {
                    _pickedLat = result.latitude;
                    _pickedLng = result.longitude;
                    _mapsLink = result.mapsLink;
                    if (result.addressLine.isNotEmpty &&
                        _address.text.trim().isEmpty) {
                      _address.text = result.addressLine;
                    }
                    if (result.city.isNotEmpty) _city.text = result.city;
                    if (result.pincode.isNotEmpty) {
                      _pincode.text = result.pincode;
                    }
                  });
                }
              },
              borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _pickedLat != null
                      ? const Color(0xFFE8F5E9)
                      : BauhausTheme.lightGrey,
                  borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
                ),
                child: Row(
                  children: [
                    Icon(
                      _pickedLat != null
                          ? Icons.check_circle
                          : Icons.map_outlined,
                      color: _pickedLat != null
                          ? const Color(0xFF2E7D32)
                          : BauhausTheme.accentRed,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pickedLat != null
                            ? 'Location pinned on map'
                            : 'Pin your location on map',
                        style: BauhausTheme.body(
                            size: 14, weight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: BauhausTheme.mediumGrey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration:
                  const InputDecoration(labelText: 'House / street address'),
              validator: (v) =>
                  (v == null || v.trim().length < 5) ? 'Enter your address' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _landmark,
              decoration:
                  const InputDecoration(labelText: 'Landmark (optional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'City'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _pincode,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pincode'),
                    validator: (v) =>
                        ((v ?? '').replaceAll(RegExp(r'\D'), '').length != 6)
                            ? '6 digits'
                            : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Complete My Membership'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipGrid(
    List<(String, String, IconData)> options,
    String selected,
    ValueChanged<String> onTap,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        final active = selected == o.$1;
        return InkWell(
          onTap: () => onTap(o.$1),
          borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active ? BauhausTheme.accentRed : BauhausTheme.lightGrey,
              borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(o.$3,
                    size: 18,
                    color: active ? Colors.white : BauhausTheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(o.$2,
                    style: BauhausTheme.body(
                        size: 13.5,
                        weight: FontWeight.w600,
                        color: active
                            ? Colors.white
                            : BauhausTheme.primaryBlack)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Success = clear expectations. People tolerate waiting when they know
  /// exactly what happens next (a visible "what happens now" timeline).
  Widget _successView() {
    const steps = [
      ('Payment received', 'Done — your plan is reserved.', true),
      ('Manager review', 'We personally review every membership (usually within a few hours).', false),
      ('Login on WhatsApp', 'You\'ll receive your member login and premium card.', false),
      ('First meal', 'Every evening we confirm the next day\'s meal with you.', false),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome aboard'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.verified, size: 72, color: BauhausTheme.accentRed),
          const SizedBox(height: 16),
          Text('You\'re in — pending a quick review',
              textAlign: TextAlign.center,
              style: BauhausTheme.heading(size: 24, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Thank you for joining. Here\'s exactly what happens next:',
            textAlign: TextAlign.center,
            style:
                BauhausTheme.body(size: 14, color: BauhausTheme.mediumGrey),
          ),
          const SizedBox(height: 24),
          ...steps.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      s.$3 ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: s.$3
                          ? const Color(0xFF2E7D32)
                          : BauhausTheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$1,
                              style: BauhausTheme.body(
                                  size: 15, weight: FontWeight.w600)),
                          Text(s.$2,
                              style: BauhausTheme.body(
                                  size: 13,
                                  color: BauhausTheme.mediumGrey)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => context.go('/'),
            child: const Text('Back to Menu'),
          ),
        ],
      ),
    );
  }
}
