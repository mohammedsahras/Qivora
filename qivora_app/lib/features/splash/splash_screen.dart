import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  final Duration duration;
  const SplashScreen({super.key, this.duration = const Duration(seconds: 2)});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradient),
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset(
            'assets/images/qivora_logo.png',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.chat_bubble_rounded,
              size: 72,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Qivora',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Connect • Chat • Share',
              style: TextStyle(color: Colors.white70)),
        ])),
      ),
    );
  }
}
