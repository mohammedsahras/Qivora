# Qivora Progress Tracker

## Schema
Schema v17 (working tree; HEAD was v13).
- v14: deduplicate `conversation_participant` rows + unique index `idx_participants_unique(conversation_id, user_id)`.
- v15: `conversations.owner_user_id` (group ownership tracking).
- v16 (Communities): new tables `communities`, `community_members` (PK community_id+user_id, role owner/admin/member, FKs CASCADE), `community_groups` (PK community_id+conversation_id), index `idx_community_members_user`.
- v17 (Status privacy): per-status privacy storage on `statuses` — `privacy TEXT DEFAULT 'all'`, `except_list TEXT`, `only_list TEXT` (added via ALTER TABLE, safe/additive; existing rows preserved). `StatusService.createStatus` persists privacy config on the row so every later access check uses the settings captured at post time.

Migrations run in `database_service.dart` (`_migrate` blocks `oldV < 14/15/16/17`); fresh schema created at v17 via `_createSchema`. Test path override via `DatabaseService.setTestDatabasePath`.

## CommunityService (lib/features/communities/community_service.dart)
- createCommunity (empty/duplicate-name rejection, creator becomes owner)
- addMember / removeMember (manager-only, duplicates rejected, owner protected, self-removal via leaveCommunity)
- leaveCommunity (transaction promotes earliest remaining member to owner; deletes empty community)
- addGroup / removeGroup (association only; removeGroup keeps the group, participants, messages)
- setMemberRole with transaction + authorization rules:
  - Owner can promote members→admin and demote admins→member.
  - Admin cannot promote/demote another admin unless explicitly authorized.
  - Admin cannot remove/demote the community owner.
  - Invalid role changes and duplicate operations rejected.

## Community UI (lib/features/communities/community_detail_screen.dart, communities_screen.dart)
- CommunityDetailScreen: info, groups (open into existing group chat), members, owner/admin role badges, permission-gated add/remove, confirmation dialogs for removals/leave, promote/demote dialog.
- Roles visible via badges. Routes /communities, /communities/detail/:id; Settings entry "Communities".
- Fix: `const Text(promote ? 'Promote' : 'Demote')` → `Text(...)` (non-constant in const constructor).

## Status privacy enforcement (lib/core/auth/status_service.dart [NEW], status_privacy.dart)
Enforcement at the data-access/service layer, not just UI:
- `visibleStatuses(db, viewerId)`: returns unexpired rows viewer is allowed to see, enforcing per-row privacy rules (all / my_contacts / my_contacts_except / only_share_with). Legacy rows without privacy metadata treated as 'all' (existing records preserved).
- **BUG FIX**: contacts cache previously did `contactsCache.putIfAbsent(ownerId, () => const <String>{}); contactsCache[ownerId] ??= await contactsOf(...)` — `putIfAbsent` inserted a default empty set so the lazy-load `??=` never fired, keeping contacts empty and privacy checks failing. Replaced with `final contacts = contactsCache[ownerId] ??= await contactsOf(db, ownerId);` (proper lazy-load) so my-contacts / except / only rules actually restrict retrieval.
- `recordStatusView(db, statusId, viewerId)`: validates viewer permission before recording; returns false for unauthorized viewers without touching `status_views`; unknown status id rejected.
- `viewsOf(db, statusId)`: viewer list (unauthorized viewers never appear because never recorded).
- Tests for every privacy mode + edges: status_privacy_test, status_access_test, status_views_test.

## Test-hang investigation (chats_test, conversation_test, contacts_test) — RESOLVED
**Verified root cause**: `sqflite_common_ffi` `databaseFactoryFfi` opens SQLite on a background isolate (`SqfliteIsolate` via `Isolate.spawn`/`SendPort`). Under `flutter_test`'s `AutomatedTestWidgetsFlutterBinding` (FakeAsync zone) that isolate round-trip never resolves, so any DB query before/during `pumpWidget` hangs. Confirmed with throwaway debug tests (deleted): static widget + DB open in test body → hang at pumpWidget; `databaseFactoryFfiNoIsolate` + DB opened in setUp → PASS; `tester.runAsync` → PASS.
**Fix direction (applied)**:
- Tests use `databaseFactory = databaseFactoryFfiNoIsolate;`.
- All test-body DB work wrapped in `await tester.runAsync(() async { ... })`; `openDb()` via `(await tester.runAsync<Database>(() => openDb()))!`.
- Per-test fresh temp DB path + `DatabaseService.instance.close()` in setUp/tearDown.
- No arbitrary delays added; no tests skipped/deleted; no assertions weakened.

