import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Status of an outbox row's sync attempt.
enum OutboxStatus {
  pending, // not yet sent or eligible for retry
  syncing, // currently being uploaded (process-local)
  synced, // server accepted, kept briefly for UI ack then purged
  failed, // exceeded retry budget; needs manual retry
}

extension OutboxStatusX on OutboxStatus {
  String get value {
    switch (this) {
      case OutboxStatus.pending:
        return 'pending';
      case OutboxStatus.syncing:
        return 'syncing';
      case OutboxStatus.synced:
        return 'synced';
      case OutboxStatus.failed:
        return 'failed';
    }
  }

  static OutboxStatus fromString(String? raw) {
    switch (raw) {
      case 'syncing':
        return OutboxStatus.syncing;
      case 'synced':
        return OutboxStatus.synced;
      case 'failed':
        return OutboxStatus.failed;
      case 'pending':
      default:
        return OutboxStatus.pending;
    }
  }
}

/// A single odometer reading stored in the local outbox awaiting upload.
class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.clientId,
    required this.tripId,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.remoteId,
    this.lastError,
  });

  final int id;
  final String clientId;
  final String tripId;
  final Map<String, dynamic> payload;
  final OutboxStatus status;
  final int attempts;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? remoteId;
  final String? lastError;

  bool get isPending =>
      status == OutboxStatus.pending || status == OutboxStatus.syncing;

  factory OutboxEntry.fromRow(Map<String, dynamic> row) {
    final payloadRaw = row['payload'] as String? ?? '{}';
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(payloadRaw);
      payload = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      payload = <String, dynamic>{};
    }
    return OutboxEntry(
      id: row['id'] as int,
      clientId: row['client_id'] as String,
      tripId: row['trip_id'].toString(),
      payload: payload,
      status: OutboxStatusX.fromString(row['status'] as String?),
      attempts: (row['attempts'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as int?) ?? 0,
      ),
      remoteId: row['remote_id'] as String?,
      lastError: row['last_error'] as String?,
    );
  }
}

/// Local-first outbox for odometer readings. Reads/writes are guarded by
/// sqflite and survive app restarts. Sync is handled separately by
/// `OdometerSyncService`.
class OdometerOutboxService {
  OdometerOutboxService._();

  static const String _dbName = 'sher_offline.db';
  static const int _dbVersion = 1;
  static const String _table = 'odometer_outbox';
  static const int maxAttempts = 6;

  static Database? _db;
  static const _uuid = Uuid();

