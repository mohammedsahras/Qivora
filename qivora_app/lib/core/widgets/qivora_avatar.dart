import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Circular avatar with an optional online status indicator.
///
/// [imageProvider] is optional; when absent the first letter of [displayName]
/// is shown as a fallback. [online] controls the small green status dot.
class QivoraAvatar extends StatelessWidget {
  final String? displayName;
  final ImageProvider? imageProvider;
  final double radius;
  final bool online;
  final bool showOnlineIndicator;

  const QivoraAvatar({
    super.key,
    this.displayName,
    this.imageProvider,
    this.radius = 24,
    this.online = false,
    this.showOnlineIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
      backgroundImage: imageProvider,
      child: imageProvider == null &&
              displayName != null &&
              displayName!.isNotEmpty
          ? Text(
              displayName!.isEmpty ? '?' : displayName![0].toUpperCase(),
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.5,
              ),
            )
          : null,
    );

    if (!showOnlineIndicator) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        if (online)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: radius * 0.34,
              height: radius * 0.34,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? AppColors.darkBg : Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
