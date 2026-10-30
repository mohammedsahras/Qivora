import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/widgets/qivora_primary_button.dart';


class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _u = TextEditingController();
  final _e = TextEditingController();
  final _ph = TextEditingController();
  final _pw = TextEditingController();
  final _cpw = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    if (_pw.text != _cpw.text) { setState(() => _error = 'Passwords do not match'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authServiceProvider).register(_u.text.trim(), _e.text.trim(), _ph.text.trim(), _pw.text);
      if (mounted) context.go('/login');
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _u, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: _e, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _ph, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: _pw, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            TextField(controller: _cpw, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm Password')),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            QivoraPrimaryButton(label: 'Register', loading: _loading, onPressed: _register),
          ],
        ),
      ),
    );
  }
}
