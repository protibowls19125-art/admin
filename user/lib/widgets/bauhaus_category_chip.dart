import 'package:flutter/material.dart';
import '../theme/bauhaus_theme.dart';

/// Pill-shaped filter chip. Terracotta when active, soft neutral when idle.
class BauhausCategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double? width;

  const BauhausCategoryChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40,
        width: width,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? BauhausTheme.accentRed
              : BauhausTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(BauhausTheme.radiusPill),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: BauhausTheme.body(
            size: 14,
            weight: FontWeight.w600,
            color: isSelected ? BauhausTheme.onAccent : BauhausTheme.mediumGrey,
            spacing: 0.2,
          ),
        ),
      ),
    );
  }
}
