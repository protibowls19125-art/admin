import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';

/// AGENT PERFORMANCE — how many deliveries each delivery agent has done,
/// combined across both models (gym `orders` + subscription
/// `meal_confirmations` — same shared delivery_agents roster). Today / this
/// week / this month totals, plus a daily breakdown. Read-only report.
class AgentPerformancePage extends StatefulWidget {
  const AgentPerformancePage({super.key});

  @override
  State<AgentPerformancePage> createState() => _AgentPerformancePageState();
}

class _AgentPerformancePageState extends State<AgentPerformancePage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _agents = [];

  /// agentId -> list of delivery DateTimes (local), combined from both
  /// sources, within the fetched window.
  final Map<String, List<DateTime>> _deliveriesByAgent = {};

  /// How far back to pull raw rows for — enough to cover "this month" even
  /// on the 1st, plus a couple of prior weeks for the daily breakdown.
  static const _windowDays = 45;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final since = DateTime.now()
          .subtract(const Duration(days: _windowDays))
          .toIso8601String();

      final results = await Future.wait([
        SupabaseService.client.from('delivery_agents').select().order('name'),
        SupabaseService.client
            .from('orders')
            .select('delivery_agent_id, delivered_at')
            .not('delivery_agent_id', 'is', null)
            .eq('status', 'delivered')
            .gte('delivered_at', since),
        SupabaseService.client
            .from('meal_confirmations')
            .select('delivery_agent_id, delivered_at')
            .not('delivery_agent_id', 'is', null)
            .eq('status', 'delivered')
            .gte('delivered_at', since),
      ]);

      final agents = (results[0] as List).cast<Map<String, dynamic>>();
      final gymDeliveries = (results[1] as List).cast<Map<String, dynamic>>();
      final subDeliveries = (results[2] as List).cast<Map<String, dynamic>>();

      final byAgent = <String, List<DateTime>>{};
      for (final row in [...gymDeliveries, ...subDeliveries]) {
        final agentId = row['delivery_agent_id'] as String?;
        final at = DateTime.tryParse((row['delivered_at'] ?? '').toString());
        if (agentId == null || at == null) continue;
        byAgent.putIfAbsent(agentId, () => []).add(at.toLocal());
      }

      if (!mounted) return;
      setState(() {
        _agents = agents;
        _deliveriesByAgent
          ..clear()
          ..addAll(byAgent);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load delivery history: $e';
        _loading = false;
      });
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1)); // Monday
    final monthStart = DateTime(today.year, today.month, 1);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('AGENT PERFORMANCE',
            style: GoogleFonts.chivo(fontSize: 20, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: GoogleFonts.chivo(color: Colors.red[700])))
              : _agents.isEmpty
                  ? Center(
                      child: Text('No delivery agents yet',
                          style: GoogleFonts.chivo(
                              fontSize: 15, color: Colors.grey[600])),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _agents.length,
                      itemBuilder: (_, i) => _agentCard(
                          _agents[i], today, weekStart, monthStart),
                    ),
    );
  }

  Widget _agentCard(Map<String, dynamic> agent, DateTime today,
      DateTime weekStart, DateTime monthStart) {
    final id = agent['id'] as String;
    final deliveries = _deliveriesByAgent[id] ?? const <DateTime>[];

    final byDate = <DateTime, int>{};
    for (final d in deliveries) {
      final day = _dateOnly(d);
      byDate[day] = (byDate[day] ?? 0) + 1;
    }
    final todayCount = byDate[today] ?? 0;
    final weekCount = byDate.entries
        .where((e) => !e.key.isBefore(weekStart) && !e.key.isAfter(today))
        .fold<int>(0, (sum, e) => sum + e.value);
    final monthCount = byDate.entries
        .where((e) => !e.key.isBefore(monthStart) && !e.key.isAfter(today))
        .fold<int>(0, (sum, e) => sum + e.value);

    final sortedDays = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(Icons.delivery_dining,
            color: agent['active'] != false ? Colors.green : Colors.grey),
        title: Text(agent['name'] as String? ?? '',
            style: GoogleFonts.chivo(fontWeight: FontWeight.w800)),
        subtitle: Text(agent['phone'] as String? ?? '',
            style: GoogleFonts.inter(fontSize: 12)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _statChip('TODAY', todayCount, Colors.blue),
                    _statChip('THIS WEEK', weekCount, Colors.purple),
                    _statChip('THIS MONTH', monthCount, Colors.teal),
                  ],
                ),
                if (sortedDays.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('DAILY BREAKDOWN',
                      style: GoogleFonts.chivo(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey[700],
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  ...sortedDays.map((d) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}',
                                style: GoogleFonts.inter(fontSize: 13)),
                            Text('${byDate[d]} deliveries',
                                style: GoogleFonts.chivo(
                                    fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      )),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('No deliveries in the last $_windowDays days',
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: Colors.grey[600])),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: GoogleFonts.chivo(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: GoogleFonts.chivo(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                    letterSpacing: 0.5)),
          ],
        ),
      );
}
