import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/widgets/qivora_primary_button.dart';


class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _loading = false;
  bool _showPw = false;
  String? _error;

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    final ok = await ref.read(authServiceProvider).login(_id.text.trim(), _pw.text);
    if (!mounted) return;
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', _id.text.trim());
      if (mounted) context.go('/home');
    } else {
      setState(() { _loading = false; _error = 'Invalid credentials'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _id, decoration: const InputDecoration(labelText: 'Username / Email / Phone')),
            const SizedBox(height: 12),
            TextField(
              controller: _pw,
              obscureText: !_showPw,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPw = !_showPw)),
              ),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            QivoraPrimaryButton(label: 'Login', loading: _loading, onPressed: _login),
            TextButton(onPressed: () => context.push('/register'), child: const Text('Create account')),
            TextButton(onPressed: () => context.push('/forgot'), child: const Text('Forgot password')),
          ],
        ),
      ),
    );
  }
}
