import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/odometer_logs_cache_service.dart';
import '../services/odometer_outbox_service.dart';
import '../services/odometer_sync_service.dart';
import '../services/trips_cache_service.dart';
import 'login_screen.dart';

class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({
    super.key,
    required this.driver,
    this.useCurrentAssignments = false,
    this.embeddedInHome = false,
    this.viewAllTrips = false,
  });

  final Map<String, dynamic> driver;
  final bool useCurrentAssignments;
  final bool embeddedInHome;
  final bool viewAllTrips;

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _trips = <dynamic>[];
  bool _loading = true;

  /// True when the trips currently shown were loaded from the local cache
  /// because the network call failed (e.g. device offline). Used to render
  /// a banner and to keep [_loading] off so the user can still interact.
  bool _isOfflineSnapshot = false;
  DateTime? _offlineSnapshotAt;

  /// Outbox readings still waiting to upload, across every trip. Surfaced
  /// in each trip card so the count includes unsynced rows the driver
  /// just recorded.
  List<OutboxEntry> _outboxEntries = const <OutboxEntry>[];
  StreamSubscription<void>? _outboxSub;

  String get _driverName =>
      (widget.driver['name'] ?? widget.driver['full_name'] ?? 'Driver')
          .toString();

  String? get _driverEmail {
    final raw = widget.driver['email'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  int? get _driverId {
    final raw = widget.driver['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
    _refreshOutbox();
    // Live-refresh per-trip pending counts whenever the outbox changes
    // (new reading queued, sync succeeded, attempt failed, etc.).
    _outboxSub = OdometerOutboxService.changes.listen((_) {
      if (!mounted) return;
      _refreshOutbox();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _outboxSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshOutbox() async {
    final all = await OdometerOutboxService.allPendingEntries();
    if (!mounted) return;
    // Detect "something just synced" – the outbox shrank since last refresh.
    // When that happens we also reload the trip list so the server-side
    // odometer count badge ticks up immediately instead of waiting for the
    // next manual refresh.
    final shrank = all.length < _outboxEntries.length;
    setState(() => _outboxEntries = all);
    if (shrank) {
      unawaited(_load());
    }
  }

  List<dynamic> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _trips;
    return _trips.where((t) {
      final lead = t['lead'];
      final contract = t['contract'];
      final groupName =
          (t['group_name'] ??
                  t['groupName'] ??
                  (lead is Map ? lead['groupName'] : null) ??
                  (contract is Map ? contract['groupName'] : null) ??
                  '')
              .toString()
              .toLowerCase();
      final ref =
          (t['booking_ref'] ??
                  t['bookingRef'] ??
                  t['ref'] ??
                  (lead is Map ? lead['bookingRef'] : null) ??
                  (contract is Map ? contract['groupName'] : null) ??
                  '')
              .toString()
              .toLowerCase();
      final client =
          (t['client_company'] ??
                  t['clientCompany'] ??
                  t['client'] ??
                  (lead is Map ? lead['clientCompany'] : null) ??
                  (contract is Map ? contract['clientName'] : null) ??
                  '')
              .toString()
              .toLowerCase();
      final route =
          (t['route'] ??
                  t['destination'] ??
                  t['route_parks'] ??
                  t['routeParks'] ??
                  (lead is Map ? lead['routeParks'] : null) ??
                  t['itinerary'] ??
                  '')
              .toString()
              .toLowerCase();
      final status = (t['status'] ?? '').toString().toLowerCase();
      return ref.contains(q) ||
          client.contains(q) ||
          groupName.contains(q) ||
          route.contains(q) ||
          status.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    final cacheUseCurrentAssignments = widget.viewAllTrips
        ? false
        : widget.useCurrentAssignments;
    final cacheDriverId = widget.viewAllTrips ? null : _driverId;

    // Only show the full-screen spinner on a cold start when we have nothing
    // to display. Refreshes (pull-to-refresh, post-sync auto-refresh, etc.)
    // keep the existing list on screen so it never appears to "disappear"
    // while a new fetch is in flight – RefreshIndicator already shows its
    // own pull spinner.
    if (_trips.isEmpty) {
      setState(() => _loading = true);
    }

    // Seed from cache first so users see *something* immediately, even on
    // cold-start with no connectivity. The live fetch below will replace it
    // when the network comes back.
    final cached = await TripsCacheService.read(
      useCurrentAssignments: cacheUseCurrentAssignments,
      driverId: cacheDriverId,
    );
    if (!mounted) return;
    if (cached != null && cached.isNotEmpty && _trips.isEmpty) {
      final stamp = await TripsCacheService.savedAt(
        useCurrentAssignments: cacheUseCurrentAssignments,
        driverId: cacheDriverId,
      );
      if (!mounted) return;
      setState(() {
        _trips = cached;
        _isOfflineSnapshot = true;
        _offlineSnapshotAt = stamp;
        _loading = false;
      });
    }

    try {
      final id = _driverId;
      // Driver scoping contract: when the screen is launched in
      // `useCurrentAssignments` mode (the default for users with the Driver
      // role) we call `fetchMyAssignedTrips`, which is constrained server-side
      // to the authenticated driver's own vehicle assignments. The fallback
      // `fetchDriverTrips(id)` is only reachable when an admin viewer is
      // browsing a specific driver. Drivers never see other vehicles.
      final data = widget.viewAllTrips
          ? await ApiService.fetchList('/safari-allocations')
          : widget.useCurrentAssignments
          ? await ApiService.fetchMyAssignedTrips()
          : id != null
          ? await ApiService.fetchDriverTrips(id)
          : await ApiService.fetchMyAssignedTrips();
      if (!mounted) return;
      // Guard against a transient empty response wiping the previously
      // cached list. Only replace if the server actually returned data, or
      // if we genuinely have no cached trips to fall back on.
      if (data.isNotEmpty || _trips.isEmpty) {
        setState(() {
          _trips = data;
          _loading = false;
          _isOfflineSnapshot = false;
          _offlineSnapshotAt = null;
        });
      } else {
        // Server returned empty but we have cached trips – keep them and
        // just clear the loading state.
        setState(() => _loading = false);
      }
      // Persist the fresh response so a later offline launch can replay it.
      // Only overwrite when the response was non-empty so we don't blank out
      // a healthy cache because of a bad response window.
      if (data.isNotEmpty) {
        unawaited(
          TripsCacheService.save(
            data,
            useCurrentAssignments: cacheUseCurrentAssignments,
            driverId: cacheDriverId,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Network/API failure: fall back to whatever we already had cached.
      // This is the common offline path — we want the driver to still see
      // their assigned trips and be able to record odometer readings into
      // the outbox.
      if (_trips.isEmpty) {
        final fallback = await TripsCacheService.read(
          useCurrentAssignments: cacheUseCurrentAssignments,
          driverId: cacheDriverId,
        );
        if (!mounted) return;
        if (fallback != null && fallback.isNotEmpty) {
          final stamp = await TripsCacheService.savedAt(
            useCurrentAssignments: cacheUseCurrentAssignments,
            driverId: cacheDriverId,
          );
          if (!mounted) return;
          setState(() {
            _trips = fallback;
            _isOfflineSnapshot = true;
            _offlineSnapshotAt = stamp;
            _loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Offline – showing your last saved trips. Readings will sync '
                'when you reconnect.',
              ),
            ),
          );
          return;
        }
      } else {
        // We already showed cached data above; just stop the spinner.
        setState(() {
          _loading = false;
          _isOfflineSnapshot = true;
        });
        return;
      }
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load trips: $e')));
    }
  }

  void _showOdometerSheet(Map<String, dynamic> trip) {
    final tripId = trip['assignmentType'] == 'long_term_lease'
        ? 'lease:${trip['id']}'
        : trip['id'];
    final auth = context.read<AuthProvider>();
    final canRecord =
        !(auth.hasRole('operations') ||
            auth.hasRole('operator') ||
            auth.hasRole('admin'));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Keep the sheet clear of the status bar / notch on tablets. The
      // bottom area is handled per-button so the chrome can still extend
      // visually behind the gesture bar.
      useSafeArea: true,
      builder: (_) =>
          _OdometerSheet(trip: trip, tripId: tripId, canRecord: canRecord),
    ).whenComplete(() {
      // Refresh both the server-side trip list (for synced-row counts) and
      // the local outbox so the per-trip "X entries recorded" badge stays
      // accurate after the driver records or syncs readings.
      if (!mounted) return;
      _refreshOutbox();
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Scaffold(
      backgroundColor: theme.colorScheme.background,
      drawer: widget.embeddedInHome ? null : _buildDriverDrawer(theme),
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: widget.embeddedInHome
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        automaticallyImplyLeading: !widget.embeddedInHome,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _driverName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            Text(
              widget.embeddedInHome
                  ? 'Day-to-Day Safari Movement'
                  : 'My Day-to-Day Safari Movement',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: const [_SyncStatusChip(), SizedBox(width: 8)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: const InputDecoration(
                hintText: 'Search trips...',
                prefixIcon: Icon(Icons.search, color: Color(0xFF64748B)),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(kGoldColor)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(kGoldColor),
              child: Column(
                children: [
                  if (_isOfflineSnapshot) _offlineBanner(),
                  Expanded(
                    child: _filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 120),
                              Icon(
                                Icons.route_outlined,
                                size: 52,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withOpacity(0.35),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  'No trips found',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _tripCard(_filtered[i]),
                          ),
                  ),
                ],
              ),
            ),
    );

    if (widget.embeddedInHome) {
      return content;
    }

    // Drivers land directly on this screen after login, so the system back
    // button would otherwise close the app. Intercept it and confirm.
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _confirmExit();
        if (shouldExit && mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            await SystemNavigator.pop();
          }
        }
      },
      child: content,
    );
  }

  /// Confirms that the driver really wants to exit the app via the system
  /// back button. Returning `true` lets the OS proceed; `false` keeps them
  /// on the trip list.
  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit app?'),
        content: const Text(
          'Use the menu \u2192 Logout to sign out, or exit the app now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD62E2E),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Side drawer with driver identity and a Logout action. The hamburger
  /// in the AppBar opens this; the system back button is intercepted by
  /// [PopScope] so drivers cannot accidentally exit the app.
  Widget _buildDriverDrawer(ThemeData theme) {
    final initials = _driverName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(kGoldColor).withOpacity(0.15),
                    child: Text(
                      initials.isEmpty ? 'D' : initials,
                      style: const TextStyle(
                        color: Color(kGoldColor),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _driverName,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_driverEmail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _driverEmail!,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const Text(
                            'Driver',
                            style: TextStyle(
                              color: Color(0xFF1D4ED8),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Refresh trips'),
              onTap: () {
                Navigator.pop(context);
                _load();
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFD62E2E),
              ),
              title: const Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFFD62E2E),
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: _handleLogout,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'SherERP \u2022 Driver',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text(
          'You will need to sign in again to record more odometer readings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD62E2E),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    // Close the drawer before kicking off the logout flow.
    Navigator.of(context).pop();
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  /// Shows a small banner when the trip list was loaded from the local
  /// snapshot rather than a live API response, so the driver knows readings
  /// will queue rather than post immediately.
  Widget _offlineBanner() {
    final stamp = _offlineSnapshotAt;
    String subtitle = 'Showing your last saved trips.';
    if (stamp != null) {
      final local = stamp.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      subtitle =
          'Last synced ${two(local.day)}/${two(local.month)} '
          '${two(local.hour)}:${two(local.minute)}.';
    }
    return Material(
      color: const Color(0xFFFFF7ED),
      child: InkWell(
        onTap: _load,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'You\u2019re offline',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$subtitle Pull to retry.',
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.refresh, size: 18, color: Color(0xFFB45309)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tripCard(Map<String, dynamic> trip) {
    final theme = Theme.of(context);
    final lead = trip['lead'];
    final contract = trip['contract'];
    final isLongTermLease = trip['assignmentType'] == 'long_term_lease';
    final groupName =
        trip['group_name'] ??
        trip['groupName'] ??
        (lead is Map ? lead['groupName'] : null) ??
        (contract is Map ? contract['groupName'] : null) ??
        '';
    final ref =
        trip['booking_ref'] ??
        trip['bookingRef'] ??
        trip['ref'] ??
        (lead is Map ? lead['bookingRef'] : null) ??
        trip['groupName'] ??
        (contract is Map ? contract['groupName'] : null) ??
        (isLongTermLease ? 'Lease #${trip['id']}' : null) ??
        '-';
    final client =
        trip['client_company'] ??
        trip['clientCompany'] ??
        trip['client'] ??
        (lead is Map ? lead['clientCompany'] : null) ??
        (contract is Map ? contract['clientName'] : null) ??
        '-';
    final route = _formatItinerary(
      trip['route'] ??
          trip['route_parks'] ??
          trip['routeParks'] ??
          trip['destination'] ??
          (lead is Map ? lead['routeParks'] : null) ??
          trip['itinerary'] ??
          'Route not specified',
    );
    final status = trip['status'] ?? 'Pending';
    final startDate = _formatTripDate(
      trip['start_date'] ??
          trip['startDate'] ??
          (lead is Map ? lead['startDate'] : null) ??
          '',
    );
    final endDate = _formatTripDate(
      trip['end_date'] ??
          trip['endDate'] ??
          (lead is Map ? lead['endDate'] : null) ??
          '',
    );
    final vehicleMap = trip['vehicle'];
    final itinerary = _formatItinerary(
      trip['itineraryItems'] ??
          trip['itinerary_items'] ??
          (lead is Map ? lead['daySections'] ?? lead['itinerary'] : null),
    );
    final vehicle = vehicleMap is Map
        ? '${vehicleMap['make'] ?? ''} ${vehicleMap['model'] ?? ''} ${(vehicleMap['plateNo'] ?? vehicleMap['vehicleNo'] ?? '').toString().trim()}'
              .trim()
        : (trip['vehicle_plate'] ?? trip['vehiclePlate'] ?? '');
    // Server provides the count via withCount('odometerLogs'). Fall back to
    // an embedded list (older payloads / cache) if present.
    int parseInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    final serverCount =
        parseInt(trip['odometer_log_count']) +
        // Fall back so we don't double-count when only one shape is present.
        0;
    final embeddedCount = (trip['odometer_logs'] as List?)?.length ?? 0;
    int odometerCount = serverCount > 0 ? serverCount : embeddedCount;
    if (odometerCount == 0) {
      odometerCount = parseInt(trip['odometerLogCount']);
    }
    // Add any locally-queued readings for this trip so the list reflects
    // them immediately, even before the outbox uploads.
    final tripIdStr = isLongTermLease
        ? 'lease:${trip['id']}'
        : (trip['id'] ?? trip['safari_allocation_id'])?.toString();
    if (tripIdStr != null && tripIdStr.isNotEmpty) {
      for (final p in _outboxEntries) {
        if (p.tripId == tripIdStr) odometerCount += 1;
      }
    }

    Color statusColor;
    switch (status.toString().toLowerCase()) {
      case 'completed':
        statusColor = const Color(0xFF16A34A);
        break;
      case 'cancelled':
        statusColor = Colors.red;
        break;
      case 'in progress':
      case 'in_progress':
        statusColor = Colors.blue;
        break;
      default:
        statusColor = const Color(kGoldColor);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showOdometerSheet(trip),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outline, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trip header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(kGoldColor), Color(0xFFE6B800)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.route_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ref.toString(),
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            client.toString(),
                            style: const TextStyle(
                              color: Color(kGoldColor),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status.toString(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Trip details
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  children: [
                    if (groupName.toString().trim().isNotEmpty)
                      _infoRow(
                        Icons.groups_outlined,
                        'Group: ${groupName.toString().trim()}',
                        theme,
                      ),
                    if (route.isNotEmpty)
                      _infoRow(
                        Icons.location_on_outlined,
                        route.toString(),
                        theme,
                      ),
                    if (startDate.isNotEmpty || endDate.isNotEmpty)
                      _infoRow(
                        Icons.calendar_today_outlined,
                        [
                          startDate,
                          endDate,
                        ].where((s) => s.toString().isNotEmpty).join(' → '),
                        theme,
                      ),
                    if (vehicle.toString().isNotEmpty)
                      _infoRow(
                        Icons.directions_car_outlined,
                        vehicle.toString(),
                        theme,
                      ),
                    if (itinerary.isNotEmpty)
                      _infoRow(
                        Icons.map_outlined,
                        'Itinerary: $itinerary',
                        theme,
                      ),
                  ],
                ),
              ),

              if (isLongTermLease)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      avatar: const Icon(Icons.car_rental_outlined, size: 16),
                      label: Text(
                        (contract is Map ? contract['leaseType'] : null)
                                ?.toString() ??
                            'Long-Term Lease',
                      ),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5DB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(kGoldColor).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.speed_outlined,
                        size: 16,
                        color: Color(kGoldColor),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        odometerCount == 0
                            ? 'No odometer entries yet'
                            : '$odometerCount odometer entr${odometerCount == 1 ? 'y' : 'ies'} recorded',
                        style: const TextStyle(
                          color: Color(kGoldColor),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Fuel-cycle summary (only when we have at least one Fuel event in
              // the trip's embedded log). Surfaces current-tank progress and the
              // last completed tank's average km/litre at a glance.
              _fuelCycleSummary(trip),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showOdometerSheet(trip),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(kGoldColor),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.speed_outlined, size: 18),
                    label: const Text(
                      'Open Fuel & Mileage Trip',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTripDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year}';
  }

  String _formatItinerary(dynamic value) {
    if (value is! List) return value?.toString().trim() ?? '';
    final rows = <String>[];
    for (final item in value) {
      if (item is! Map) continue;
      final title =
          item['date'] ??
          item['dayDate'] ??
          item['day_date'] ??
          item['dayTitle'];
      final date = _formatTripDate(title);
      final details =
          (item['details'] ??
                  item['description'] ??
                  item['dayDescription'] ??
                  item['route'] ??
                  item['title'] ??
                  '')
              .toString()
              .trim();
      if (date.isNotEmpty && details.isNotEmpty) {
        rows.add('$date — $details');
      } else if (date.isNotEmpty) {
        rows.add(date);
      } else if (details.isNotEmpty) {
        rows.add(details);
      }
    }
    return rows.isEmpty ? 'Itinerary not specified' : rows.join('  •  ');
  }

  Widget _infoRow(IconData icon, String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a compact tank-cycle summary for a trip card.
  ///
  /// Tanks are bounded by consecutive `Fuel` odometer entries: the distance
  /// between two refuels divided by the litres pumped at the closing refuel
  /// gives the average km/litre for the tank. If only one Fuel entry exists
  /// we show the current-tank progress (distance covered since the last fill).
  Widget _fuelCycleSummary(Map<String, dynamic> trip) {
    final rawLogs = trip['odometer_logs'];
    if (rawLogs is! List || rawLogs.isEmpty) return const SizedBox.shrink();

    // Pull the entries we can sort chronologically.
    final all = <Map<String, dynamic>>[];
    for (final raw in rawLogs) {
      if (raw is Map) all.add(Map<String, dynamic>.from(raw));
    }
    DateTime? readDate(Map<String, dynamic> e) {
      final value = e['recorded_at'] ?? e['created_at'] ?? e['createdAt'];
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    all.sort((a, b) {
      final da = readDate(a);
      final db = readDate(b);
      if (da == null && db == null) return 0;
      if (da == null) return -1;
      if (db == null) return 1;
      return da.compareTo(db);
    });

    int? readingOf(Map<String, dynamic> e) {
      final v = e['odometer_reading'] ?? e['odometerReading'] ?? e['reading'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    double? litersOf(Map<String, dynamic> e) {
      final v = e['liters'] ?? e['litres'];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final fuels = all
        .where(
          (e) =>
              (e['entry_type'] ?? e['entryType'] ?? '')
                      .toString()
                      .toLowerCase() ==
                  'fuel' &&
              (e['fuel_fill_type'] ?? e['fuelFillType'] ?? 'full_tank') !=
                  'extra',
        )
        .toList();

    if (fuels.isEmpty) return const SizedBox.shrink();

    String? completedLabel;
    if (fuels.length >= 2) {
      final start = fuels[fuels.length - 2];
      final end = fuels.last;
      final s = readingOf(start);
      final r = readingOf(end);
      final litres = litersOf(end);
      if (s != null && r != null && r > s && litres != null && litres > 0) {
        final distance = r - s;
        final avg = distance / litres;
        completedLabel =
            'Last tank: $distance km on ${litres.toStringAsFixed(1)} L · '
            '${avg.toStringAsFixed(1)} km/L';
      }
    }

    String currentLabel;
    final lastFuel = fuels.last;
    final lastFuelReading = readingOf(lastFuel);
    final latest = all.last;
    final latestReading = readingOf(latest);
    if (lastFuelReading != null &&
        latestReading != null &&
        latestReading >= lastFuelReading) {
      final covered = latestReading - lastFuelReading;
      currentLabel = covered == 0
          ? 'Current tank: started at $lastFuelReading km'
          : 'Current tank: $covered km since last fill';
    } else {
      currentLabel = 'Current tank: tracking…';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_gas_station,
                  size: 14,
                  color: Color(0xFF047857),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    currentLabel,
                    style: const TextStyle(
                      color: Color(0xFF047857),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (completedLabel != null) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Text(
                  completedLabel,
                  style: const TextStyle(
                    color: Color(0xFF065F46),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────
// Odometer log bottom sheet
// ────────────────────────────────────────────────

class _OdometerSheet extends StatefulWidget {
  const _OdometerSheet({
    required this.trip,
    required this.tripId,
    this.canRecord = true,
  });

  final Map<String, dynamic> trip;
  final dynamic tripId;
  final bool canRecord;

  @override
  State<_OdometerSheet> createState() => _OdometerSheetState();
}

class _OdometerSheetState extends State<_OdometerSheet> {
  List<Map<String, dynamic>> _entries = [];
  List<OutboxEntry> _pending = [];
  StreamSubscription<void>? _outboxSub;
  bool _loading = true;
  bool _saving = false;
  bool _showEntryEditor = false;
  Map<String, dynamic>? _editingEntry;
  final _entryFormKey = GlobalKey<FormState>();
  final _locationCtrl = TextEditingController();
  final _readingCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _litersCtrl = TextEditingController();
  final _unitPriceCtrl = TextEditingController();
  String _entryType = 'Movement';
  bool get _isFuelEntry => _entryType == 'Fuel' || _entryType == 'ExtraFuel';
  final ImagePicker _imagePicker = ImagePicker();

  /// Local path of the odometer photo attached to the in-progress entry.
  /// Persisted under app documents by [OdometerOutboxService.savePhoto] so it
  /// survives cache eviction while the row sits in the outbox.
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _outboxSub = OdometerOutboxService.changes.listen((_) {
      if (!mounted) return;
      _loadPending();
    });
    _loadEntries();
  }

  @override
  void dispose() {
    _outboxSub?.cancel();
    _locationCtrl.dispose();
    _readingCtrl.dispose();
    _notesCtrl.dispose();
    _litersCtrl.dispose();
    _unitPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    if (!mounted) return;
    if (_entries.isEmpty && _pending.isEmpty) {
      setState(() => _loading = true);
    }
    final id = widget.tripId;
    if (id == null) {
      setState(() {
        _entries = [];
        _pending = [];
        _loading = false;
      });
      return;
    }

    // Seed from cache first so previously-synced readings remain visible when
    // the driver reopens a trip offline.
    final cached = await OdometerLogsCacheService.read(id);
    if (!mounted) return;
    if (cached != null && cached.isNotEmpty && _entries.isEmpty) {
      setState(() {
        _entries = cached;
        _loading = false;
      });
    }

    // Pending rows are read regardless of network so the UI always shows the
    // driver's local-only entries.
    final pendingFuture = OdometerOutboxService.entriesForTrip(id);

    try {
      final data = await ApiService.fetchOdometerLogs(id);
      final pending = await pendingFuture;
      final normalized = data
          .map(
            (e) => e is Map<String, dynamic>
                ? e
                : Map<String, dynamic>.from(e as Map),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        if (normalized.isNotEmpty || _entries.isEmpty) {
          _entries = normalized;
        }
        _pending = pending;
        _loading = false;
      });
      if (normalized.isNotEmpty || _entries.isEmpty) {
        unawaited(OdometerLogsCacheService.save(id, normalized));
      }
    } catch (_) {
      // We are likely offline. Still show pending entries so the driver can
      // keep recording.
      final pending = await pendingFuture;
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _loading = false;
      });
    }
  }

  Future<void> _loadPending() async {
    final id = widget.tripId;
    if (id == null) return;
    final pending = await OdometerOutboxService.entriesForTrip(id);
    if (!mounted) return;
    setState(() => _pending = pending);
  }

  /// True when at least one Fuel-Up record exists for this trip, either
  /// already on the server or sitting in the local outbox. The driver flow
  /// requires a Fuel entry to open the first tank cycle before any other
  /// readings can be recorded.
  bool get _hasAnyFuel {
    bool isFullTankFuel(Map<String, dynamic> value) {
      final type = (value['entry_type'] ?? value['entryType'] ?? '')
          .toString()
          .toLowerCase();
      final fill =
          (value['fuel_fill_type'] ?? value['fuelFillType'] ?? 'full_tank')
              .toString();
      return type == 'fuel' && fill != 'extra';
    }

    for (final e in _entries) {
      if (isFullTankFuel(e)) return true;
    }
    for (final p in _pending) {
      if (isFullTankFuel(p.payload)) return true;
    }
    return false;
  }

  /// Highest odometer reading already recorded for this trip across both
  /// the server-confirmed `_entries` and the local outbox `_pending`,
  /// excluding the entry currently being edited (so the user can keep its
  /// existing value). The vehicle odometer only counts up, so any new
  /// reading must be greater than or equal to this value.
  int? get _lastOdometerReading {
    int? toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    final editingId = _editingEntry?['id'];
    final editingClientId = _editingEntry?['client_id'];

    int? best;
    void consider(int? value) {
      if (value == null) return;
      if (best == null || value > best!) best = value;
    }

    for (final e in _entries) {
      if (editingId != null && e['id'] == editingId) continue;
      if (editingClientId != null && e['client_id'] == editingClientId) {
        continue;
      }
      consider(toInt(e['odometer_reading'] ?? e['odometerReading']));
    }
    for (final p in _pending) {
      if (editingClientId != null &&
          p.payload['client_id'] == editingClientId) {
        continue;
      }
      consider(toInt(p.payload['odometer_reading']));
    }
    return best;
  }

  void _addEntry() {
    if (!widget.canRecord) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Operations can view odometer logs only.'),
        ),
      );
      return;
    }
    // First reading on a fresh trip MUST be a Fuel-Up so every odometer
    // entry that follows is grouped under a known tank cycle.
    final defaultType = _hasAnyFuel ? 'Movement' : 'Fuel';
    setState(() {
      _editingEntry = null;
      _entryType = defaultType;
      _locationCtrl.clear();
      _readingCtrl.clear();
      _notesCtrl.clear();
      _litersCtrl.clear();
      _unitPriceCtrl.clear();
      _photoPath = null;
      _showEntryEditor = true;
    });
  }

  void _editEntry(Map<String, dynamic> entry) {
    if (!widget.canRecord) return;
    setState(() {
      _editingEntry = entry;
      // Legacy rows may still carry Start / Stop / End – fold them all
      // into the simplified Movement type so the dropdown can match.
      final rawType = (entry['entry_type'] ?? entry['entryType'] ?? '')
          .toString();
      if (rawType.toLowerCase() == 'fuel') {
        final fillType =
            (entry['fuel_fill_type'] ?? entry['fuelFillType'] ?? 'full_tank')
                .toString();
        _entryType = fillType == 'extra' ? 'ExtraFuel' : 'Fuel';
      } else {
        _entryType = 'Movement';
      }
      _locationCtrl.text = entry['location']?.toString() ?? '';
      _readingCtrl.text =
          (entry['odometer_reading'] ?? entry['odometerReading'] ?? '')
              .toString();
      _notesCtrl.text = entry['notes']?.toString() ?? '';
      _litersCtrl.text = (entry['liters'] ?? entry['litres'] ?? '').toString();
      _unitPriceCtrl.text = (entry['unit_price'] ?? entry['unitPrice'] ?? '')
          .toString();
      _photoPath = null; // Editing remote rows; photo is server-side already.
      _showEntryEditor = true;
    });
  }

  void _cancelEditor() {
    FocusManager.instance.primaryFocus?.unfocus();
    // If the user attached a photo but cancels before saving, do not leak
    // the file we copied into the persistent directory.
    final orphaned = _photoPath;
    if (orphaned != null) {
      unawaited(OdometerOutboxService.discardPhoto(orphaned));
    }
    setState(() {
      _showEntryEditor = false;
      _editingEntry = null;
      _entryType = 'Movement';
      _locationCtrl.clear();
      _readingCtrl.clear();
      _notesCtrl.clear();
      _litersCtrl.clear();
      _unitPriceCtrl.clear();
      _photoPath = null;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null) return;
      // Copy out of the picker's temp directory so the file survives until
      // the outbox row is uploaded.
      final saved = await OdometerOutboxService.savePhoto(picked.path);
      // If the user re-shot, drop the previous file.
      if (_photoPath != null) {
        unawaited(OdometerOutboxService.discardPhoto(_photoPath));
      }
      if (!mounted) return;
      setState(() => _photoPath = saved);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not capture odometer photo. Try again.'),
        ),
      );
    }
  }

  void _clearPhoto() {
    final path = _photoPath;
    if (path == null) return;
    unawaited(OdometerOutboxService.discardPhoto(path));
    setState(() => _photoPath = null);
  }

  Future<void> _saveEntry() async {
    if (!widget.canRecord) return;
    if (!_entryFormKey.currentState!.validate()) return;

    final payload = <String, dynamic>{
      'entry_type': _isFuelEntry ? 'Fuel' : _entryType,
      'location': _locationCtrl.text.trim(),
      'odometer_reading': int.parse(_readingCtrl.text.trim()),
      'notes': _notesCtrl.text.trim(),
    };

    // Fuel events carry the litres pumped (and optional unit price / station)
    // so we can compute average km/litre over each completed tank cycle.
    if (_isFuelEntry) {
      payload['fuel_fill_type'] = _entryType == 'ExtraFuel'
          ? 'extra'
          : 'full_tank';
      final liters = double.tryParse(_litersCtrl.text.trim());
      if (liters != null) payload['liters'] = liters;
      final price = double.tryParse(_unitPriceCtrl.text.trim());
      if (price != null) payload['unit_price'] = price;
      // Location doubles as the station name for fuel events – mirror it
      // into the dedicated `station` field for backend compatibility.
      final station = _locationCtrl.text.trim();
      if (station.isNotEmpty) payload['station'] = station;
    }

    if (_photoPath != null && _photoPath!.isNotEmpty) {
      payload['photo_path'] = _photoPath;
    }

    setState(() => _saving = true);
    try {
      if (_editingEntry == null) {
        // Offline-first: every new reading is queued locally, then the sync
        // service drains the outbox whenever the device has connectivity.
        await OdometerOutboxService.enqueue(
          tripId: widget.tripId,
          payload: payload,
        );
        // Ownership of the photo file transfers to the outbox row, so clear
        // the local reference to avoid the cancel-editor cleanup deleting
        // the now-queued file.
        _photoPath = null;
        if (mounted) {
          // Kick the sync worker so online users get instant upload.
          // ignore: use_build_context_synchronously
          unawaited(context.read<OdometerSyncService>().flush());
        }
        await _loadPending();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reading saved. It will sync when online.'),
          ),
        );
      } else {
        await ApiService.updateOdometerLog(_editingEntry!['id'], payload);
        await _loadEntries();
      }
      if (!mounted) return;
      _cancelEditor();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save entry: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    if (!widget.canRecord) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(kDarkCard),
        title: const Text(
          'Delete Entry',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Remove this odometer entry?',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ApiService.deleteOdometerLog(entry['id']);
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = widget.trip['booking_ref'] ?? widget.trip['ref'] ?? 'Trip';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Sheet header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(kGoldColor).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.speed_outlined,
                    color: Color(kGoldColor),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Movement Odometer Log',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        ref.toString(),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(kGoldColor),
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),

          if (_pending.isNotEmpty) _pendingStatusBar(),

          if (!_loading && !_hasAnyFuel) _fuelFirstBanner(),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Divider(height: 1),
          ),

          // Entries / loading / inline editor share the remaining space.
          // When the editor is open we give it the full flex slot so its
          // internal SingleChildScrollView gets a bounded height and the
          // Save / Cancel row can never overflow when the keyboard is up.
          Expanded(
            child: _showEntryEditor
                ? _buildInlineEntryEditor(theme)
                : _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(kGoldColor)),
                  )
                : (_entries.isEmpty && _pending.isEmpty)
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_gas_station_outlined,
                        size: 52,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _hasAnyFuel
                            ? 'No odometer entries yet'
                            : 'Start with a Fuel-Up',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _hasAnyFuel
                            ? 'Tap "Add Entry" to record the next\nodometer reading.'
                            : 'Record a full-tank fuel-up first.\nAll trip readings will be grouped\nunder it.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    children: _buildGroupedEntries(theme),
                  ),
          ),

          if (!widget.canRecord)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'View only: operations can review odometer logs but cannot record entries.',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // Add button (hidden while the inline editor owns the slot above –
          // the editor brings its own Cancel / Save row).
          if (!_showEntryEditor && widget.canRecord)
            Padding(
              // Stack the keyboard inset and the system gesture / nav-bar
              // inset so the CTA never hides under the on-screen nav icons
              // on tablets / gesture-nav phones.
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).viewPadding.bottom +
                    16,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _addEntry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(kGoldColor),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    _hasAnyFuel ? Icons.add : Icons.local_gas_station,
                    size: 20,
                  ),
                  label: Text(
                    _hasAnyFuel ? 'Add Entry' : 'Record Fuel Up',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Prominent prompt shown until the trip has its first Fuel-Up record.
  /// Reinforces the workflow: refuel \u2192 record fuel + odometer \u2192 then drive
  /// and capture stops under that tank cycle.
  Widget _fuelFirstBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          border: Border.all(color: const Color(0xFFFDE68A)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.local_gas_station,
              color: Color(0xFFB45309),
              size: 22,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start the tank cycle',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Fuel up to a full tank, take a photo of the odometer, '
                    'then record movements under this tank.',
                    style: TextStyle(color: Color(0xFF92400E), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the grouped list of entries for the sheet.
  ///
  /// Pending (outbox) and remote entries are merged, sorted by their recorded
  /// timestamp, and split into "tank cycles". A new cycle starts at every
  /// `Fuel` entry; readings recorded before any Fuel-Up land in an
  /// "Unassigned" group at the top so nothing disappears, but the workflow
  /// makes that group rare.
  List<Widget> _buildGroupedEntries(ThemeData theme) {
    final fallback = DateTime.fromMillisecondsSinceEpoch(0);
    DateTime parseStamp(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? fallback;
      }
      return fallback;
    }

    String typeOf(Map<String, dynamic> payload) {
      final type = (payload['entry_type'] ?? payload['entryType'] ?? 'Movement')
          .toString()
          .toLowerCase();
      final fill =
          (payload['fuel_fill_type'] ?? payload['fuelFillType'] ?? 'full_tank')
              .toString();
      return type == 'fuel' && fill == 'extra' ? 'extra_fuel' : type;
    }

    // Normalize both sources into a single list of items we can sort.
    final items = <_TimelineItem>[];
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      items.add(
        _TimelineItem(
          isPending: false,
          stamp: parseStamp(
            e['recorded_at'] ?? e['created_at'] ?? e['createdAt'],
          ),
          entry: e,
          index: i,
          type: typeOf(e),
        ),
      );
    }
    for (final p in _pending) {
      items.add(
        _TimelineItem(
          isPending: true,
          stamp: parseStamp(p.payload['recorded_at']),
          pending: p,
          type: typeOf(p.payload),
        ),
      );
    }

    items.sort((a, b) => a.stamp.compareTo(b.stamp));

    // Index server-side fuel rows by id so non-fuel readings that already
    // carry a `fuel_log_id` can be attached to the exact tank cycle the
    // backend assigned, even if recorded_at would have placed them under a
    // different fuel-up due to clock skew or back-dated entries.
    final fuelGroups = <_TankGroup>[];
    final fuelById = <String, _TankGroup>{};
    for (final it in items) {
      if (it.type == 'fuel') {
        final group = _TankGroup(fuel: it);
        fuelGroups.add(group);
        final id = it.entry?['id'];
        if (id != null) fuelById[id.toString()] = group;
      }
    }

    // Walk readings in chronological order. Prefer the server-supplied
    // fuel_log_id when present; otherwise fall back to "the most recent
    // fuel-up so far" so offline-pending entries still group cleanly.
    final orphan = _TankGroup(label: 'Before first fuel-up');
    _TankGroup? mostRecentFuel;
    for (final it in items) {
      if (it.type == 'fuel') {
        mostRecentFuel =
            fuelById[it.entry?['id']?.toString()] ??
            // Pending fuel rows aren't keyed by id yet; locate by reference.
            fuelGroups.firstWhere(
              (g) => identical(g.fuel, it),
              orElse: () => _TankGroup(fuel: it),
            );
        continue;
      }

      _TankGroup? target;
      final serverFuelId = it.entry?['fuel_log_id'];
      if (serverFuelId != null) {
        target = fuelById[serverFuelId.toString()];
      }
      target ??= mostRecentFuel;

      if (target != null) {
        target.children.add(it);
      } else {
        orphan.children.add(it);
      }
    }

    final widgets = <Widget>[];
    if (orphan.children.isNotEmpty) {
      widgets.add(_groupHeader(theme, orphan, cycleNumber: null));
      widgets.addAll(orphan.children.map((it) => _renderItem(it, theme)));
      widgets.add(const SizedBox(height: 8));
    }
    for (var i = 0; i < fuelGroups.length; i++) {
      final g = fuelGroups[i];
      // The cycle is "closed" by the next fuel-up. Pass that fuel-up so the
      // header can display the driver's average km/L for the closed tank.
      final nextFuel = i + 1 < fuelGroups.length
          ? fuelGroups[i + 1].fuel
          : null;
      widgets.add(
        _groupHeader(theme, g, cycleNumber: i + 1, nextFuel: nextFuel),
      );
      // The fuel entry itself heads the cycle, then its child movements.
      widgets.add(_renderItem(g.fuel!, theme));
      widgets.addAll(g.children.map((it) => _renderItem(it, theme)));
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }

  Widget _renderItem(_TimelineItem it, ThemeData theme) {
    if (it.isPending) {
      return _pendingTile(it.pending!, theme);
    }
    return _entryTile(it.entry!, it.index ?? 0, theme);
  }

  /// Header card that introduces a tank cycle (or the orphan group when
  /// readings exist before the first fuel-up).
  ///
  /// [nextFuel] is the fuel-up that closes this cycle (i.e. the next refill).
  /// When present we can compute the driver's km / L average for the closed
  /// tank: total km between the two refills divided by litres pumped at the
  /// closing fill (which is what was consumed since the previous full tank).
  Widget _groupHeader(
    ThemeData theme,
    _TankGroup group, {
    required int? cycleNumber,
    _TimelineItem? nextFuel,
  }) {
    if (cycleNumber == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_outlined,
              size: 16,
              color: Color(0xFFB45309),
            ),
            const SizedBox(width: 6),
            Text(
              group.label ?? 'Unassigned readings',
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final fuel = group.fuel!;
    final payload = fuel.isPending ? fuel.pending!.payload : fuel.entry!;
    final litres = payload['liters'] ?? payload['litres'];
    final reading =
        payload['odometer_reading'] ??
        payload['odometerReading'] ??
        payload['reading'];
    // A Fuel log is "closed" by the next fuel-up on the same trip; the
    // server stamps `closed_at` when that happens. Open cycles keep a
    // gentle pulse so drivers can tell which tank is still active.
    final closedAtRaw = fuel.isPending ? null : payload['closed_at'];
    final isClosed =
        (closedAtRaw is String && closedAtRaw.isNotEmpty) || nextFuel != null;

    int? toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    double? toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim());
      return null;
    }

    int? readingOf(_TimelineItem item) {
      final p = item.isPending ? item.pending!.payload : item.entry!;
      return toInt(
        p['odometer_reading'] ?? p['odometerReading'] ?? p['reading'],
      );
    }

    // Compute the driver-average row when this cycle is closed by a later
    // fuel-up. Distance = next.reading - this.reading; litres consumed =
    // litres pumped at the next fuel-up (full-tank refill assumption).
    String? statsLabel;
    final startReading = toInt(reading);
    if (nextFuel != null && startReading != null) {
      final nextPayload = nextFuel.isPending
          ? nextFuel.pending!.payload
          : nextFuel.entry!;
      final endReading = toInt(
        nextPayload['odometer_reading'] ??
            nextPayload['odometerReading'] ??
            nextPayload['reading'],
      );
      final consumed = toDouble(nextPayload['liters'] ?? nextPayload['litres']);
      if (endReading != null && endReading > startReading) {
        final distance = endReading - startReading;
        if (consumed != null && consumed > 0) {
          final avg = distance / consumed;
          final pctOfTank = (consumed / kVehicleFuelCapacityLitres) * 100;
          statsLabel =
              '$distance km \u00b7 ${consumed.toStringAsFixed(1)} L used '
              '(${pctOfTank.toStringAsFixed(0)}% of '
              '${kVehicleFuelCapacityLitres.toStringAsFixed(0)} L tank) '
              '\u00b7 Avg ${avg.toStringAsFixed(1)} km/L';
        } else {
          statsLabel = '$distance km covered this tank';
        }
      }
    } else if (group.children.isNotEmpty && startReading != null) {
      // Open cycle – show distance covered so far against the highest
      // movement reading recorded against this tank.
      int? maxChild;
      for (final c in group.children) {
        final r = readingOf(c);
        if (r == null) continue;
        if (maxChild == null || r > maxChild) maxChild = r;
      }
      if (maxChild != null && maxChild > startReading) {
        final covered = maxChild - startReading;
        statsLabel = '$covered km so far \u00b7 next refill closes this tank';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isClosed ? const Color(0xFFF0FDF4) : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isClosed ? const Color(0xFFBBF7D0) : const Color(0xFFA7F3D0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isClosed ? Icons.check_circle : Icons.local_gas_station,
                  size: 16,
                  color: const Color(0xFF047857),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tank Cycle #$cycleNumber'
                    '${litres != null ? ' \u00b7 ${litres}L' : ''}'
                    '${reading != null ? ' \u00b7 from $reading km' : ''}'
                    '${isClosed ? ' \u00b7 closed' : ' \u00b7 open'}',
                    style: const TextStyle(
                      color: Color(0xFF047857),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (group.children.isNotEmpty)
                  Text(
                    '${group.children.length} stop${group.children.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFF065F46),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (statsLabel != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  statsLabel,
                  style: const TextStyle(
                    color: Color(0xFF065F46),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlineEntryEditor(ThemeData theme) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      // Same reasoning as the Add button above: lift the editor's Cancel /
      // Save row above the system gesture / nav-bar area.
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom +
            12,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outline, width: 0.8),
        ),
        child: Form(
          key: _entryFormKey,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.edit_note,
                        color: Color(kGoldColor),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _editingEntry == null
                              ? 'Add Odometer Entry'
                              : 'Edit Odometer Entry',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _entryType,
                    decoration: const InputDecoration(labelText: 'Entry Type'),
                    items: _hasAnyFuel
                        ? const [
                            DropdownMenuItem(
                              value: 'Movement',
                              child: Text('Route Movement'),
                            ),
                            DropdownMenuItem(
                              value: 'Fuel',
                              child: Text('Fuel Up (Full Tank)'),
                            ),
                            DropdownMenuItem(
                              value: 'ExtraFuel',
                              child: Text('Extra Fuel (Partial Fill)'),
                            ),
                          ]
                        : const [
                            // No fuel cycle has been opened yet – lock the
                            // form to Fuel-Up so we never orphan readings.
                            DropdownMenuItem(
                              value: 'Fuel',
                              child: Text('Fuel Up (Full Tank)'),
                            ),
                          ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _entryType = v);
                    },
                  ),
                  if (_isFuelEntry) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_gas_station,
                            size: 16,
                            color: Color(0xFFB45309),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _entryType == 'ExtraFuel'
                                  ? 'Partial fill: record the mileage, litres added, and price. This will not close the current full-tank cycle.'
                                  : 'Record the odometer BEFORE filling up, then enter litres pumped to a full tank.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locationCtrl,
                    decoration: InputDecoration(
                      labelText: _isFuelEntry
                          ? 'Fuel Station / Location'
                          : 'Location / Place Name',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Location is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (_lastOdometerReading != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.history,
                            size: 16,
                            color: Color(0xFF1D4ED8),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Last recorded reading: '
                              '${_lastOdometerReading} km. '
                              'New reading must be ≥ this value.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextFormField(
                    controller: _readingCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Odometer Reading (km)',
                      prefixIcon: const Icon(Icons.speed_outlined),
                      helperText: _lastOdometerReading != null
                          ? 'Previous: ${_lastOdometerReading} km'
                          : null,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Reading is required';
                      }
                      final parsed = int.tryParse(v.trim());
                      if (parsed == null) {
                        return 'Enter a valid number';
                      }
                      final last = _lastOdometerReading;
                      if (last != null && parsed < last) {
                        return 'Reading cannot be less than $last km';
                      }
                      return null;
                    },
                  ),
                  if (_isFuelEntry) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _litersCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: _entryType == 'ExtraFuel'
                            ? 'Extra Litres Added'
                            : 'Litres Filled (full tank)',
                        prefixIcon: const Icon(
                          Icons.local_gas_station_outlined,
                        ),
                      ),
                      validator: (v) {
                        if (!_isFuelEntry) return null;
                        if (v == null || v.trim().isEmpty) {
                          return 'Litres are required';
                        }
                        final parsed = double.tryParse(v.trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a valid litre amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _unitPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Price / Litre',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _photoAttachmentField(theme),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _cancelEditor,
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _saveEntry,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(kGoldColor),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact attachment row for the odometer photo. Drivers can either take a
  /// fresh picture or pull an existing one from the gallery; the thumbnail is
  /// shown inline and can be cleared before saving.
  Widget _photoAttachmentField(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _photoPath == null
                ? Container(
                    width: 56,
                    height: 56,
                    color: const Color(0xFFE2E8F0),
                    child: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFF94A3B8),
                    ),
                  )
                : Image.file(
                    File(_photoPath!),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFFFEE2E2),
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _photoPath == null ? 'Odometer Photo' : 'Photo attached',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _photoPath == null
                      ? 'Snap a picture of the dashboard so the office '
                            'can verify the reading.'
                      : 'Tap retake to replace, or clear to remove.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                tooltip: _photoPath == null ? 'Take photo' : 'Retake',
                onPressed: _saving
                    ? null
                    : () => _pickPhoto(ImageSource.camera),
                icon: const Icon(
                  Icons.photo_camera_outlined,
                  color: Color(kGoldColor),
                ),
              ),
              if (_photoPath == null)
                IconButton(
                  tooltip: 'Pick from gallery',
                  onPressed: _saving
                      ? null
                      : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFF64748B),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Remove photo',
                  onPressed: _saving ? null : _clearPhoto,
                  icon: const Icon(Icons.close, color: Color(0xFFDC2626)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entryTile(Map<String, dynamic> entry, int index, ThemeData theme) {
    final location = entry['location'] ?? entry['place'] ?? 'Unknown location';
    final reading =
        entry['odometer_reading'] ??
        entry['odometerReading'] ??
        entry['reading'] ??
        '-';
    final notes = entry['notes'] ?? '';
    final entryType = entry['entry_type'] ?? entry['entryType'] ?? 'Movement';
    final fuelFillType =
        (entry['fuel_fill_type'] ?? entry['fuelFillType'] ?? 'full_tank')
            .toString();
    final entryLabel =
        entryType.toString().toLowerCase() == 'fuel' && fuelFillType == 'extra'
        ? 'Extra Fuel'
        : entryType.toString();
    final remotePhotoUrl = _resolveRemotePhotoUrl(entry);
    final hasPhoto = remotePhotoUrl != null;

    IconData typeIcon;
    Color typeColor;
    switch (entryType.toString().toLowerCase()) {
      case 'start':
        typeIcon = Icons.flag_outlined;
        typeColor = const Color(0xFF16A34A);
        break;
      case 'end':
        typeIcon = Icons.sports_score_outlined;
        typeColor = Colors.redAccent;
        break;
      default:
        typeIcon = Icons.place_outlined;
        typeColor = const Color(kGoldColor);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: typeColor.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(typeIcon, size: 18, color: typeColor),
          ),
          const SizedBox(width: 12),

          // Location + notes
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location.toString(),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (notes.toString().isNotEmpty)
                  Text(
                    notes.toString(),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Reading badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(kGoldColor).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$reading km',
                  style: const TextStyle(
                    color: Color(kGoldColor),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entryLabel,
                style: TextStyle(color: typeColor, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 8),

          if (hasPhoto)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _entryPhotoThumb(
                remoteUrl: remotePhotoUrl,
                onTap: () => _openPhotoPreview(remoteUrl: remotePhotoUrl),
              ),
            ),

          if (widget.canRecord)
            Column(
              children: [
                GestureDetector(
                  onTap: () => _editEntry(entry),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _deleteEntry(entry),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ─── Offline / sync UI ──────────────────────────────────────────────────

  Widget _pendingStatusBar() {
    final sync = context.watch<OdometerSyncService>();
    final failed = _pending
        .where((e) => e.status == OutboxStatus.failed)
        .length;
    final waiting = _pending.length - failed;

    final color = failed > 0
        ? const Color(0xFFDC2626)
        : const Color(0xFFD97706);
    final bg = failed > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);
    final border = failed > 0
        ? const Color(0xFFFECACA)
        : const Color(0xFFFDE68A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: sync.isSyncing,
              builder: (context, syncing, _) => SizedBox(
                width: 14,
                height: 14,
                child: syncing
                    ? CircularProgressIndicator(strokeWidth: 2, color: color)
                    : Icon(
                        failed > 0 ? Icons.error_outline : Icons.cloud_off,
                        size: 14,
                        color: color,
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusBarText(waiting: waiting, failed: failed),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => sync.flush(includeFailed: true),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Retry',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusBarText({required int waiting, required int failed}) {
    if (failed > 0 && waiting > 0) {
      return '$waiting waiting · $failed failed';
    }
    if (failed > 0) return '$failed reading(s) failed to sync';
    return '$waiting reading(s) waiting to sync';
  }

  Widget _pendingTile(OutboxEntry entry, ThemeData theme) {
    final p = entry.payload;
    final location = (p['location'] ?? p['place'] ?? 'Unknown location')
        .toString();
    final reading =
        (p['odometer_reading'] ?? p['odometerReading'] ?? p['reading'] ?? '-')
            .toString();
    final notes = (p['notes'] ?? '').toString();
    final entryType = (p['entry_type'] ?? p['entryType'] ?? 'Movement')
        .toString();
    final fuelFillType =
        (p['fuel_fill_type'] ?? p['fuelFillType'] ?? 'full_tank').toString();
    final entryLabel =
        entryType.toLowerCase() == 'fuel' && fuelFillType == 'extra'
        ? 'Extra Fuel'
        : entryType;
    final localPhotoPath = (p['photo_path'] is String)
        ? (p['photo_path'] as String)
        : null;
    final hasPhoto = localPhotoPath != null && localPhotoPath.isNotEmpty;
    final failed = entry.status == OutboxStatus.failed;

    final color = failed ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final bg = failed ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);
    final border = failed ? const Color(0xFFFECACA) : const Color(0xFFFDE68A);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              failed ? Icons.error_outline : Icons.cloud_upload_outlined,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  failed
                      ? (entry.lastError ?? 'Failed after retries')
                      : (entry.lastError != null
                            ? 'Retrying: ${entry.lastError}'
                            : (notes.isNotEmpty
                                  ? notes
                                  : 'Waiting to upload…')),
                  style: TextStyle(color: color, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$reading km',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$entryLabel · ${failed ? 'Failed' : 'Pending'}',
                style: TextStyle(color: color, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 8),
          if (hasPhoto)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _entryPhotoThumb(
                localPath: localPhotoPath,
                onTap: () => _openPhotoPreview(localPath: localPhotoPath),
              ),
            ),
          IconButton(
            tooltip: 'Discard',
            onPressed: () async {
              await OdometerOutboxService.delete(entry.id);
              await _loadPending();
            },
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  String? _resolveRemotePhotoUrl(Map<String, dynamic> payload) {
    final rawUrl = payload['photo_url'] ?? payload['photoUrl'];
    if (rawUrl is String && rawUrl.trim().isNotEmpty) {
      final url = rawUrl.trim();
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
      }
      if (url.startsWith('/')) return '$kBackendOrigin$url';
      return '$kBackendOrigin/$url';
    }

    final rawPath = payload['photo_path'] ?? payload['photoPath'];
    if (rawPath is! String || rawPath.trim().isEmpty) return null;
    final path = rawPath.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/storage/')) return '$kBackendOrigin$path';
    if (path.startsWith('storage/')) return '$kBackendOrigin/$path';
    return '$kBackendOrigin/storage/$path';
  }

  Widget _entryPhotoThumb({
    String? remoteUrl,
    String? localPath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          color: const Color(0xFFE2E8F0),
          child: localPath != null
              ? Image.file(
                  File(localPath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                )
              : Image.network(
                  remoteUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _openPhotoPreview({String? remoteUrl, String? localPath}) async {
    if (remoteUrl == null && localPath == null) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: localPath != null
                    ? Image.file(File(localPath), fit: BoxFit.contain)
                    : Image.network(remoteUrl!, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight value object used by the odometer sheet to merge remote
/// entries and queued outbox rows into a single chronologically sortable
/// timeline.
class _TimelineItem {
  _TimelineItem({
    required this.isPending,
    required this.stamp,
    required this.type,
    this.entry,
    this.pending,
    this.index,
  });

  final bool isPending;
  final DateTime stamp;
  final String type;
  final Map<String, dynamic>? entry;
  final OutboxEntry? pending;
  final int? index;
}

/// A tank cycle: one Fuel-Up entry plus all the movement readings recorded
/// before the next Fuel-Up. The orphan group (no [fuel]) holds anything that
/// somehow predates the first fuel record.
class _TankGroup {
  _TankGroup({this.fuel, this.label});

  final _TimelineItem? fuel;
  final String? label;
  final List<_TimelineItem> children = <_TimelineItem>[];
}

/// Compact AppBar chip that surfaces the number of odometer readings still
/// queued for upload, and lets the driver kick off a manual sync.
class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<OdometerSyncService>();
    return ValueListenableBuilder<int>(
      valueListenable: sync.pendingCount,
      builder: (context, count, _) {
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Material(
            color: const Color(0xFFFFFBEB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFFDE68A)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => sync.flush(includeFailed: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: sync.isSyncing,
                      builder: (context, syncing, _) => SizedBox(
                        width: 12,
                        height: 12,
                        child: syncing
                            ? const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFD97706),
                              )
                            : const Icon(
                                Icons.cloud_off,
                                size: 12,
                                color: Color(0xFFD97706),
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$count pending',
                      style: const TextStyle(
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
