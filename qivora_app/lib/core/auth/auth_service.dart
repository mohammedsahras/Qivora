import 'password_service.dart';
import 'auth_repository.dart';

class AuthService {
  final AuthRepository repo;
  final PasswordService passwords;
  AuthService(this.repo, this.passwords);

  Future<void> register(String username, String email, String phone, String password) async {
    final hash = passwords.hash(password);
    await repo.register(username: username, email: email, phone: phone, passwordHash: hash);
  }

  Future<bool> login(String identifier, String password) async {
    final user = await repo.findByIdentifier(identifier);
    if (user == null) return false;
    final hash = user['password_hash'] as String?;
    if (hash == null) return false;
    return passwords.verify(password, hash);
  }
}
