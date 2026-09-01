import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/subscription_admin_provider.dart';

/// No-code control room for the subscription programme:
///   PLANS             — create/edit the plans & pricing shown in the customer app
///   BANNERS           — the promo banners on the customer home page
///   WHATSAPP SETTINGS — API credentials + every automated message's text
///   WHATSAPP SEND     — manual one-off send, and the nightly automation's time
///   AGENTS            — delivery agent roster
/// Every change here is live in production without touching code.
class SubscriptionSettingsPage extends StatefulWidget {
  const SubscriptionSettingsPage({super.key});

  @override
  State<SubscriptionSettingsPage> createState() =>
      _SubscriptionSettingsPageState();
}

class _SubscriptionSettingsPageState extends State<SubscriptionSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  @override
  void initState() {
    super.initState();
    // Deferred to a microtask — fetchSubscriptions() notifies listeners
    // synchronously (before its first await), which trips Flutter's
    // "notify during build" assertion when called directly from initState.
    Future.microtask(() {
      if (!mounted) return;
      final p = context.read<SubscriptionAdminProvider>();
      p.fetchEditors();
      p.fetchSubscriptions(); // populates p.members for the WHATSAPP SEND picker
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool ok = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green[700] : Colors.red[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SubscriptionAdminProvider>();
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('SUBSCRIPTION SETTINGS',
            style:
                GoogleFonts.chivo(fontSize: 20, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/subs'),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.black87,
          indicatorColor: Colors.black87,
          isScrollable: true,
          labelStyle: GoogleFonts.chivo(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: 'PLANS'),
            Tab(text: 'BANNERS'),
            Tab(text: 'WHATSAPP SETTINGS'),
            Tab(text: 'WHATSAPP SEND'),
            Tab(text: 'AGENTS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _plansTab(p),
          _bannersTab(p),
          _whatsappSettingsTab(p),
          _whatsappSendTab(p),
          _agentsTab(p),
        ],
      ),
    );
  }

  // ── PLANS ──────────────────────────────────────────────────────────────────

  Widget _plansTab(SubscriptionAdminProvider p) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Google Form Enquiry URL ──────────────────────────────
        _EnquiryFormUrlCard(onToast: _toast),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _planDialog(),
          icon: const Icon(Icons.add),
          label: const Text('NEW PLAN'),
        ),
        const SizedBox(height: 12),
        ...p.plans.map((plan) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(
                    '${plan['name']} — ₹${plan['price']} / ${plan['duration_days']} days',
                    style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                subtitle: Text(
                    '${plan['meals_per_day']} meal(s)/day'
                    '${(plan['badge'] ?? '').toString().isNotEmpty ? ' · badge: ${plan['badge']}' : ''}'
                    '${plan['active'] == false ? ' · HIDDEN' : ''}',
                    style: GoogleFonts.inter(fontSize: 13)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: plan['active'] != false,
                      onChanged: (v) async {
                        final err = await p
                            .savePlan({'id': plan['id'], 'active': v});
                        if (err != null) _toast(err, ok: false);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _planDialog(plan: plan),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Future<void> _planDialog({Map<String, dynamic>? plan}) async {
    final name = TextEditingController(text: plan?['name'] as String? ?? '');
    final tagline =
        TextEditingController(text: plan?['tagline'] as String? ?? '');
    final desc =
        TextEditingController(text: plan?['description'] as String? ?? '');
    final price =
        TextEditingController(text: plan?['price']?.toString() ?? '');
    final comparePrice = TextEditingController(
        text: (plan?['compare_at_price'] ?? '').toString() == '0'
            ? ''
            : (plan?['compare_at_price'] ?? '').toString());
    final days =
        TextEditingController(text: plan?['duration_days']?.toString() ?? '30');
    final mealsDay =
        TextEditingController(text: plan?['meals_per_day']?.toString() ?? '1');
    final badge = TextEditingController(text: plan?['badge'] as String? ?? '');
    final features = TextEditingController(
        text: ((plan?['features'] as List?) ?? []).join('\n'));
    final sort =
        TextEditingController(text: plan?['sort_order']?.toString() ?? '0');
    final graceDays = TextEditingController(
        text: plan?['grace_days']?.toString() ?? '3');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(plan == null ? 'New plan' : 'Edit plan'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name')),
                TextField(
                    controller: tagline,
                    decoration: const InputDecoration(labelText: 'Tagline')),
                TextField(
                    controller: desc,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Description')),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Price ₹'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: comparePrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Normal price ₹',
                              helperText: 'Shows "SAVE X%"'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: days,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Days'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: mealsDay,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Meals/day'))),
                ]),
                TextField(
                    controller: badge,
                    decoration: const InputDecoration(
                        labelText: 'Badge (e.g. MOST POPULAR — optional)')),
                TextField(
                    controller: features,
                    maxLines: 5,
                    decoration: const InputDecoration(
                        labelText: 'Features — one per line')),
                TextField(
                    controller: sort,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Sort order')),
                TextField(
                    controller: graceDays,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Grace days after plan ends',
                        helperText:
                            'Members with unused meals still get the daily '
                            'WhatsApp automation for this many extra days '
                            'past end date, then expire regardless')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SAVE')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<SubscriptionAdminProvider>().savePlan({
      if (plan != null) 'id': plan['id'],
      'name': name.text.trim(),
      'tagline': tagline.text.trim(),
      'description': desc.text.trim(),
      'price': double.tryParse(price.text) ?? 0,
      'compare_at_price': double.tryParse(comparePrice.text) ?? 0,
      'duration_days': int.tryParse(days.text) ?? 30,
      'meals_per_day': int.tryParse(mealsDay.text) ?? 1,
      'badge': badge.text.trim(),
      'features': features.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'sort_order': int.tryParse(sort.text) ?? 0,
      'grace_days': int.tryParse(graceDays.text) ?? 3,
    });
    _toast(err ?? 'Plan saved ✅', ok: err == null);
  }

  // ── BANNERS ────────────────────────────────────────────────────────────────

  Widget _bannersTab(SubscriptionAdminProvider p) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ElevatedButton.icon(
          onPressed: () => _bannerDialog(),
          icon: const Icon(Icons.add),
          label: const Text('NEW BANNER'),
        ),
        const SizedBox(height: 12),
        ...p.banners.map((b) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(b['title'] as String? ?? '',
                    style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
                subtitle: Text(
                    '${b['subtitle'] ?? ''}'
                    '${b['active'] == false ? '  · HIDDEN' : ''}',
                    style: GoogleFonts.inter(fontSize: 13)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: b['active'] != false,
                      onChanged: (v) async {
                        final err = await p
                            .saveBanner({'id': b['id'], 'active': v});
                        if (err != null) _toast(err, ok: false);
                      },
                    ),
                    IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _bannerDialog(banner: b)),
                    IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => p.deleteBanner(b['id'] as String)),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Future<void> _bannerDialog({Map<String, dynamic>? banner}) async {
    final title =
        TextEditingController(text: banner?['title'] as String? ?? '');
    final subtitle =
        TextEditingController(text: banner?['subtitle'] as String? ?? '');
    final image =
        TextEditingController(text: banner?['image_url'] as String? ?? '');
    final cta = TextEditingController(
        text: banner?['cta_text'] as String? ?? 'See Plans');
    final color = TextEditingController(
        text: banner?['bg_color'] as String? ?? '#1B3A2D');
    final sort =
        TextEditingController(text: banner?['sort_order']?.toString() ?? '0');
    Uint8List? imageBytes;
    final picker = ImagePicker();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
        title: Text(banner == null ? 'New banner' : 'Edit banner'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photo — pick from device, or fall back to the URL field
                // below (e.g. an already-hosted image).
                InkWell(
                  onTap: () async {
                    final picked = await picker.pickImage(
                        source: ImageSource.gallery, maxWidth: 1200);
                    if (picked != null) {
                      final bytes = await picked.readAsBytes();
                      setState(() => imageBytes = bytes);
                    }
                  },
                  child: Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageBytes != null
                        ? Image.memory(imageBytes!, fit: BoxFit.cover)
                        : (image.text.trim().isNotEmpty
                            ? Image.network(image.text.trim(), fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image,
                                        color: Colors.grey)))
                            : const Center(
                                child: Icon(Icons.add_a_photo,
                                    color: Colors.grey))),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: title,
                    decoration:
                        const InputDecoration(labelText: 'Title (headline)')),
                TextField(
                    controller: subtitle,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Subtitle')),
                TextField(
                    controller: image,
                    onChanged: (_) => setState(() {}), // live-updates the preview above
                    decoration: const InputDecoration(
                        labelText: 'Or paste an image URL instead')),
                TextField(
                    controller: cta,
                    decoration:
                        const InputDecoration(labelText: 'Button text')),
                TextField(
                    controller: color,
                    decoration: const InputDecoration(
                        labelText: 'Background colour (hex, e.g. #1B3A2D)')),
                TextField(
                    controller: sort,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Sort order')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SAVE')),
        ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<SubscriptionAdminProvider>().saveBanner({
      if (banner != null) 'id': banner['id'],
      'title': title.text.trim(),
      'subtitle': subtitle.text.trim(),
      'image_url': image.text.trim(),
      'cta_text': cta.text.trim(),
      'bg_color': color.text.trim(),
      'sort_order': int.tryParse(sort.text) ?? 0,
    }, imageFile: imageBytes);
    _toast(err ?? 'Banner saved ✅', ok: err == null);
  }

  // ── WHATSAPP SETTINGS (credentials + message text — no sending here) ───────

  Widget _whatsappSettingsTab(SubscriptionAdminProvider p) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _CredentialsCard(provider: p, onToast: _toast),
        const SizedBox(height: 16),
        Text('MESSAGE TEMPLATES',
            style:
                GoogleFonts.chivo(fontWeight: FontWeight.w800, fontSize: 14)),
        Text(
          'Placeholders: {{name}} {{date}} {{plan}} {{meal}} {{member_code}} {{cutoff_time}}',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
        ),
        const SizedBox(height: 8),
        ...p.templates.map((t) => _TemplateCard(
              template: t,
              onSave: (text, active) async {
                final err =
                    await p.saveTemplate(t['id'] as String, text, active);
                _toast(err ?? 'Message updated ✅', ok: err == null);
              },
            )),
      ],
    );
  }

  // ── WHATSAPP SEND (manual one-off, and the automated nightly job) ──────────

  Widget _whatsappSendTab(SubscriptionAdminProvider p) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ManualSendCard(provider: p, onToast: _toast),
        const SizedBox(height: 16),
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AUTOMATED',
                    style: GoogleFonts.chivo(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  'At the time below, the system automatically '
                  'messages the covered members asking if they want '
                  'today\'s meal. Replies (YES/NO) update the kitchen '
                  'automatically.',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                const SizedBox(height: 10),
                _ReminderTimeEditor(
                  label: 'SEND TIME',
                  load: p.loadMealReminderTime,
                  save: p.saveMealReminderTime,
                  onToast: _toast,
                  savedMessage: 'Reminder time saved ✅',
                ),
                const SizedBox(height: 10),
                Text(
                  'Reply-by deadline shown in the message text '
                  '({{cutoff_time}}) — members are told to confirm before '
                  'this time.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 6),
                _ReminderTimeEditor(
                  label: 'REPLY-BY CUTOFF',
                  load: p.loadMealReminderCutoff,
                  save: p.saveMealReminderCutoff,
                  onToast: _toast,
                  savedMessage: 'Cutoff time saved ✅',
                ),
                const Divider(height: 28),
                Text('AUTO-CONFIRM',
                    style: GoogleFonts.chivo(
                        fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  'At this time, ALL members who haven\'t responded yet are '
                  'automatically confirmed (treated as YES). They\'ll appear '
                  'in Today\'s Meal for KDS push. Runs before the cutoff.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                _AutoConfirmTimeEditor(provider: p, onToast: _toast),
                const Divider(height: 28),
                Text(
                  'Meta template actually sent. do_you_need_meal_today is '
                  'now APPROVED — this should say that name. If it ever '
                  'needs to change, switch it here, no redeploy needed.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 6),
                _TemplateNameEditor(provider: p, onToast: _toast),
                const Divider(height: 28),
                Text('OFF DAYS',
                    style: GoogleFonts.chivo(
                        fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  'The automation will be completely skipped on selected days. '
                  'No WhatsApp messages will be sent and no meal confirmation '
                  'rows will be created on these days (e.g. every Sunday).',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                _OffDaysEditor(provider: p, onToast: _toast),
                const Divider(height: 28),
                Text('WHO IT COVERS',
                    style: GoogleFonts.chivo(
                        fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 8),
                _AutomationMembersEditor(provider: p, onToast: _toast),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── AGENTS ─────────────────────────────────────────────────────────────────

  Widget _agentsTab(SubscriptionAdminProvider p) {
    final name = TextEditingController();
    final phone = TextEditingController();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: name,
                        decoration:
                            const InputDecoration(labelText: 'Agent name'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: phone,
                        decoration:
                            const InputDecoration(labelText: 'Phone'))),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (name.text.trim().isEmpty) return;
                    final err = await p.addAgent(name.text.trim(), phone.text.trim());
                    if (err != null) _toast(err, ok: false);
                    name.clear();
                    phone.clear();
                  },
                  child: const Text('ADD'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...p.agents.map((a) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.delivery_dining,
                    color:
                        a['active'] != false ? Colors.green : Colors.grey),
                title: Text(a['name'] as String? ?? '',
                    style: GoogleFonts.chivo(fontWeight: FontWeight.w700)),
                subtitle: Text(a['phone'] as String? ?? ''),
                trailing: Switch(
                  value: a['active'] != false,
                  onChanged: (v) => p.toggleAgent(a['id'] as String, v),
                ),
              ),
            )),
      ],
    );
  }
}

/// Inline editor for one WhatsApp template.
class _TemplateCard extends StatefulWidget {
  final Map<String, dynamic> template;
  final Future<void> Function(String text, bool active) onSave;

  const _TemplateCard({required this.template, required this.onSave});

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  late final TextEditingController _text = TextEditingController(
      text: widget.template['message_text'] as String? ?? '');
  late bool _active = widget.template['active'] != false;
  bool _dirty = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.template['title'] as String? ?? '',
                      style: GoogleFonts.chivo(
                          fontWeight: FontWeight.w800, fontSize: 13)),
                ),
                Switch(
                  value: _active,
                  onChanged: (v) => setState(() {
                    _active = v;
                    _dirty = true;
                  }),
                ),
              ],
            ),
            TextField(
              controller: _text,
              maxLines: null,
              style: GoogleFonts.inter(fontSize: 13.5),
              onChanged: (_) => setState(() => _dirty = true),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (_dirty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ElevatedButton(
                    onPressed: () async {
                      await widget.onSave(_text.text, _active);
                      if (mounted) setState(() => _dirty = false);
                    },
                    child: const Text('SAVE MESSAGE'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Editable send time (IST) for the nightly meal-reminder WhatsApp message.
/// Stored in app_config; the edge function polls every 5 minutes and only
/// actually sends once past this time each day.
/// Checkbox list of active members with select-all/clear shortcuts. Shared by
/// the manual send card and the automation coverage editor.
class _MemberSelector extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _MemberSelector({
    required this.members,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Text('No active members yet.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () => onChanged(
                  members.map((m) => m['id'] as String).toSet()),
              child: const Text('SELECT ALL'),
            ),
            TextButton(
              onPressed: () => onChanged({}),
              child: const Text('CLEAR'),
            ),
            const Spacer(),
            Text('${selected.length} selected',
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.grey[700])),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!)),
          child: ListView(
            shrinkWrap: true,
            children: members.map((m) {
              final id = m['id'] as String;
              final name = (m['customer_name'] as String?) ?? '';
              final code = (m['member_code'] as String?) ?? '';
              return CheckboxListTile(
                dense: true,
                value: selected.contains(id),
                title: Text(name.isEmpty ? 'Unnamed member' : name,
                    style: GoogleFonts.inter(fontSize: 13)),
                subtitle: code.isEmpty
                    ? null
                    : Text(code,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey[600])),
                onChanged: (v) {
                  final next = Set<String>.from(selected);
                  v == true ? next.add(id) : next.remove(id);
                  onChanged(next);
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// MANUAL send card — everyone active, or a hand-picked subset, right now.
class _ManualSendCard extends StatefulWidget {
  final SubscriptionAdminProvider provider;
  final void Function(String, {bool ok}) onToast;

  const _ManualSendCard({required this.provider, required this.onToast});

  @override
  State<_ManualSendCard> createState() => _ManualSendCardState();
}

class _ManualSendCardState extends State<_ManualSendCard> {
  bool _useSelection = false;
  Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final members = widget.provider.members;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MANUAL',
                style: GoogleFonts.chivo(
                    fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              'Send today\'s "meal today?" question right now, '
              'regardless of the automated time below.',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _useSelection,
              title: Text(
                  _useSelection ? 'Selected members only' : 'All active members',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              onChanged: (v) => setState(() => _useSelection = v),
            ),
            if (_useSelection) ...[
              const SizedBox(height: 6),
              _MemberSelector(
                members: members,
                selected: _selected,
                onChanged: (s) => setState(() => _selected = s),
              ),
              const SizedBox(height: 10),
            ],
            ElevatedButton.icon(
              onPressed: (_useSelection && _selected.isEmpty)
                  ? null
                  : () async {
                      final msg = await widget.provider.sendTonightNow(
                        subscriptionIds:
                            _useSelection ? _selected.toList() : null,
                      );
                      widget.onToast(msg ?? 'Done');
                    },
              icon: const Icon(Icons.send),
              label: Text(_useSelection
                  ? 'SEND TO ${_selected.length} SELECTED'
                  : 'SEND TONIGHT\'S QUESTION NOW'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which members the AUTOMATED nightly run covers — persisted separately
/// from the send time so either can change independently.
class _AutomationMembersEditor extends StatefulWidget {
  final SubscriptionAdminProvider provider;
  final void Function(String, {bool ok}) onToast;

  const _AutomationMembersEditor(
      {required this.provider, required this.onToast});

  @override
  State<_AutomationMembersEditor> createState() =>
      _AutomationMembersEditorState();
}

class _AutomationMembersEditorState extends State<_AutomationMembersEditor> {
  bool _useSelection = false;
  Set<String> _selected = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.provider.loadMealReminderMembers().then((v) {
      if (!mounted) return;
      setState(() {
        _useSelection = v['mode'] == 'selected';
        _selected = Set<String>.from(v['subscriptionIds'] as List);
        _loaded = true;
      });
    });
  }

  Future<void> _save() async {
    final err = await widget.provider.saveMealReminderMembers(
      _useSelection ? 'selected' : 'all',
      _selected.toList(),
    );
    widget.onToast(err ?? 'Automation coverage saved ✅', ok: err == null);
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.provider.members;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _useSelection,
          title: Text(
              _useSelection ? 'Selected members only' : 'All active members',
              style:
                  GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
          onChanged: _loaded ? (v) => setState(() => _useSelection = v) : null,
        ),
        if (_useSelection) ...[
          const SizedBox(height: 6),
          _MemberSelector(
            members: members,
            selected: _selected,
            onChanged: (s) => setState(() => _selected = s),
          ),
          const SizedBox(height: 10),
        ],
        ElevatedButton(
          onPressed: _loaded ? _save : null,
          child: const Text('SAVE COVERAGE'),
        ),
      ],
    );
  }
}

/// Admin-editable IST time backed by app_config — used for both the nightly
/// send time and the reply-by cutoff shown in the message, so neither is
/// hardcoded in the edge function.
class _ReminderTimeEditor extends StatefulWidget {
  final String label;
  final Future<Map<String, int>> Function() load;
  final Future<String?> Function(int hour, int minute) save;
  final void Function(String, {bool ok}) onToast;
  final String savedMessage;

  const _ReminderTimeEditor({
    required this.label,
    required this.load,
    required this.save,
    required this.onToast,
    required this.savedMessage,
  });

  @override
  State<_ReminderTimeEditor> createState() => _ReminderTimeEditorState();
}

class _ReminderTimeEditorState extends State<_ReminderTimeEditor> {
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.load().then((v) {
      if (!mounted) return;
      setState(() {
        _time = TimeOfDay(hour: v['hour'] ?? 20, minute: v['minute'] ?? 0);
        _loaded = true;
      });
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final err = await widget.save(_time.hour, _time.minute);
    widget.onToast(err ?? widget.savedMessage, ok: err == null);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(widget.label,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _loaded ? _pickTime : null,
            icon: const Icon(Icons.schedule),
            label: Text(_loaded ? _time.format(context) : 'Loading…'),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _loaded ? _save : null,
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

class _TemplateNameEditor extends StatefulWidget {
  final SubscriptionAdminProvider provider;
  final void Function(String, {bool ok}) onToast;

  const _TemplateNameEditor({required this.provider, required this.onToast});

  @override
  State<_TemplateNameEditor> createState() => _TemplateNameEditorState();
}

class _TemplateNameEditorState extends State<_TemplateNameEditor> {
  final _ctrl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.provider.loadMealReminderTemplateName().then((v) {
      if (!mounted) return;
      _ctrl.text = v;
      setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      widget.onToast('Template name can\'t be empty', ok: false);
      return;
    }
    final err = await widget.provider.saveMealReminderTemplateName(name);
    widget.onToast(err ?? 'Template name saved ✅', ok: err == null);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text('TEMPLATE NAME',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: TextField(
            controller: _ctrl,
            enabled: _loaded,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'do_you_need_meal_today',
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _loaded ? _save : null,
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

/// WhatsApp Business API credentials (stored in app_config, used by the
/// automation edge functions). Filled in once the numbers arrive from Meta.
class _CredentialsCard extends StatefulWidget {
  final SubscriptionAdminProvider provider;
  final void Function(String, {bool ok}) onToast;

  const _CredentialsCard({required this.provider, required this.onToast});

  @override
  State<_CredentialsCard> createState() => _CredentialsCardState();
}

class _CredentialsCardState extends State<_CredentialsCard> {
  final _token = TextEditingController();
  final _phoneId = TextEditingController();
  bool _loaded = false;
  bool _hideToken = true;

  @override
  void initState() {
    super.initState();
    widget.provider.loadWhatsAppConfig().then((v) {
      if (!mounted) return;
      setState(() {
        _token.text = (v['access_token'] ?? '') as String;
        _phoneId.text = (v['phone_number_id'] ?? '') as String;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _token.dispose();
    _phoneId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WHATSAPP API CREDENTIALS',
                style: GoogleFonts.chivo(
                    fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              'From Meta Business → WhatsApp → API Setup. Messages start '
              'flowing automatically once these are saved.',
              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[700]),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _token,
              obscureText: _hideToken,
              enabled: _loaded,
              decoration: InputDecoration(
                labelText: 'Access token',
                suffixIcon: IconButton(
                  icon: Icon(
                      _hideToken ? Icons.visibility : Icons.visibility_off,
                      size: 20),
                  onPressed: () => setState(() => _hideToken = !_hideToken),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneId,
              enabled: _loaded,
              decoration:
                  const InputDecoration(labelText: 'Phone number ID'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                final err = await widget.provider.saveWhatsAppConfig({
                  'access_token': _token.text.trim(),
                  'phone_number_id': _phoneId.text.trim(),
                });
                widget.onToast(err ?? 'Credentials saved ✅', ok: err == null);
              },
              child: const Text('SAVE CREDENTIALS'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Day-of-week picker for skipping automation on certain days (e.g. Sundays).
/// Backed by app_config key `meal_reminder_off_days`.
class _OffDaysEditor extends StatefulWidget {
  final SubscriptionAdminProvider provider;
  final void Function(String, {bool ok}) onToast;

  const _OffDaysEditor({required this.provider, required this.onToast});

  @override
  State<_OffDaysEditor> createState() => _OffDaysEditorState();
}

class _OffDaysEditorState extends State<_OffDaysEditor> {
  // 0=Sun, 1=Mon, ..., 6=Sat — matches JS Date.getDay() used by the edge fn.
  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  Set<int> _offDays = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.provider.loadMealReminderOffDays().then((days) {
      if (!mounted) return;
      setState(() {
        _offDays = days.toSet();
        _loaded = true;
      });
    });
  }

  Future<void> _save() async {
    final err =
        await widget.provider.saveMealReminderOffDays(_offDays.toList()..sort());
    widget.onToast(err ?? 'Off-days saved ✅', ok: err == null);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _offDays.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(7, (i) {
            final selected = _offDays.contains(i);
            return FilterChip(
              label: Text(_dayLabels[i],
                  style: GoogleFonts.chivo(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Colors.black87,
                  )),
              selected: selected,
              selectedColor: Colors.red[700],
              checkmarkColor: Colors.white,
              onSelected: _loaded
                  ? (v) => setState(() {
                        v ? _offDays.add(i) : _offDays.remove(i);
                      })
                  : null,
            );
          }),
        ),
        if (sorted.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Automation OFF every: ${sorted.map((d) => _dayLabels[d]).join(', ')}',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.red[700]),
            ),
          ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _loaded ? _save : null,
          child: const Text('SAVE OFF-DAYS'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-Confirm Time Editor
// ─────────────────────────────────────────────────────────────────────────────

/// Admin-editable IST time at which unanswered meal confirmations are
/// automatically promoted to 'confirmed' (YES). Backed by app_config key
/// `meal_auto_confirm_time`. Includes an enable/disable toggle.
class _AutoConfirmTimeEditor extends StatefulWidget {
  final SubscriptionAdminProvider provider;
  final void Function(String, {bool ok}) onToast;

  const _AutoConfirmTimeEditor({required this.provider, required this.onToast});

  @override
  State<_AutoConfirmTimeEditor> createState() => _AutoConfirmTimeEditorState();
}

class _AutoConfirmTimeEditorState extends State<_AutoConfirmTimeEditor> {
  TimeOfDay _time = const TimeOfDay(hour: 11, minute: 0);
  bool _enabled = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.provider.loadAutoConfirmTime().then((v) {
      if (!mounted) return;
      setState(() {
        _time = TimeOfDay(hour: v['hour'] ?? 11, minute: v['minute'] ?? 0);
        _enabled = (v['enabled'] ?? 1) == 1;
        _loaded = true;
      });
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final err = await widget.provider
        .saveAutoConfirmTime(_time.hour, _time.minute, enabled: _enabled);
    widget.onToast(err ?? 'Auto-confirm time saved ✅', ok: err == null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(
              value: _enabled,
              onChanged: _loaded
                  ? (v) => setState(() => _enabled = v)
                  : null,
              activeTrackColor: Colors.green[700],
            ),
            Text(
              _enabled ? 'ENABLED' : 'DISABLED',
              style: GoogleFonts.chivo(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _enabled ? Colors.green[700] : Colors.grey,
              ),
            ),
          ],
        ),
        if (_enabled)
          Row(
            children: [
              SizedBox(
                width: 130,
                child: Text('AUTO-CONFIRM AT',
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loaded ? _pickTime : null,
                  icon: const Icon(Icons.schedule),
                  label: Text(_loaded ? _time.format(context) : 'Loading…'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _loaded ? _save : null,
                child: const Text('SAVE'),
              ),
            ],
          ),
        if (!_enabled)
          ElevatedButton(
            onPressed: _loaded ? _save : null,
            child: const Text('SAVE'),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Google Form Enquiry URL Card
// ─────────────────────────────────────────────────────────────────────────────

/// Admin-editable Google Form URL shown at the top of the PLANS tab.
/// Stored in `app_config` with key `subscription_enquiry_form_url`.
/// The user app reads this value and opens it when a customer taps
/// "ENQUIRE NOW" on a subscription plan card.
class _EnquiryFormUrlCard extends StatefulWidget {
  final void Function(String msg, {bool ok}) onToast;
  const _EnquiryFormUrlCard({required this.onToast});

  @override
  State<_EnquiryFormUrlCard> createState() => _EnquiryFormUrlCardState();
}

class _EnquiryFormUrlCardState extends State<_EnquiryFormUrlCard> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'subscription_enquiry_form_url')
          .maybeSingle();
      _ctrl.text = (row?['value'] as String?) ?? '';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('app_config').upsert({
        'key': 'subscription_enquiry_form_url',
        'value': _ctrl.text.trim(),
        'description': 'Google Form URL shown on subscription plan cards',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      widget.onToast('Enquiry form URL saved', ok: true);
    } catch (e) {
      widget.onToast('Failed to save: $e', ok: false);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, color: Color(0xFF1565C0), size: 20),
                const SizedBox(width: 8),
                Text('ENQUIRY FORM URL',
                    style: GoogleFonts.chivo(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1565C0))),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Customers tap "ENQUIRE NOW" on plans → this form opens.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: 'https://forms.gle/...',
                  prefixIcon: const Icon(Icons.open_in_new, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: Text(_saving ? 'SAVING...' : 'SAVE URL'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
