import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/bauhaus_theme.dart';

/// Epicurean menu card: framed food photo on a white "paper" surface with a
/// soft ambient shadow, editorial serif dish name, terracotta price, and a
/// pill dietary tag.
class BauhausCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final String price;
  final String category;
  final VoidCallback? onTap;
  final Widget? actionButton;

  const BauhausCard({
    super.key,
    this.imageUrl,
    required this.title,
    this.subtitle,
    required this.price,
    required this.category,
    this.onTap,
    this.actionButton,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: BauhausTheme.white,
          borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
          boxShadow: BauhausTheme.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null)
              AspectRatio(
                aspectRatio: 3 / 2,
                child: CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: BauhausTheme.lightGrey,
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: BauhausTheme.lightGrey,
                    child: const Icon(Icons.restaurant_menu,
                        color: BauhausTheme.mediumGrey),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: BauhausTheme.heading(
                              size: 18, weight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        price,
                        style: BauhausTheme.body(
                          size: 20,
                          weight: FontWeight.w500,
                          color: BauhausTheme.accentRed,
                          spacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: BauhausTheme.body(
                          size: 14,
                          color: BauhausTheme.mediumGrey,
                          height: 1.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (category.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: BauhausTheme.surfaceContainerHigh,
                        borderRadius:
                            BorderRadius.circular(BauhausTheme.radiusSm),
                      ),
                      child: Text(
                        category.toUpperCase(),
                        style: BauhausTheme.body(
                          size: 10,
                          weight: FontWeight.w700,
                          color: BauhausTheme.mediumGrey,
                          spacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                  if (actionButton != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: actionButton!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
