import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/admin_orders_provider.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';

/// Admin page to set per order-type availability windows. Saved to
/// app_config.service_hours; the customer app reads it to gate ordering.
class ServiceHoursPage extends StatefulWidget {
  const ServiceHoursPage({super.key});

  @override
  State<ServiceHoursPage> createState() => _ServiceHoursPageState();
}

class _TypeHours {
  bool enabled;
  TimeOfDay open;
  TimeOfDay close;
  // Optional evening window — e.g. a kitchen closed 3–6 PM between lunch
  // and dinner. When splitHours is off, only open/close apply (unchanged
  // behavior from before this window existed).
  bool splitHours;
  TimeOfDay open2;
  TimeOfDay close2;
  _TypeHours(this.enabled, this.open, this.close,
      {this.splitHours = false, TimeOfDay? open2, TimeOfDay? close2})
      : open2 = open2 ?? const TimeOfDay(hour: 18, minute: 0),
        close2 = close2 ?? const TimeOfDay(hour: 22, minute: 0);
}

class _ServiceHoursPageState extends State<ServiceHoursPage> {
  static const _types = ['dine_in', 'takeaway', 'delivery'];
  static const _labels = {
    'dine_in': 'Dine In',
    'takeaway': 'Takeaway',
    'delivery': 'Delivery',
  };
  final Map<String, _TypeHours> _cfg = {};
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _bizCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _gstNoCtrl = TextEditingController();
  final _gstPctCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  final _codLatCtrl = TextEditingController();
  final _codLngCtrl = TextEditingController();
  final _codRadiusMCtrl = TextEditingController();
  final _logoFontCtrl = TextEditingController();
  bool _codGeofenceEnabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _pushingToSheet = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _phoneCtrl, _noteCtrl, _bizCtrl, _addrCtrl,
      _gstNoCtrl, _gstPctCtrl, _deliveryCtrl, _footerCtrl,
      _codLatCtrl, _codLngCtrl, _codRadiusMCtrl, _logoFontCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TimeOfDay _parse(String? s, TimeOfDay fb) {
    if (s == null || !s.contains(':')) return fb;
    final p = s.split(':');
    return TimeOfDay(
        hour: int.tryParse(p[0]) ?? fb.hour,
        minute: int.tryParse(p[1]) ?? fb.minute);
  }

