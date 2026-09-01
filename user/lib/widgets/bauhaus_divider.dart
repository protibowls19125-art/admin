import 'package:flutter/material.dart';
import '../theme/bauhaus_theme.dart';

/// Light hairline used sparingly to separate list items / sections.
class BauhausDivider extends StatelessWidget {
  final double thickness;
  final double height;
  final bool isStriped; // retained for API compatibility; rendered as hairline
  final Color? color;

  const BauhausDivider({
    super.key,
    this.thickness = 1,
    this.height = 24,
    this.isStriped = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor = color ?? BauhausTheme.patternGrey;
    return SizedBox(
      height: height,
      child: Center(
        child: Container(
          height: thickness,
          color: lineColor,
        ),
      ),
    );
  }
}
