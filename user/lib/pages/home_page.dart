import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/menu_item.dart';
import '../providers/menu_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/gym_membership_provider.dart';
import '../providers/theme_config_provider.dart';
import '../theme/bauhaus_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/floating_cart_bar.dart';
import '../widgets/logo_loader.dart';
import '../widgets/promo_banner_carousel.dart';
import 'order_tracking_page.dart';

/// Digital menu — "Modern Bistro" / Epicurean Minimalist design.
class HomePage extends StatefulWidget {
  final int initialTab;
  const HomePage({super.key, this.initialTab = 0});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _selectedTab;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _menuScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    Future.microtask(() {
      if (!mounted) return;
      context.read<MenuProvider>().fetchAll();
      context.read<MenuProvider>().fetchFeaturedLabel();
      final gold = context.read<GymMembershipProvider>();
      if (gold.isMemberLoggedIn) {
        gold.loadMemberData();
      } else {
        gold.fetchPlans();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _menuScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmExit(BuildContext context) async {
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
      child: Scaffold(
      backgroundColor: BauhausTheme.background,
      appBar: AppBar(
        backgroundColor: BauhausTheme.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 40),
            const SizedBox(width: 8),
            Consumer<ThemeConfigProvider>(
              builder: (context, themeCfg, child) => Text(
                'PROTI BOWLS',
                style: themeCfg.getLogoStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF007A3D),
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Consumer<GymMembershipProvider>(
            builder: (context, gold, _) => IconButton(
              tooltip: gold.isMemberLoggedIn ? 'Gold membership' : 'Log in',
              icon: gold.isMemberLoggedIn
                  ? const Icon(Icons.workspace_premium,
                      color: Color(0xFFD4A017))
                  : const Icon(Icons.account_circle_outlined, size: 30, color: BauhausTheme.surfaceBlack),
              onPressed: () => context.go('/member/gold'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          _selectedTab == 0
              ? _buildMenuTab(context)
              : const OrderTrackingPage(),
          Consumer<CartProvider>(
            builder: (context, cart, _) => Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: FloatingCartBar(
                  itemCount: cart.itemCount, total: cart.total),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        active: _selectedTab == 0 ? AppTab.menu : AppTab.orders,
        onMenu: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedTab = 0);
          });
        },
        onSearch: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedTab = 0);
            Future.delayed(const Duration(milliseconds: 50), () async {
              if (!mounted) return;
              if (_menuScrollCtrl.hasClients) {
                await _menuScrollCtrl.animateTo(
                  0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              }
              if (!mounted) return;
              _searchFocus.requestFocus();
            });
          });
        },
      ),
      ),
    );
  }

  // ── MENU TAB ─────────────────────────────────────────────────────────────
  Widget _buildMenuTab(BuildContext context) {
    return Consumer<MenuProvider>(
      builder: (context, menu, _) {
        if (menu.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final searching = _searchCtrl.text.isNotEmpty;
        final featured = _featuredItems(menu);
        final exampleItem = featured.isNotEmpty ? featured.first : null;

        return RefreshIndicator(
          onRefresh: () => menu.fetchAll(),
          color: BauhausTheme.accentRed,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return ListView(
                controller: _menuScrollCtrl,
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  // ── GOLD SAVINGS BANNER ──────────────────────────────
                  if (!searching)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _GoldSavingsBanner(exampleItem: exampleItem),
                    ),

                  // ── HERO ───────────────────────────────────────────
                  if (featured.isNotEmpty && !searching)
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: SizedBox(
                        height: 280,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: featured.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, i) => _HeroCard(
                            item: featured[i],
                            width: w > 480 ? 380 : w * 0.85,
                            label: menu.featuredLabel,
                          ),
                        ),
                      ),
                    ),

                  // ── SEARCH ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: BauhausTheme.primaryBlack),
                      onChanged: (v) {
                        menu.setSearchQuery(v);
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: 'Search our menu...',
                        hintStyle: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: BauhausTheme.onSurfaceVariant),
                        prefixIcon: const Icon(Icons.search,
                            color: BauhausTheme.onSurfaceVariant, size: 22),
                        suffixIcon: searching
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: BauhausTheme.onSurfaceVariant,
                                    size: 20),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  menu.setSearchQuery('');
                                  setState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: BauhausTheme.lightGrey,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(BauhausTheme.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(BauhausTheme.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(BauhausTheme.radiusMd),
                          borderSide: const BorderSide(
                              color: BauhausTheme.accentRed, width: 1.5),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                  // ── CATEGORY PILLS ─────────────────────────────────
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      children: [
                        for (final cat in menu.categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _categoryPill(
                              cat,
                              menu.selectedCategory == cat,
                              () => menu.selectCategory(cat),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── SECTIONS ───────────────────────────────────────
                  // (promo banners are injected mid-list by _buildSections)
                  if (menu.filteredItems.isEmpty)
                    _emptyState()
                  else
                    ..._buildSections(menu, w, showBanners: !searching),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<MenuItem> _featuredItems(MenuProvider menu) {
    // Every item the admin has starred as a Featured Creation — shown as a
    // horizontal scroller. Empty when none are featured.
    return menu.items.where((i) => i.featured).toList();
  }

  List<Widget> _buildSections(MenuProvider menu, double width,
      {bool showBanners = false}) {
    // Group filtered items by category, preserving the provider's order.
    final items = menu.filteredItems;
    final order = menu.categories.where((c) => c != 'All').toList();
    final grouped = <String, List<MenuItem>>{};
    for (final it in items) {
      grouped.putIfAbsent(it.category, () => []).add(it);
    }
    final cats = [
      ...order.where(grouped.containsKey),
      ...grouped.keys.where((c) => !order.contains(c)),
    ];

    final cols = width < 600 ? 1 : (width < 1000 ? 2 : 3);
    const gutter = 16.0;
    final cardW =
        (width - 40 - (gutter * (cols - 1))) / cols; // 20px side padding

    // The promo banners sit MID-PAGE: after roughly half of the category
    // sections, so the menu leads and the subscription pitch appears once
    // the visitor is already engaged (not as a front-door ad).
    final bannerAfter = (cats.length / 2).ceil(); // 1 cat → after it

    return [
      for (var i = 0; i < cats.length; i++) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: _sectionHeader(cats[i]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: gutter,
            runSpacing: gutter,
            children: [
              for (final item in grouped[cats[i]]!)
                SizedBox(
                  width: cols == 1 ? double.infinity : cardW,
                  child: _MenuCard(item: item),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (showBanners && i + 1 == bannerAfter)
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 8),
            child: PromoBannerCarousel(),
          ),
      ],
    ];
  }

  Widget _sectionHeader(String title) => Container(
        width: double.infinity,
        padding: const EdgeInsets.only(bottom: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom:
                BorderSide(color: BauhausTheme.outline, width: 1),
          ),
        ),
        child: Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: BauhausTheme.primaryBlack,
            height: 1.3,
          ),
        ),
      );

  Widget _categoryPill(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: selected
              ? BauhausTheme.surfaceBlack // primary #0a0a0a
              : BauhausTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(BauhausTheme.radiusPill),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: selected
                ? BauhausTheme.onAccent
                : BauhausTheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            const Icon(Icons.search_off,
                size: 48, color: BauhausTheme.outline),
            const SizedBox(height: 12),
            Text('No items found',
                style: BauhausTheme.body(
                    size: 15, color: BauhausTheme.mediumGrey)),
          ],
        ),
      );

}

