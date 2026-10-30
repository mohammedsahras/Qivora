# Qivora Feature Inventory & Audit Baseline

## Status
- Analyze: No issues found.
- Architecture: Flutter + Riverpod + GoRouter + SQLite (qivora.db).
- Screens inspected: splash, welcome, login, home, chats, conversation, contacts, calls, settings, privacy.
- Buttons audited: see per-screen notes (in progress).

## Implemented and verified
- SQLite database service, migrations, conversations/messages/contacts.
- Riverpod + GoRouter navigation.
- Chat list, conversation view, contacts, calls UI, settings.

## Partially implemented
- WebRTC calls (requires physical devices + STUN/TURN).
- Status, groups (files not present — not implemented).
- Real-time messaging (local only).

## Blocked by configuration
- Debug APK build (Kotlin daemon cache issue, environment).
- Release signing (no credentials, by requirement).
- Push notifications (no FCM config).

## Not implemented
- Status feature, groups, profile editing, chat wallpaper, app lock, block/report, QR sharing, translation, privacy controls for last seen/photo/read receipts, storage management, export/restore.

## Backend requirements
- Authenticated messaging APIs, WebSocket delivery, offline sync, secure media transfer, server-enforced group permissions, WebRTC signaling, STUN/TURN, push notifications.

## Known limitations
- Remote messaging/calls/push not verified.
- Environment build issue prevents APK generation currently.
