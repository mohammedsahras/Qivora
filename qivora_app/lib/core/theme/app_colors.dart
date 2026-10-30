import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Qivora primary brand color — a distinctive teal/green tone.
  static const primary = Color(0xFF00A878);

  /// Primary color with slight transparency for overlays.
  static const primaryLight = Color(0xFFE3F6EF);

  static const secondary = Color(0xFF64748B);
  static const accent = Color(0xFF34D399);

  /// Light-mode scaffold background.
  static const background = Color(0xFFF4FBF8);

  /// Semantic colors.
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF2563EB);

  /// Message bubbles.
  static const bubbleSent = Color(0xFFD4FCDB);
  static const bubbleReceived = Color(0xFFFFFFFF);

  /// Text colors.
  static const textMain = Color(0xFF172033);
  static const textSecondary = Color(0xFF64748B);
  static const textOnPrimary = Color(0xFFFFFFFF);

  /// Dark mode colors.
  static const darkBg = Color(0xFF0B1118);
  static const darkSurface = Color(0xFF151E27);
  static const darkBubbleSent = Color(0xFF0E7C61);
  static const darkBubbleReceived = Color(0xFF1E293B);

  /// Light-mode surface/background used by call screens and app bars.
  static const lightBackground = Color(0xFFF4FBF8);

  /// Error/danger color used for destructive actions.
  static const error = Color(0xFFEF4444);

  /// Online status indicator green.
  static const online = Color(0xFF22C55E);

  /// Divider and subtle border color.
  static const divider = Color(0xFFE2E8F0);
  static const darkDivider = Color(0xFF2D3748);

  static const gradient = LinearGradient(
    colors: [primary, Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
