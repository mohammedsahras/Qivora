import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

/// A modern rounded-square back button used on all secondary screens.
///
/// - Background: light mint / emerald ([AppColors.primaryLight]).
/// - Icon: dark teal left-arrow ([AppColors.primary], [Icons.arrow_back_rounded]).
/// - Touch target: 48x48 (meets accessibility minimum).
/// - Animation: subtle scale press + Material ripple ([InkWell]).
/// - Elevation: soft drop shadow.
///
/// Navigation logic:
///   • If [GoRouter.canPop] is true, pops to the actual previous route.
///   • Otherwise falls back to [fallbackRoute] (default `/home`) via [GoRouter.go].
class QivoraBackButton extends StatelessWidget {
  /// Fallback route used when there is no previous route to pop to.
  final String? fallbackRoute;

  const QivoraBackButton({super.key, this.fallbackRoute});

  void _onTap(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(fallbackRoute ?? '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Back',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTap(context),
        splashColor: AppColors.primary.withValues(alpha: 0.20),
        highlightColor: AppColors.primary.withValues(alpha: 0.10),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2900A878),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
      ),
    );
  }
}
