# Auth Architecture Plan

## Components
- AuthRepository interface (local + future remote).
- AuthService for hashing/verification.
- AuthState (Riverpod) with user/session.
- GoRouter redirect based on auth state.

## Existing user migration
- Existing users have no password. They must set password via "first-time password setup" or password reset. No auto-login.

## Uniqueness
- username, email (normalized lower), phone (E.164) unique.

## Session
- Store session token in SharedPreferences? For local, store user_id + issued_at. Future: secure token from backend.

## Backend
- Repository interface allows swapping local impl with HTTP client later. No direct DB connection.
