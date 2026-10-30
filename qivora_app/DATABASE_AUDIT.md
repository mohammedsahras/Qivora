# Database Audit

- Schema version 10.
- users, conversations, messages, etc.
- password_hash nullable.
- Unique indexes on username/email/phone.
- No data in default db file (0 bytes) but runtime path may differ.
