# Auth Database Migration Plan

- Bump schema version 9 -> 10.
- Audit shows empty DB; no conflicts.
- ALTER TABLE users ADD COLUMN password_hash TEXT.
- ADD UNIQUE indexes on username, email, phone_number where not null.
- Add password_resets table (local dev only, documented not production).
- Preserve all existing rows.
- No table drops.
- Existing users have null password_hash until set.
