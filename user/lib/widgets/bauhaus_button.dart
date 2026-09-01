import 'package:flutter/material.dart';
import '../theme/bauhaus_theme.dart';

/// Primary terracotta CTA — rounded, soft, inviting.
class BauhausButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final double height;
  final double? width;
  final IconData? icon;

  const BauhausButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.height = 52,
    this.width,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = isDisabled || isLoading;
    return SizedBox(
      height: height,
      width: width ?? double.infinity,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: BauhausTheme.accentRed,
          foregroundColor: BauhausTheme.onAccent,
          disabledBackgroundColor: BauhausTheme.surfaceContainerHigh,
          disabledForegroundColor: BauhausTheme.mediumGrey,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(BauhausTheme.onAccent),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Secondary action — charcoal outline on the off-white surface.
class BauhausOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final double? width;
  final Color? borderColor;

  const BauhausOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.height = 52,
    this.width,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width ?? double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: BauhausTheme.primaryBlack,
          side: BorderSide(
              color: borderColor ?? BauhausTheme.primaryBlack, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(BauhausTheme.primaryBlack),
                ),
              )
            : Text(label),
      ),
    );
  }
}
