import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_admin_provider.dart';

/// MEAL PLANNER — admin/manager customise the subscription meals here.
/// Mirrors the dining menu-management panel, but for the SEPARATE
/// subscription catalogue (`subscription_meals`), since the subscription
/// model runs its own kitchen while sharing the single customer website.
///
///   MEAL LIBRARY — CRUD dishes: photo, description, preference, macros.
///   DAILY MENU   — assign the dish served on a date, per food preference.
///                  Feeds the KDS, the member app and the WhatsApp message.
class SubscriptionMealsPage extends StatefulWidget {
  const SubscriptionMealsPage({super.key});

  @override
  State<SubscriptionMealsPage> createState() => _SubscriptionMealsPageState();
}

class _SubscriptionMealsPageState extends State<SubscriptionMealsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  // Same-day cycle: the reminder asks about today's meal, so today's menu
  // is what a manager schedules by default (see send-daily-meal-whatsapp).
  DateTime _menuDate = DateTime.now();

  // Preset palette for food preference tags — admin picks a name, not a raw
  // color value. Keep in sync with _colorFor's fallback list.
  static const _palette = {
    'green': Colors.green,
    'red': Colors.red,
    'orange': Colors.orange,
    'teal': Colors.teal,
    'purple': Colors.purple,
    'blue': Colors.blue,
    'brown': Colors.brown,
    'pink': Colors.pink,
    'indigo': Colors.indigo,
    'blueGrey': Colors.blueGrey,
  };
  Color _colorFor(String? name) => _palette[name] ?? Colors.blueGrey;

  @override
  void initState() {
    super.initState();
    final p = context.read<SubscriptionAdminProvider>();
    p.fetchMealLibrary();
    p.fetchFoodPreferences();
    p.fetchSchedule(_menuDate);
    _tabs.addListener(() {
      if (mounted) setState(() {});
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
        title: Text('MEAL PLANNER',
            style:
                GoogleFonts.chivo(fontSize: 20, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/subs'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () {
              p.fetchMealLibrary();
              p.fetchFoodPreferences();
              p.fetchSchedule(_menuDate);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.black87,
          indicatorColor: Colors.black87,
          labelStyle: GoogleFonts.chivo(fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: 'MEAL LIBRARY (${p.mealLibrary.length})'),
            const Tab(text: 'DAILY MENU'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _dishDialog(),
              icon: const Icon(Icons.add),
              label: Text('NEW DISH',
                  style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [_libraryTab(p), _dailyMenuTab(p)],
      ),
    );
  }

  // ── MEAL LIBRARY ───────────────────────────────────────────────────────────

  Widget _libraryTab(SubscriptionAdminProvider p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        _foodPreferencesCard(p),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Import from Gym Menu'),
                content: const Text(
                    'This will copy all active dishes from your Gym restaurant '
                    'menu into the Subscription meal library. Existing '
                    'subscription dishes with the same name will be skipped.\n\n'
                    'Proceed?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('IMPORT')),
                ],
              ),
            );
            if (ok != true || !mounted) return;
            final result = await p.importFromGymMenu();
            if (result != null) {
              _toast(result, ok: !result.startsWith('Could not'));
            }
          },
          icon: const Icon(Icons.file_download),
          label: const Text('IMPORT FROM GYM MENU'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[50],
            foregroundColor: Colors.blue[800],
            elevation: 0,
          ),
        ),
        const SizedBox(height: 10),
        if (p.mealLibrary.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text('No dishes yet — add your first one',
                  style: GoogleFonts.chivo(
                      fontSize: 15, color: Colors.grey[600])),
            ),
          )
        else
          ...List.generate(p.mealLibrary.length, (i) {
        final dish = p.mealLibrary[i];
        final prefRow = p.foodPreferences.firstWhere(
          (x) => x['key'] == dish['food_preference'],
          orElse: () => const {'label': 'ALL DIETS', 'color': 'blueGrey'},
        );
        final prefLabel = prefRow['label'] as String;
        final prefColor = _colorFor(prefRow['color'] as String?);
        final img = (dish['image_url'] ?? '') as String;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: img.isNotEmpty
                      ? Image.network(img,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imgPlaceholder())
                      : _imgPlaceholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dish['name'] as String? ?? '',
                          style: GoogleFonts.chivo(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      if ((dish['description'] ?? '').toString().isNotEmpty)
                        Text(dish['description'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 12.5, color: Colors.grey[700])),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          _chip(prefLabel, prefColor),
                          if ((dish['kcal'] ?? 0) != 0)
                            _chip('${dish['kcal']} KCAL', Colors.blueGrey),
                          if ((dish['protein'] ?? 0) != 0)
                            _chip('${dish['protein']}g PROTEIN', Colors.indigo),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: dish['active'] != false,
                  onChanged: (v) async {
                    final err = await p
                        .saveMealDish({'id': dish['id'], 'active': v});
                    if (err != null) _toast(err, ok: false);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _dishDialog(dish: dish),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(dish),
                ),
              ],
            ),
          ),
        );
      }),
      ],
    );
  }

  Widget _foodPreferencesCard(SubscriptionAdminProvider p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('FOOD PREFERENCES',
                    style: GoogleFonts.chivo(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _foodPreferenceDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('NEW'),
                ),
              ],
            ),
            if (p.foodPreferences.isEmpty)
              Text('No dietary categories yet — add your first one',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: Colors.grey[600]))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: p.foodPreferences.map((f) {
                  final color = _colorFor(f['color'] as String?);
                  return InputChip(
                    label: Text(f['label'] as String,
                        style: GoogleFonts.chivo(
                            fontSize: 11, fontWeight: FontWeight.w800)),
                    backgroundColor: color.withValues(alpha: 0.12),
                    avatar: CircleAvatar(backgroundColor: color, radius: 6),
                    onPressed: () => _foodPreferenceDialog(pref: f),
                    onDeleted: () => _confirmDeleteFoodPreference(f),
                    deleteIcon: const Icon(Icons.close, size: 16),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteFoodPreference(Map<String, dynamic> pref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${pref['label']}"?'),
        content: const Text(
            'Dishes and members already tagged with it keep the raw value, '
            'but it won\'t be offered as a choice anymore.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final err = await context
          .read<SubscriptionAdminProvider>()
          .deleteFoodPreference(pref['id'] as String);
      if (err != null) _toast(err, ok: false);
    }
  }

  Future<void> _foodPreferenceDialog({Map<String, dynamic>? pref}) async {
    final label =
        TextEditingController(text: pref?['label'] as String? ?? '');
    String color = pref?['color'] as String? ?? 'green';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(pref == null ? 'New food preference' : 'Edit food preference'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: color,
                items: _palette.keys
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                  backgroundColor: _palette[c], radius: 7),
                              const SizedBox(width: 8),
                              Text(c),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => color = v ?? color),
                decoration: const InputDecoration(labelText: 'Color'),
              ),
            ],
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
    if (label.text.trim().isEmpty) {
      _toast('Name is required', ok: false);
      return;
    }
    final err =
        await context.read<SubscriptionAdminProvider>().saveFoodPreference({
      if (pref != null) 'id': pref['id'],
      'label': label.text.trim(),
      'color': color,
      // Machine key: derived once from the label at creation, then stable —
      // dishes/members reference it directly, so it must never change.
      if (pref == null)
        'key': label.text
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), ''),
    });
    _toast(err ?? 'Saved ✅', ok: err == null);
  }

  Widget _imgPlaceholder() => Container(
        width: 64,
        height: 64,
        color: Colors.grey[300],
        child: const Icon(Icons.restaurant, color: Colors.white70),
      );

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: GoogleFonts.chivo(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );

  Future<void> _confirmDelete(Map<String, dynamic> dish) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${dish['name']}"?'),
        content: const Text(
            'It will also disappear from any day it was scheduled on.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context
          .read<SubscriptionAdminProvider>()
          .deleteMealDish(dish['id'] as String);
    }
  }

  Future<void> _dishDialog({Map<String, dynamic>? dish}) async {
    final name = TextEditingController(text: dish?['name'] as String? ?? '');
    final desc =
        TextEditingController(text: dish?['description'] as String? ?? '');
    final kcal = TextEditingController(text: '${dish?['kcal'] ?? ''}');
    final protein = TextEditingController(text: '${dish?['protein'] ?? ''}');
    final carbs = TextEditingController(text: '${dish?['carbs'] ?? ''}');
    final fat = TextEditingController(text: '${dish?['fat'] ?? ''}');
    final serving =
        TextEditingController(text: dish?['serving_size'] as String? ?? '');
    String pref = dish?['food_preference'] as String? ?? 'all';
    Uint8List? imageBytes;
    final picker = ImagePicker();
    final foodPreferences = context.read<SubscriptionAdminProvider>().foodPreferences;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(dish == null ? 'New dish' : 'Edit dish'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Photo
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
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: imageBytes != null
                          ? Image.memory(imageBytes!, fit: BoxFit.cover)
                          : ((dish?['image_url'] ?? '')
                                  .toString()
                                  .isNotEmpty
                              ? Image.network(dish!['image_url'] as String,
                                  fit: BoxFit.cover)
                              : const Center(
                                  child: Icon(Icons.add_a_photo,
                                      color: Colors.grey))),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Dish name')),
                  TextField(
                      controller: desc,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Description')),
                  DropdownButtonFormField<String>(
                    initialValue: pref,
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('All diets')),
                      ...foodPreferences.map((f) => DropdownMenuItem(
                            value: f['key'] as String,
                            child: Text(f['label'] as String),
                          )),
                    ],
                    onChanged: (v) => setState(() => pref = v ?? 'all'),
                    decoration:
                        const InputDecoration(labelText: 'Suitable for'),
                  ),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: kcal,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'kcal'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: protein,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Protein g'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: carbs,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Carbs g'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: fat,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Fat g'))),
                  ]),
                  TextField(
                      controller: serving,
                      decoration: const InputDecoration(
                          labelText: 'Serving size (e.g. 400 g)')),
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
    if (name.text.trim().isEmpty) {
      _toast('Dish name is required', ok: false);
      return;
    }
    final err = await context.read<SubscriptionAdminProvider>().saveMealDish(
      {
        if (dish != null) 'id': dish['id'],
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'food_preference': pref,
        'kcal': int.tryParse(kcal.text) ?? 0,
        'protein': double.tryParse(protein.text) ?? 0,
        'carbs': double.tryParse(carbs.text) ?? 0,
        'fat': double.tryParse(fat.text) ?? 0,
        'serving_size': serving.text.trim(),
      },
      imageFile: imageBytes,
    );
    _toast(err ?? 'Dish saved ✅', ok: err == null);
  }

  // ── DAILY MENU ─────────────────────────────────────────────────────────────

  Widget _dailyMenuTab(SubscriptionAdminProvider p) {
    final dateLabel =
        '${_menuDate.day.toString().padLeft(2, '0')}/${_menuDate.month.toString().padLeft(2, '0')}/${_menuDate.year}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text('Menu for $dateLabel',
                style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
            subtitle: Text(
                'Add every dish available this day, per preference.',
                style: GoogleFonts.inter(fontSize: 12.5)),
            trailing: ElevatedButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _menuDate,
                  firstDate:
                      DateTime.now().subtract(const Duration(days: 7)),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                );
                if (picked != null) {
                  setState(() => _menuDate = picked);
                  p.fetchSchedule(picked);
                }
              },
              child: const Text('CHANGE DATE'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...p.foodPreferences.map((prefRow) {
          final key = prefRow['key'] as String;
          final label = prefRow['label'] as String;
          final color = _colorFor(prefRow['color'] as String?);
          final scheduled = p.scheduleByPref[key] ?? const [];
          final scheduledIds =
              scheduled.map((r) => r['meal_id'] as String).toSet();
          // Dishes suitable for this preference (its own tag, or 'all') not
          // already on the day's menu — the "+ add" picker's choices.
          final addable = p.mealLibrary
              .where((d) =>
                  d['active'] != false &&
                  !scheduledIds.contains(d['id']) &&
                  (d['food_preference'] == key ||
                      d['food_preference'] == 'all'))
              .toList();
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _chip(label, color),
                  const SizedBox(height: 10),
                  if (scheduled.isEmpty)
                    Text('No dishes added yet',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Colors.grey[600]))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: scheduled.map((row) {
                        final dish =
                            (row['subscription_meals'] as Map?)?.cast<String, dynamic>();
                        final mealId = row['meal_id'] as String;
                        return Chip(
                          label: Text(dish?['name'] as String? ?? 'Dish'),
                          backgroundColor: color.withValues(alpha: 0.12),
                          onDeleted: () async {
                            final err = await p.removeDishFromSchedule(
                                _menuDate, key, mealId);
                            if (err != null) _toast(err, ok: false);
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 8),
                  if (addable.isNotEmpty)
                    DropdownButton<String>(
                      value: null,
                      hint: const Text('+ Add dish'),
                      isDense: true,
                      items: addable
                          .map((d) => DropdownMenuItem<String>(
                                value: d['id'] as String,
                                child: Text(
                                    '${d['name']}${(d['kcal'] ?? 0) != 0 ? '  ·  ${d['kcal']} kcal' : ''}'),
                              ))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        final err =
                            await p.addDishToSchedule(_menuDate, key, v);
                        if (err != null) _toast(err, ok: false);
                      },
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

}