## conversation_screen.dart fixes
- `_getBool` accepts bool/num (`if (v is bool) return v; if (v is num) return v.toInt() == 1; return false;`).
- `_scrollToBottom` / `_loadOlder` guard on `position.hasContentDimensions` before reading `maxScrollExtent` (content dimensions uncomputed during first layout → `maxScrollExtent` null-check crash).
- Message composer (`_buildInput` with TextField + Send button) now always rendered (moved out of the `_msgs.isEmpty` branch) so empty conversations still show the composer.
- `chats_screen.dart`: archived PopupMenu toggle now calls `_load()` after setState.

## conversation_test.dart fixes
- All `DateTime` DB inserts converted to ISO-8601 strings (sqflite FFI only supports num/String/Uint8List; raw DateTime threw `Invalid sql argument type 'DateTime'`).
- Rewritten to use `databaseFactoryFfiNoIsolate`, `TestWidgetsFlutterBinding.ensureInitialized()`, per-test GoRouter, `runAsync` wraps, extra pumps. All 5 tests now pass.

## qivora_message_bubble.dart (lib/core/widgets/qivora_message_bubble.dart) — layout crash fix
- The message bubble's outer `Column` had default `mainAxisSize: max` and contained a redundant `Flexible`; under the ListView's sliver constraints this threw "RenderFlex children have non-zero flex but incoming height constraints are unbounded" (`RenderFlex ... Column ← QivoraMessageBubble`, constraints `0.0<=h<=Infinity`), crashing every test that rendered a message.
- Fix: outer `Column(mainAxisSize: MainAxisSize.min)` and removed the redundant `Flexible` (inner column already `mainAxisSize: min`). Verified via minimal repro + scratch tests.

## Tests
- chats_test.dart: 6/6 GREEN (rewritten: databaseFactoryFfiNoIsolate, runAsync seeding).
- contacts_test.dart: 3/3 GREEN (rewritten: databaseFactoryFfiNoIsolate, runAsync, per-test GoRouter).
- conversation_test.dart: 5/5 GREEN (rewritten; scroll guards, composer always present, String timestamps).
- status_access_test / status_privacy_test / status_views_test: all GREEN (contacts-cache fix).
- communities_test: 5/5 (updated schema-version expectation 16→17).
- community_roles_test, groups_test, database_test: pass.
- **Full `flutter test`: 65 passed, 0 failed.**

## Verification results
- `flutter test`: **65 passed, 0 failed** (all test files).
- `flutter analyze`: **No issues found.**
- `flutter build apk --debug`: **Built `build/app/outputs/flutter-apk/app-debug.apk` successfully** (only Gradle/Kotlin-plugin warnings, no errors).

## git diff
`git diff --stat` (12 modified tracked files, 423 insertions, 162 deletions):
- QIVORA_PROGRESS_TRACKER.md, lib/core/database/database_service.dart, lib/core/widgets/qivora_message_bubble.dart,
  lib/features/chat/chats_screen.dart, lib/features/chat/conversation_screen.dart,
  lib/features/settings/settings_screen.dart, lib/features/status/status_screen.dart, lib/main.dart,
  test/chats_test.dart, test/contacts_test.dart, test/conversation_test.dart, test/database_test.dart

`git diff --name-only`: same 12 files above.

New (untracked) files delivered this phase:
- lib/core/auth/status_service.dart, lib/features/chat/archived_chats_screen.dart,
  lib/features/chat/starred_messages_screen.dart, lib/features/communities/, lib/features/groups/,
  test/communities_test.dart, test/community_roles_test.dart, test/groups_test.dart,
  test/status_access_test.dart

## Remaining limitations
- No cross-device sync (no backend); community profile image stored locally via image_picker.
- Test-hang root cause documented and fixed for this codebase's tests; if the environment's sqflite/ffi binding changes, re-verify with `databaseFactoryFfiNoIsolate` + `tester.runAsync`.
- Existing SQLite data preserved; all migrations additive (ALTER TABLE ADD COLUMN / CREATE IF NOT EXISTS).
