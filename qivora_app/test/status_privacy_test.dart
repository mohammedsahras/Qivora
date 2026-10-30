import 'package:flutter_test/flutter_test.dart';
import 'package:qivora_app/core/auth/status_privacy.dart';

void main() {
  test('my contacts rule', () {
    expect(canViewStatus(ownerId: 'me', viewerId: 'a', privacy: 'contacts', contacts: {'a'}), isTrue);
    expect(canViewStatus(ownerId: 'me', viewerId: 'b', privacy: 'contacts', contacts: {'a'}), isFalse);
  });

  test('my contacts except rule', () {
    expect(canViewStatus(ownerId: 'me', viewerId: 'a', privacy: 'except', contacts: {'a'}, except: {'a'}), isFalse);
    expect(canViewStatus(ownerId: 'me', viewerId: 'b', privacy: 'except', contacts: {'a','b'}, except: {'a'}), isTrue);
  });

  test('only share with rule', () {
    expect(canViewStatus(ownerId: 'me', viewerId: 'a', privacy: 'only', contacts: {'a'}, only: {'a'}), isTrue);
    expect(canViewStatus(ownerId: 'me', viewerId: 'b', privacy: 'only', contacts: {'a','b'}, only: {'a'}), isFalse);
  });

  test('owner always sees own status', () {
    expect(canViewStatus(ownerId: 'me', viewerId: 'me', privacy: 'contacts', contacts: {}), isTrue);
  });
}