  String _fmt24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    try {
      final res = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', 'service_hours')
          .maybeSingle();
      final v = (res?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      for (final t in _types) {
        final m = (v[t] as Map?)?.cast<String, dynamic>() ?? {};
        _cfg[t] = _TypeHours(
          (m['enabled'] as bool?) ?? true,
          _parse(m['open'] as String?, const TimeOfDay(hour: 9, minute: 0)),
          _parse(m['close'] as String?, const TimeOfDay(hour: 21, minute: 0)),
          splitHours: (m['split_hours'] as bool?) ?? false,
          open2: _parse(m['open2'] as String?, const TimeOfDay(hour: 18, minute: 0)),
          close2: _parse(m['close2'] as String?, const TimeOfDay(hour: 22, minute: 0)),
        );
      }
      try {
        final sc = await SupabaseService.client
            .from('app_config')
            .select('value')
            .eq('key', 'support_contact')
            .maybeSingle();
        final scv = (sc?['value'] as Map?)?.cast<String, dynamic>() ?? {};
        _phoneCtrl.text = (scv['phone'] as String?) ?? '';
        _noteCtrl.text = (scv['hours_note'] as String?) ?? '';
      } catch (_) {}
      try {
        final bc = await SupabaseService.client
            .from('app_config')
            .select('value')
            .eq('key', 'bill_config')
            .maybeSingle();
        final bcv = (bc?['value'] as Map?)?.cast<String, dynamic>() ?? {};
        _bizCtrl.text = (bcv['business_name'] as String?) ?? '';
        _addrCtrl.text = (bcv['address'] as String?) ?? '';
        _gstNoCtrl.text = (bcv['gst_number'] as String?) ?? '';
        _gstPctCtrl.text = bcv['gst_percent']?.toString() ?? '';
        _deliveryCtrl.text = bcv['delivery_charge']?.toString() ?? '';
        _footerCtrl.text = (bcv['footer'] as String?) ?? '';
        _codGeofenceEnabled = (bcv['cod_geofence_enabled'] as bool?) ?? false;
        _codLatCtrl.text = bcv['cod_center_lat']?.toString() ?? '';
        _codLngCtrl.text = bcv['cod_center_lng']?.toString() ?? '';
        _codRadiusMCtrl.text = bcv['cod_radius_m']?.toString() ?? '';
      } catch (_) {}
      try {
        final lf = await SupabaseService.client
            .from('app_config')
            .select('value')
            .eq('key', 'logo_font_family')
            .maybeSingle();
        _logoFontCtrl.text = (lf?['value'] as String?) ?? '';
      } catch (_) {}
    } catch (_) {
      for (final t in _types) {
        _cfg[t] = _TypeHours(true, const TimeOfDay(hour: 9, minute: 0),
            const TimeOfDay(hour: 21, minute: 0));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final value = {
      for (final t in _types)
        t: {
          'enabled': _cfg[t]!.enabled,
          'open': _fmt24(_cfg[t]!.open),
          'close': _fmt24(_cfg[t]!.close),
          'split_hours': _cfg[t]!.splitHours,
          'open2': _fmt24(_cfg[t]!.open2),
          'close2': _fmt24(_cfg[t]!.close2),
        }
    };
    try {
      await SupabaseService.client.from('app_config').upsert(
        {'key': 'service_hours', 'value': value},
        onConflict: 'key',
      );
      await SupabaseService.client.from('app_config').upsert(
        {
          'key': 'support_contact',
          'value': {
            'phone': _phoneCtrl.text.trim(),
            'hours_note': _noteCtrl.text.trim(),
          },
        },
        onConflict: 'key',
      );
      await SupabaseService.client.from('app_config').upsert(
        {
          'key': 'bill_config',
          'value': {
            'business_name': _bizCtrl.text.trim(),
            'address': _addrCtrl.text.trim(),
            'gst_number': _gstNoCtrl.text.trim(),
            'gst_percent': double.tryParse(_gstPctCtrl.text.trim()) ?? 0,
            'delivery_charge': double.tryParse(_deliveryCtrl.text.trim()) ?? 0,
            'footer': _footerCtrl.text.trim(),
            'cod_geofence_enabled': _codGeofenceEnabled,
            'cod_center_lat': double.tryParse(_codLatCtrl.text.trim()),
            'cod_center_lng': double.tryParse(_codLngCtrl.text.trim()),
            'cod_radius_m': double.tryParse(_codRadiusMCtrl.text.trim()) ?? 0,
          },
        },
        onConflict: 'key',
      );
      
      // Parse Google Fonts URL to family name if provided
      String logoFont = _logoFontCtrl.text.trim();
      if (logoFont.isNotEmpty) {
        final RegExp urlRegExp = RegExp(r'family=([^&:]+)');
        final match = urlRegExp.firstMatch(logoFont);
        if (match != null) {
          logoFont = match.group(1)!.replaceAll('+', ' ');
          _logoFontCtrl.text = logoFont;
        }
      }
      await SupabaseService.client.from('app_config').upsert(
        {'key': 'logo_font_family', 'value': logoFont},
        onConflict: 'key',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Service hours saved ✓')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Save failed: $e'), backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pushToSheet() async {
    setState(() => _pushingToSheet = true);
    final result =
        await context.read<AdminOrdersProvider>().pushOrdersToSheetNow();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result ?? 'Push failed'),
        backgroundColor: (result ?? '').startsWith('Pushed') ? null : Colors.red,
      ));
      setState(() => _pushingToSheet = false);
    }
  }

  TimeOfDay _fieldValue(String t, String field) {
    final c = _cfg[t]!;
    switch (field) {
      case 'open':
        return c.open;
      case 'close':
        return c.close;
      case 'open2':
        return c.open2;
      default:
        return c.close2;
    }
  }

