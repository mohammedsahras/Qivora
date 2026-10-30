import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();
  Database? _db;

  /// Overrides the database path used by [_open]. Intended for tests only so
  /// test runs never touch the user's real database.
  static String? _testDatabasePath;

  /// Call [setTestDatabasePath] before accessing [database] in tests.
  static void setTestDatabasePath(String? path) {
    _testDatabasePath = path;
    instance._db = null;
  }

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  /// Convenience alias for [setTestDatabasePath] used by tests.
  static void forcePathForTests(String path) => setTestDatabasePath(path);

  Future<Database> _open() async {
    // When a test database path is set, skip getDatabasesPath() which uses a
    // platform channel that is unavailable on the Windows test host.
    final path =
        _testDatabasePath ?? join(await getDatabasesPath(), 'qivora.db');
    return openDatabase(
      path,
      version: 13,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS contacts (
              id TEXT PRIMARY KEY,
              owner_user_id TEXT NOT NULL,
              contact_user_id TEXT NOT NULL,
              display_name TEXT,
              created_at TEXT NOT NULL,
              UNIQUE(owner_user_id, contact_user_id)
            );
          ''');
        }
        if (oldV < 3) {
          // add attachment metadata columns
          Future<void> addCol(String table, String col, String type) async {
            try {
              await db.execute('ALTER TABLE $table ADD COLUMN $col $type');
            } catch (_) {}
          }

          await addCol('messages', 'attachment_type', 'TEXT');
          await addCol('messages', 'attachment_filename', 'TEXT');
          await addCol('messages', 'attachment_size', 'INTEGER');
          await addCol('messages', 'media_duration', 'INTEGER');
          await addCol('messages', 'forwarded_from_message_id', 'TEXT');
          await addCol('messages', 'forwarded_from_conversation_id', 'TEXT');
          // unique reaction per user per message
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_reactions_unique ON message_reactions(message_id, user_id);');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_reactions_msg ON message_reactions(message_id);');
          // add call_history table if missing (for upgrades from v2)
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS call_history (
                id TEXT PRIMARY KEY,
                conversation_id TEXT,
                caller_id TEXT,
                recipient_id TEXT,
                call_type TEXT NOT NULL,
                call_status TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT,
                duration INTEGER,
                created_at TEXT NOT NULL,
                FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE SET NULL,
                FOREIGN KEY (caller_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE SET NULL
              );
            ''');
          } catch (_) {}
        }
        if (oldV < 4) {
          // Archive flag on conversations and per-user unread/pin/mute state.
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN archived INTEGER DEFAULT 0');
          await db.execute(
              'ALTER TABLE conversation_participants ADD COLUMN unread_count INTEGER DEFAULT 0');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_conversations_archived ON conversations(archived, updated_at DESC);');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_participants_unread ON conversation_participants(unread_count);');
        }
        if (oldV < 5) {
          // About text on the users profile table.
          await db.execute('ALTER TABLE users ADD COLUMN about TEXT');
        }
        if (oldV < 6) {
          // Starred messages flag.
          await db.execute(
              'ALTER TABLE messages ADD COLUMN starred INTEGER DEFAULT 0');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_messages_starred ON messages(starred, created_at DESC);');
        }
        if (oldV < 7) {
          // Read receipts: track which users have read which messages.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS message_read_receipts (
              id TEXT PRIMARY KEY,
              message_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              read_at TEXT NOT NULL,
              FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
          ''');
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_read_receipts_unique ON message_read_receipts(message_id, user_id);');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_read_receipts_msg ON message_read_receipts(message_id);');
        }
        if (oldV < 8) {
          // Voice message audio path.
          await db.execute('ALTER TABLE messages ADD COLUMN audio_path TEXT');
        }
        if (oldV < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS drafts (
              conversation_id TEXT PRIMARY KEY,
              draft_text TEXT NOT NULL DEFAULT '',
              updated_at TEXT NOT NULL,
              FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            );
          ''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_drafts_updated ON drafts(updated_at);');
         if (oldV < 11) {
           try {
             await db.execute("ALTER TABLE users ADD COLUMN password_hash TEXT");
           } catch (_) {}
         }
         if (oldV < 11) {
           await db.execute("CREATE TABLE IF NOT EXISTS channels (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, category TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);");
           await db.execute("CREATE TABLE IF NOT EXISTS channel_updates (id TEXT PRIMARY KEY, channel_id TEXT NOT NULL, content TEXT, image_path TEXT, created_at TEXT NOT NULL, FOREIGN KEY(channel_id) REFERENCES channels(id) ON DELETE CASCADE);");
           await db.execute("CREATE TABLE IF NOT EXISTS statuses (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, content TEXT, image_path TEXT, background_color TEXT, created_at TEXT NOT NULL, expires_at TEXT NOT NULL, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE);");
           await db.execute("CREATE TABLE IF NOT EXISTS blocked_contacts (id TEXT PRIMARY KEY, blocker_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(blocker_id, blocked_id));");
           await db.execute("CREATE TABLE IF NOT EXISTS privacy_settings (key TEXT PRIMARY KEY, value TEXT);");
         }
         if (oldV < 12) {
           await db.execute("CREATE TABLE IF NOT EXISTS channel_followers (channel_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(channel_id, user_id), FOREIGN KEY(channel_id) REFERENCES channels(id) ON DELETE CASCADE, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE);");
           await db.execute("CREATE TABLE IF NOT EXISTS channel_admins (channel_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(channel_id, user_id), FOREIGN KEY(channel_id) REFERENCES channels(id) ON DELETE CASCADE, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE);");
         }
         if (oldV < 13) {
           await db.execute("CREATE TABLE IF NOT EXISTS status_views (status_id TEXT NOT NULL, viewer_id TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(status_id, viewer_id), FOREIGN KEY(status_id) REFERENCES statuses(id) ON DELETE CASCADE, FOREIGN KEY(viewer_id) REFERENCES users(id) ON DELETE CASCADE);");
         }
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        username TEXT UNIQUE,
        phone_number TEXT,
        email TEXT,
        avatar_path TEXT,
        status_text TEXT,
        is_online INTEGER DEFAULT 0,
        about TEXT,
        password_hash TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        avatar_path TEXT,
        last_message_id TEXT,
        archived INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE conversation_participants (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        role TEXT DEFAULT 'member',
        joined_at TEXT NOT NULL,
        is_muted INTEGER DEFAULT 0,
        is_pinned INTEGER DEFAULT 0,
        unread_count INTEGER DEFAULT 0,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        message_type TEXT NOT NULL,
        content TEXT,
        reply_to_message_id TEXT,
        attachment_path TEXT,
        attachment_type TEXT,
        attachment_filename TEXT,
        attachment_size INTEGER,
        media_duration INTEGER,
        audio_path TEXT,
        forwarded_from_message_id TEXT,
        forwarded_from_conversation_id TEXT,
        delivery_status TEXT DEFAULT 'sent',
        starred INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE message_reactions (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        emoji TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE message_read_receipts (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        read_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    ''');
    await db.execute(
        'CREATE INDEX idx_messages_conv_created ON messages(conversation_id, created_at);');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_reactions_unique ON message_reactions(message_id, user_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reactions_msg ON message_reactions(message_id);');
    await db.execute(
        'CREATE INDEX idx_participants_conv ON conversation_participants(conversation_id);');
    await db.execute(
        'CREATE INDEX idx_participants_user ON conversation_participants(user_id);');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contacts (
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        contact_user_id TEXT NOT NULL,
        display_name TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(owner_user_id, contact_user_id)
      );
    ''');
    // New: call history table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS call_history (
        id TEXT PRIMARY KEY,
        conversation_id TEXT,
        caller_id TEXT,
        recipient_id TEXT,
        call_type TEXT NOT NULL,
        call_status TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        duration INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE SET NULL,
        FOREIGN KEY (caller_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE SET NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS drafts (
        conversation_id TEXT PRIMARY KEY,
        draft_text TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drafts_updated ON drafts(updated_at);');
    await db.execute("CREATE TABLE IF NOT EXISTS channels (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, category TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);");
    await db.execute("CREATE TABLE IF NOT EXISTS channel_updates (id TEXT PRIMARY KEY, channel_id TEXT NOT NULL, content TEXT, image_path TEXT, created_at TEXT NOT NULL, FOREIGN KEY(channel_id) REFERENCES channels(id) ON DELETE CASCADE);");
    await db.execute("CREATE TABLE IF NOT EXISTS statuses (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, content TEXT, image_path TEXT, background_color TEXT, created_at TEXT NOT NULL, expires_at TEXT NOT NULL, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE);");
    await db.execute("CREATE TABLE IF NOT EXISTS blocked_contacts (id TEXT PRIMARY KEY, blocker_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(blocker_id, blocked_id));");
    await db.execute("CREATE TABLE IF NOT EXISTS privacy_settings (key TEXT PRIMARY KEY, value TEXT);");
    await db.execute("CREATE TABLE IF NOT EXISTS channel_followers (channel_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(channel_id, user_id), FOREIGN KEY(channel_id) REFERENCES channels(id) ON DELETE CASCADE, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE);");
    await db.execute("CREATE TABLE IF NOT EXISTS channel_admins (channel_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(channel_id, user_id), FOREIGN KEY(channel_id) REFERENCES channels(id) ON DELETE CASCADE, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE);");
    await db.execute("CREATE TABLE IF NOT EXISTS status_views (status_id TEXT NOT NULL, viewer_id TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(status_id, viewer_id), FOREIGN KEY(status_id) REFERENCES statuses(id) ON DELETE CASCADE, FOREIGN KEY(viewer_id) REFERENCES users(id) ON DELETE CASCADE);");
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
