import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api_service.dart';
import 'odometer_outbox_service.dart';

/// Drains the local odometer outbox to the backend. The service:
///
/// - listens for connectivity changes (`connectivity_plus`),
/// - runs a periodic foreground tick (default 60 seconds),
/// - resyncs whenever the app comes back to the foreground.
///
/// Construct once at app start (after auth is ready) and call [start].
/// Call [stop] on logout.
class OdometerSyncService with WidgetsBindingObserver {
  OdometerSyncService({Duration tickInterval = const Duration(seconds: 60)})
    : _tickInterval = tickInterval;

  final Duration _tickInterval;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _timer;
  bool _draining = false;
  bool _started = false;

  /// Reactive count of pending entries, useful for badges.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// `true` while a flush cycle is uploading entries.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  StreamSubscription<void>? _outboxSub;

  void start() {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(this);

    _connSub = _connectivity.onConnectivityChanged.listen((results) {
      if (results.any(_isOnline)) {
        // Fire-and-forget; we don't want to block the connectivity stream.
        unawaited(flush());
      }
    });

    _timer = Timer.periodic(_tickInterval, (_) => unawaited(flush()));

    _outboxSub = OdometerOutboxService.changes.listen((_) {
      unawaited(_refreshPending());
    });

    unawaited(_refreshPending());
    // First drain attempt right away (if the app launches while online).
    unawaited(flush());
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    await _connSub?.cancel();
    _connSub = null;
    _timer?.cancel();
    _timer = null;
    await _outboxSub?.cancel();
    _outboxSub = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(flush());
    }
  }

  bool _isOnline(ConnectivityResult r) =>
      r != ConnectivityResult.none && r != ConnectivityResult.bluetooth;

  Future<bool> _hasNetwork() async {
    final results = await _connectivity.checkConnectivity();
    return results.any(_isOnline);
  }

  Future<void> _refreshPending() async {
    try {
      final count = await OdometerOutboxService.pendingCount();
      pendingCount.value = count;
    } catch (_) {
      // Ignore — UI will just show stale count.
    }
  }

  /// Attempt to upload every due entry. Safe to call multiple times in
  /// parallel — only one drain runs at a time. When [includeFailed] is true,
  /// rows that exceeded the retry budget are picked up as well (used by the
  /// "Retry now" UI action).
  Future<void> flush({bool includeFailed = false}) async {
    if (_draining) return;
    if (!await _hasNetwork()) {
      await _refreshPending();
      return;
    }

    _draining = true;
    isSyncing.value = true;
    try {
      final entries = await OdometerOutboxService.dueEntries(
        includeFailed: includeFailed,
      );
      for (final entry in entries) {
        await _upload(entry);
      }
    } finally {
      _draining = false;
      isSyncing.value = false;
      await _refreshPending();
    }
  }

  Future<void> _upload(OutboxEntry entry) async {
    await OdometerOutboxService.markSyncing(entry.id);
    try {
      // If the driver attached an odometer photo, send the row as
      // multipart/form-data so the file rides along. Otherwise stay on the
      // plain JSON endpoint.
      final payload = Map<String, dynamic>.from(entry.payload);
      final photoPath = payload.remove('photo_path');
      Map<String, dynamic> response;
      if (photoPath is String && photoPath.isNotEmpty) {
        response = await ApiService.createOdometerLogMultipart(
          entry.tripId,
          payload: payload,
          photoField: 'photo',
          photoPath: photoPath,
        );
      } else {
        response = await ApiService.createOdometerLog(entry.tripId, payload);
      }

      // Server may echo the new resource id under common keys.
      String? remoteId;
      final candidate =
          response['id'] ??
          (response['data'] is Map ? response['data']['id'] : null) ??
          (response['log'] is Map ? response['log']['id'] : null);
      if (candidate != null) remoteId = candidate.toString();

      await OdometerOutboxService.markSynced(entry.id, remoteId: remoteId);
      // Clean up the on-device photo once it has been delivered to the
      // server; we do not need a local copy after that.
      if (photoPath is String && photoPath.isNotEmpty) {
        await OdometerOutboxService.discardPhoto(photoPath);
      }
    } on ApiException catch (e) {
      // Surface the failure in the run log so it's diagnosable when an
      // entry refuses to drain.
      debugPrint(
        '[OdometerSync] upload failed for trip=${entry.tripId} '
        'client_id=${entry.clientId} status=${e.statusCode}: ${e.message}',
      );
      // Validation, not-found, conflict, auth, and permission errors won't
      // get better by retrying – mark as failed immediately so the driver
      // (or admin) can act on the surfaced error.
      if (e.statusCode == 400 ||
          e.statusCode == 401 ||
          e.statusCode == 403 ||
          e.statusCode == 404 ||
          e.statusCode == 409 ||
          e.statusCode == 422) {
        await OdometerOutboxService.markFailed(
          entry.id,
          error: '[${e.statusCode}] ${e.message}',
          attempts: OdometerOutboxService.maxAttempts,
        );
      } else {
        await OdometerOutboxService.markFailed(
          entry.id,
          error: '[${e.statusCode}] ${e.message}',
          attempts: entry.attempts + 1,
        );
      }
    } catch (e) {
      // Network/timeout — back off and retry on the next tick.
      debugPrint(
        '[OdometerSync] upload network error for trip=${entry.tripId} '
        'client_id=${entry.clientId}: $e',
      );
      await OdometerOutboxService.markFailed(
        entry.id,
        error: e.toString(),
        attempts: entry.attempts + 1,
      );
    }
  }
}
