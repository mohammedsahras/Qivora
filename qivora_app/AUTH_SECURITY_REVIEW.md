# Auth Security Review

- Password hashing uses bcrypt (maintained package).
- No plaintext stored in new code.
- Forgot password is honest: no email sent (backend not configured).
- Local SQLite auth not production-grade; documented.
- Existing users with NULL password_hash not auto-authenticated.
- chats_test hang unresolved.
