import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';
import 'auth_service.dart';
import 'password_service.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => LocalAuthRepository());
final passwordServiceProvider = Provider<PasswordService>((ref) => PasswordService());
final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.read(authRepositoryProvider), ref.read(passwordServiceProvider)));
final authStateProvider = StateProvider<bool>((ref) => false);
