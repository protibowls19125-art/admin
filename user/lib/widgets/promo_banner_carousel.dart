import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/bauhaus_theme.dart';

/// Auto-advancing promo banner carousel on the home page.
/// Content is 100% DB-driven (`subscription_banners`) so the manager can run
/// campaigns without a deploy. Renders nothing when there are no banners.
class PromoBannerCarousel extends StatefulWidget {
  const PromoBannerCarousel({super.key});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<PromoBannerCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionProvider>().fetchBanners();
    });
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final banners = context.read<SubscriptionProvider>().banners;
      if (banners.length < 2 || !_controller.hasClients) return;
      _page = (_page + 1) % banners.length;
      _controller.animateToPage(
        _page,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Color _hex(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF1B3A2D);
  }

  @override
  Widget build(BuildContext context) {
    final banners = context.watch<SubscriptionProvider>().banners;
    if (banners.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: banners.length,
            itemBuilder: (context, i) {
              final b = banners[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: InkWell(
                  onTap: () => context.go(b.ctaRoute),
                  borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _hex(b.bgColorHex),
                      borderRadius:
                          BorderRadius.circular(BauhausTheme.radiusLg),
                      boxShadow: BauhausTheme.cardShadow,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  b.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: BauhausTheme.heading(
                                      size: 18,
                                      weight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                                if (b.subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    b.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: BauhausTheme.body(
                                        size: 12, color: Colors.white70),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                        BauhausTheme.radiusPill),
                                  ),
                                  child: Text(
                                    b.ctaText,
                                    style: BauhausTheme.body(
                                        size: 12,
                                        weight: FontWeight.w700,
                                        color: BauhausTheme.primaryBlack),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (b.imageUrl.isNotEmpty)
                          Expanded(
                            flex: 2,
                            child: CachedNetworkImage(
                              imageUrl: b.imageUrl,
                              fit: BoxFit.cover,
                              height: double.infinity,
                              errorWidget: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (banners.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              banners.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page
                      ? BauhausTheme.accentRed
                      : BauhausTheme.outline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
