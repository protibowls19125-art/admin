import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/bauhaus_theme.dart';

/// Persistent floating "View Cart" bar — a charcoal pill that hovers over the
/// menu with a soft shadow, terracotta count badge, and running total.
class FloatingCartBar extends StatelessWidget {
  final int itemCount;
  final double total;

  const FloatingCartBar({
    super.key,
    required this.itemCount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: itemCount > 0 ? Offset.zero : const Offset(0, 1.4),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: itemCount > 0 ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () => context.go('/order'),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: BauhausTheme.surfaceBlack,
              borderRadius: BorderRadius.circular(16),
              boxShadow: BauhausTheme.floatingShadow,
            ),
            child: Row(
              children: [
                // Basket + count badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_basket_outlined,
                        color: BauhausTheme.white, size: 24),
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BauhausTheme.accentRed,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: BauhausTheme.surfaceBlack, width: 2),
                        ),
                        child: Text(
                          '$itemCount',
                          style: BauhausTheme.body(
                            size: 9,
                            weight: FontWeight.w800,
                            color: BauhausTheme.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$itemCount ${itemCount == 1 ? 'Item' : 'Items'}',
                        style: BauhausTheme.body(
                          size: 11,
                          weight: FontWeight.w600,
                          color: BauhausTheme.white.withValues(alpha: 0.7),
                          spacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        total <= 0 ? 'FREE' : '₹${total.toStringAsFixed(0)}',
                        style: BauhausTheme.body(
                          size: 17,
                          weight: FontWeight.w600,
                          color: BauhausTheme.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: BauhausTheme.white,
                    borderRadius:
                        BorderRadius.circular(BauhausTheme.radiusMd),
                  ),
                  child: Text(
                    'View Cart',
                    style: BauhausTheme.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: BauhausTheme.primaryBlack,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
