# Auth Inspection Report (Phase 1)

## Existing auth
- LoginScreen creates local user record if none exists; stores user_id in SharedPreferences. No password hashing, no registration, no recovery.

## Database
- DatabaseService singleton, sqflite ffi, schema version 9. users table has id, display_name, username, phone_number, email, etc. No password fields.

## Routing
- GoRouter; need inspect main.dart.

## State
- Riverpod ConsumerStatefulWidget.

## chats_test hang
- Unresolved; DB query before pumpWidget hangs.

## Plan
- Add auth tables/additive migrations for username/email/phone/password_hash.
- Implement screens: login, register, forgot password, reset password, profile.
- Local password hashing (bcrypt/argon2) via maintained package.
- Backend integration deferred.

No code changes yet.
