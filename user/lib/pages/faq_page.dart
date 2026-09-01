import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../theme/bauhaus_theme.dart';

/// Help & FAQ for customers — common payment/order questions, plus an
/// admin-configurable support phone number.
class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  String _phone = '';
  String _note = '';

  static const _faqs = [
    {
      'q': 'My money was deducted but the order isn\'t confirmed. What do I do?',
      'a': 'If an amount was deducted but you didn\'t receive an order '
          'confirmation, the payment didn\'t complete verification — so no order '
          'was created and you are not charged. Any such amount is automatically '
          'refunded by your bank / UPI app, usually within 5–7 working days. If '
          'it doesn\'t reflect back, contact us with your payment reference '
          '(UTR / transaction ID).',
    },
    {
      'q': 'Can I cancel or get a refund after my order is confirmed?',
      'a': 'No. Once the restaurant confirms your order, preparation begins '
          'right away — so a confirmed order cannot be cancelled or refunded. '
          'You can cancel only while the order is still in the "Pending" stage '
          '(before it is confirmed).',
    },
    {
      'q': 'How do I cancel an order?',
      'a': 'Open "My Orders" and tap "Cancel Order" while the order is still '
          'Pending. Delivery orders are paid online in advance and cannot be '
          'self-cancelled — please call support for those.',
    },
    {
      'q': 'How do I track my order?',
      'a': 'Go to "My Orders" for live status: Pending → Confirmed → Preparing '
          '→ Completed (delivery orders also show Prepared → In Transit → '
          'Delivered).',
    },
    {
      'q': 'My online payment failed. Was I charged?',
      'a': 'A failed payment does not create an order. If any amount shows as '
          'deducted, it auto-reverses within a few working days. Just try '
          'placing the order again.',
    },
    {
      'q': 'Why can\'t I pick Dine-in / Takeaway / Delivery right now?',
      'a': 'Each order type has its own service hours. A greyed-out option is '
          'outside its available time — the hours are shown beneath it.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', 'support_contact')
          .maybeSingle();
      final v = (res?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted) {
        setState(() {
          _phone = (v['phone'] as String?) ?? '';
          _note = (v['hours_note'] as String?) ?? '';
        });
      }
    } catch (_) {/* leave empty */}
  }

  void _call() {
    if (_phone.isEmpty) return;
    launchUrl(
      Uri.parse('tel:$_phone'),
      webOnlyWindowName: '_blank',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: BauhausTheme.primaryBlack),
          onPressed: () => context.go('/'),
        ),
        title: Text('HELP & FAQ',
            style: BauhausTheme.heading(size: 20, weight: FontWeight.w800)),
        backgroundColor: BauhausTheme.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._faqs.map((f) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: BauhausTheme.patternGrey),
                  borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
                ),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    title: Text(f['q']!,
                        style: GoogleFonts.inter(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(f['a']!,
                            style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: BauhausTheme.mediumGrey,
                                height: 1.5)),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BauhausTheme.primaryBlack,
              borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('STILL NEED HELP?',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('Call our support team for any payment or order issue.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.white70)),
                if (_note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(_note,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.white54)),
                ],
                const SizedBox(height: 12),
                if (_phone.isNotEmpty)
                  GestureDetector(
                    onTap: _call,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: BauhausTheme.accentRed,
                        borderRadius:
                            BorderRadius.circular(BauhausTheme.radiusMd),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.call, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(_phone,
                              style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  )
                else
                  Text('Support contact not set yet.',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