// ─────────────────────────────────────────────────────────────────────────────
// Gold savings teaser — shown to non-members, links to the Gold sales page.
// ─────────────────────────────────────────────────────────────────────────────
class _GoldSavingsBanner extends StatelessWidget {
  final MenuItem? exampleItem;
  const _GoldSavingsBanner({this.exampleItem});

  @override
  Widget build(BuildContext context) {
    final gold = context.watch<GymMembershipProvider>();
    if (gold.isMemberLoggedIn || gold.plans.isEmpty) {
      return const SizedBox.shrink();
    }
    final plan = gold.plans.first;
    if (plan.discountPercent <= 0) return const SizedBox.shrink();

    final item = exampleItem;
    final discounted =
        item != null ? item.price * (1 - plan.discountPercent / 100) : null;

    return InkWell(
      borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
      onTap: () => context.go('/member/gold'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFF9D423), Color(0xFFD4A017)],
          ),
          borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gold members save ${plan.discountPercent.toStringAsFixed(0)}%'
                    '${plan.freeDelivery ? ' + free delivery' : ''}',
                    style: BauhausTheme.body(
                        size: 13, weight: FontWeight.w700, color: Colors.white),
                  ),
                  if (item != null && discounted != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Text(item.price <= 0 ? 'FREE' : '₹${item.price.toStringAsFixed(0)}',
                              style: BauhausTheme.body(
                                size: 12,
                                color: Colors.white70,
                              ).copyWith(
                                  decoration: item.price <= 0 ? null : TextDecoration.lineThrough)),
                          const SizedBox(width: 6),
                          Text('₹${discounted.toStringAsFixed(0)} with Gold',
                              style: BauhausTheme.body(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero — featured creation
// ─────────────────────────────────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  final MenuItem item;
  final double width;
  final String label;
  const _HeroCard({
    required this.item,
    this.width = double.infinity,
    this.label = "TODAY'S SPECIAL",
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => pushWithLogoLoader(context, '/product/${item.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 280,
          width: width,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.imageUrl != null)
                CachedNetworkImage(
                  imageUrl: item.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: BauhausTheme.lightGrey),
                  errorWidget: (_, __, ___) => Container(
                    color: BauhausTheme.lightGrey,
                    child: const Icon(Icons.restaurant_menu,
                        color: BauhausTheme.mediumGrey, size: 48),
                  ),
                )
              else
                Container(color: BauhausTheme.surfaceContainerHigh),
              // gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu card — exact Epicurean card
// ─────────────────────────────────────────────────────────────────────────────
class _MenuCard extends StatefulWidget {
  final MenuItem item;
  const _MenuCard({required this.item});

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  bool _added = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onAdd(CartProvider cart) {
    cart.addItem(widget.item);
    setState(() => _added = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _added = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      decoration: BoxDecoration(
        color: BauhausTheme.white,
        borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
        boxShadow: BauhausTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          GestureDetector(
            onTap: () => pushWithLogoLoader(context, '/product/${item.id}'),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: BauhausTheme.lightGrey),
                      errorWidget: (_, __, ___) => Container(
                        color: BauhausTheme.lightGrey,
                        child: const Icon(Icons.restaurant_menu,
                            color: BauhausTheme.mediumGrey),
                      ),
                    )
                  else
                    Container(
                      color: BauhausTheme.lightGrey,
                      child: const Icon(Icons.restaurant_menu,
                          color: BauhausTheme.mediumGrey),
                    ),
                  if (item.isSoldOut)
                    Container(
                      color: Colors.black.withValues(alpha: 0.5),
                      alignment: Alignment.center,
                      child: Text('SOLD OUT',
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2)),
                    ),
                ],
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => pushWithLogoLoader(context, '/product/${item.id}'),
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: BauhausTheme.primaryBlack,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (item.discountPercent > 0)
                          Text(
                            '₹${item.compareAtPrice.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: BauhausTheme.mediumGrey,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        Text(
                          item.price <= 0 ? 'FREE' : '₹${item.price.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: item.price <= 0 ? Colors.green.shade700 : BauhausTheme.accentRed,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (item.discountPercent > 0)
                          Text(
                            'SAVE ${item.discountPercent}%',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2E7D32),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: BauhausTheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in item.tags.take(3)) _dietTag(tag),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _addButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dietTag(String tag) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: BauhausTheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          tag.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: BauhausTheme.onSurfaceVariant,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _addButton() {
    return Consumer<CartProvider>(
      builder: (context, cart, _) {
        if (widget.item.isSoldOut) {
          return SizedBox(
            width: double.infinity,
            height: 46,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: BauhausTheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(BauhausTheme.radiusSm),
              ),
              child: Center(
                child: Text('Sold Out',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: BauhausTheme.mediumGrey)),
              ),
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: () => _onAdd(cart),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _added ? const Color(0xFF474746) : BauhausTheme.accentRed,
              foregroundColor: BauhausTheme.onAccent,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BauhausTheme.radiusSm),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_added ? Icons.check : Icons.add_shopping_cart,
                    size: 20),
                const SizedBox(width: 8),
                Text(
                  _added ? 'Added' : 'Add to Cart',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
