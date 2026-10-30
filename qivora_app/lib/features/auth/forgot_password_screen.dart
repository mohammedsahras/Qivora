import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/qivora_primary_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _msg;

  Future<void> _send() async {
    setState(() { _loading = true; _msg = null; });
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() { _loading = false; _msg = 'Backend email provider not configured. Request not sent.'; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            if (_msg != null) Text(_msg!),
            const SizedBox(height: 24),
            QivoraPrimaryButton(label: 'Send Reset Link', loading: _loading, onPressed: _send),
            TextButton(onPressed: () => context.pop(), child: const Text('Back to Login')),
          ],
        ),
      ),
    );
  }
}