  /// Broadcasts whenever the outbox changes. UI can listen to refresh badges.
  static final StreamController<void> _changes =
      StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id TEXT NOT NULL UNIQUE,
            trip_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            attempts INTEGER NOT NULL DEFAULT 0,
            remote_id TEXT,
            last_error TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_${_table}_status ON $_table(status)',
        );
        await db.execute('CREATE INDEX idx_${_table}_trip ON $_table(trip_id)');
      },
    );
    return _db!;
  }

  /// Enqueue a new odometer reading for trip [tripId]. The reading is queued
  /// immediately and will be uploaded by [OdometerSyncService] as soon as
  /// connectivity is available. Returns the persisted [OutboxEntry].
  static Future<OutboxEntry> enqueue({
    required dynamic tripId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _open();
    final clientId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Tag the payload with the device-generated client_id so the server can
    // dedupe on retries.
    final taggedPayload = <String, dynamic>{
      ...payload,
      'client_id': clientId,
      'recorded_at':
          payload['recorded_at'] ?? DateTime.now().toUtc().toIso8601String(),
    };

    final id = await db.insert(_table, {
      'client_id': clientId,
      'trip_id': tripId.toString(),
      'payload': jsonEncode(taggedPayload),
      'status': OutboxStatus.pending.value,
      'attempts': 0,
      'created_at': now,
      'updated_at': now,
    });

    _notify();

    return OutboxEntry(
      id: id,
      clientId: clientId,
      tripId: tripId.toString(),
      payload: taggedPayload,
      status: OutboxStatus.pending,
      attempts: 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  /// All pending or failed entries for [tripId]. Used to render unsynced
  /// readings alongside server-synced rows.
  static Future<List<OutboxEntry>> entriesForTrip(dynamic tripId) async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'trip_id = ? AND status != ?',
      whereArgs: [tripId.toString(), OutboxStatus.synced.value],
      orderBy: 'created_at ASC',
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }

  /// All pending or failed entries across every trip. Used by the trip
  /// list to surface per-trip unsynced reading counts in one query.
  static Future<List<OutboxEntry>> allPendingEntries() async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'status != ?',
      whereArgs: [OutboxStatus.synced.value],
      orderBy: 'created_at ASC',
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }

  /// Count of rows still waiting (pending/syncing/failed). Used for badges.
  static Future<int> pendingCount() async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE status != ?',
      [OutboxStatus.synced.value],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Rows the sync worker should attempt. Failed rows are skipped unless
  /// [includeFailed] is true (manual retry).
  static Future<List<OutboxEntry>> dueEntries({
    bool includeFailed = false,
    int limit = 50,
  }) async {
    final db = await _open();
    final where = includeFailed ? 'status IN (?, ?, ?)' : 'status IN (?, ?)';
    final args = includeFailed
        ? [
            OutboxStatus.pending.value,
            OutboxStatus.syncing.value,
            OutboxStatus.failed.value,
          ]
        : [OutboxStatus.pending.value, OutboxStatus.syncing.value];
    final rows = await db.query(
      _table,
      where: where,
      whereArgs: args,
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }

  static Future<void> markSyncing(int id) async {
    final db = await _open();
    await db.update(
      _table,
      {
        'status': OutboxStatus.syncing.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  static Future<void> markSynced(int id, {String? remoteId}) async {
    final db = await _open();
    await db.update(
      _table,
      {
        'status': OutboxStatus.synced.value,
        'remote_id': remoteId,
        'last_error': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    // Synced rows are not interesting for the queue; purge immediately so the
    // outbox table stays small and the badge counts stay correct.
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  static Future<void> markFailed(
    int id, {
    required String error,
    required int attempts,
  }) async {
    final db = await _open();
    final exceeded = attempts >= maxAttempts;
    await db.update(
      _table,
      {
        'status': exceeded
            ? OutboxStatus.failed.value
            : OutboxStatus.pending.value,
        'attempts': attempts,
        'last_error': error,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  /// Manually reset a failed entry so the sync worker will pick it up again.
  static Future<void> resetFailed(int id) async {
    final db = await _open();
    await db.update(
      _table,
      {
        'status': OutboxStatus.pending.value,
        'attempts': 0,
        'last_error': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  static Future<void> delete(int id) async {
    final db = await _open();
    // Best-effort: remove any attached photo so we don't leak files.
    final rows = await db.query(
      _table,
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final raw = rows.first['payload'] as String? ?? '{}';
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['photo_path'] is String) {
          await discardPhoto(decoded['photo_path'] as String);
        }
      } catch (_) {}
    }
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  /// Used by tests; wipes the entire outbox.
  static Future<void> clearAll() async {
    final db = await _open();
    await db.delete(_table);
    _notify();
  }

  // ─── Photo attachments ───────────────────────────────────────────────────
  //
  // Photos of the odometer reading are stored in a dedicated subdirectory
  // under the app's documents folder (which survives cache eviction and app
  // upgrades). Each outbox row references the absolute path via its
  // `photo_path` payload key. After successful upload the file is removed.

  static const String _photoDir = 'odometer_photos';

  static Future<Directory> _ensurePhotoDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _photoDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies [sourcePath] (typically returned by `ImagePicker`) into the
  /// persistent photo directory and returns the new absolute path. Safe to
  /// call from the entry editor; the file is preserved even if the original
  /// cache file is evicted before the outbox row is uploaded.
  static Future<String> savePhoto(String sourcePath) async {
    final dir = await _ensurePhotoDir();
    final ext = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final target = p.join(dir.path, '${_uuid.v4()}$ext');
    await File(sourcePath).copy(target);
    return target;
  }

  /// Removes a previously-saved photo (e.g. when the driver discards an
  /// in-progress entry).
  static Future<void> discardPhoto(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup only; do not surface errors.
    }
  }

  static void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }
}
