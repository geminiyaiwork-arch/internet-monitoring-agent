import 'package:flutter/material.dart';

/// Branding asset (TZ UI + logo placement).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.compact = false,
    this.height = 160,
  });

  final bool compact;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/app_logo.png',
      height: compact ? 48 : height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