  Future<void> _pick(String t, String field) async {
    final picked = await showTimePicker(
        context: context, initialTime: _fieldValue(t, field));
    if (picked != null) {
      setState(() {
        final c = _cfg[t]!;
        switch (field) {
          case 'open':
            c.open = picked;
            break;
          case 'close':
            c.close = picked;
            break;
          case 'open2':
            c.open2 = picked;
            break;
          case 'close2':
            c.close2 = picked;
            break;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/')),
        title: Text('SETTINGS',
            style: GoogleFonts.chivo(fontSize: 18, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('SUPPORT CONTACT',
                    style: GoogleFonts.chivo(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Support phone (shown in customer Help/FAQ)',
                    hintText: '+91XXXXXXXXXX',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional, e.g. "Available 10 AM – 9 PM")',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('SERVICE HOURS',
                    style: GoogleFonts.chivo(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  "Set when each order type is available. Outside these hours, "
                  "customers can't place that order type.",
                  style: GoogleFonts.chivo(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
                ..._types.map(_card),
                const SizedBox(height: 24),
                Text('BILL / INVOICE',
                    style: GoogleFonts.chivo(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                TextField(
                  controller: _bizCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Business name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _addrCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Address', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _gstNoCtrl,
                  decoration: const InputDecoration(
                      labelText: 'GSTIN (optional)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _gstPctCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'GST % (exclusive — added at checkout)',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _deliveryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Delivery charge ₹',
                            border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _footerCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Bill footer note',
                      border: OutlineInputBorder()),
                ),
                if (context.watch<AuthProvider>().role == 'developer') ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text('USER APP LOGO FONT',
                          style: GoogleFonts.chivo(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Paste a Google Fonts link or family name exactly (e.g. 'Pacifico'). "
                    "This changes the text logo font in the User app. Leave blank for default.",
                    style:
                        GoogleFonts.chivo(fontSize: 12, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _logoFontCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Google Fonts Link or Family Name',
                        border: OutlineInputBorder(),
                        hintText: 'https://fonts.googleapis.com/css2?family=Jersey+10...'),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text('CASH ON DELIVERY ZONE',
                          style: GoogleFonts.chivo(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Switch(
                        value: _codGeofenceEnabled,
                        onChanged: (v) =>
                            setState(() => _codGeofenceEnabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _codGeofenceEnabled
                        ? "Delivery orders can pay cash only within this radius "
                          "of the kitchen. Outside it, they must pay online. Get "
                          "lat/lng by right-clicking the kitchen's spot on "
                          "Google Maps."
                        : "Off — delivery orders can't pay cash, same as before.",
                    style:
                        GoogleFonts.chivo(fontSize: 12, color: Colors.grey[700]),
                  ),
                  if (_codGeofenceEnabled) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codLatCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: 'Kitchen latitude',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _codLngCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: 'Kitchen longitude',
                                border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codRadiusMCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'COD radius (meters)',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ],
                if (['admin', 'developer']
                    .contains(context.watch<AuthProvider>().role)) ...[
                  const SizedBox(height: 24),
                  Text('ORDER EXPORT',
                      style: GoogleFonts.chivo(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    "Orders normally export to Google Sheets automatically "
                    "every night. This button runs the same job right now — "
                    "safe to press any time, including right before/after the "
                    "nightly run: it only ever pushes orders not already sent, "
                    "so nothing is ever duplicated in the sheet.",
                    style: GoogleFonts.chivo(fontSize: 12, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: _pushingToSheet ? null : _pushToSheet,
                      child: _pushingToSheet
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text('PUSH TO SHEET NOW',
                              style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('SAVE',
                            style:
                                GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card(String t) {
    final c = _cfg[t]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_labels[t]!.toUpperCase(),
                  style: GoogleFonts.chivo(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              Switch(
                  value: c.enabled,
                  onChanged: (v) => setState(() => c.enabled = v)),
            ],
          ),
          if (c.enabled) ...[
            Row(
              children: [
                Expanded(
                    child: _timeBox(c.splitHours ? 'MORNING OPEN' : 'OPEN',
                        c.open, () => _pick(t, 'open'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _timeBox(c.splitHours ? 'MORNING CLOSE' : 'CLOSE',
                        c.close, () => _pick(t, 'close'))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text('Split into morning/evening',
                      style: GoogleFonts.chivo(fontSize: 12)),
                  const Spacer(),
                  Switch(
                    value: c.splitHours,
                    onChanged: (v) => setState(() => c.splitHours = v),
                  ),
                ],
              ),
            ),
            if (c.splitHours)
              Row(
                children: [
                  Expanded(
                      child: _timeBox(
                          'EVENING OPEN', c.open2, () => _pick(t, 'open2'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _timeBox(
                          'EVENING CLOSE', c.close2, () => _pick(t, 'close2'))),
                ],
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Disabled — customers cannot order ${_labels[t]}',
                  style:
                      GoogleFonts.chivo(fontSize: 12, color: Colors.red[700])),
            ),
        ],
      ),
    );
  }

  Widget _timeBox(String label, TimeOfDay t, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.chivo(fontSize: 9, color: Colors.grey[600])),
            Text(t.format(context),
                style: GoogleFonts.chivo(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
