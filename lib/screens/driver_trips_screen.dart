import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';

class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({
    super.key,
    required this.driver,
    this.useCurrentAssignments = false,
  });

  final Map<String, dynamic> driver;
  final bool useCurrentAssignments;

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _trips = <dynamic>[];
  bool _loading = true;

  String get _driverName =>
      (widget.driver['name'] ?? widget.driver['full_name'] ?? 'Driver')
          .toString();

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
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<dynamic> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _trips;
    return _trips.where((t) {
      final lead = t['lead'];
      final ref =
          (t['booking_ref'] ??
                  t['bookingRef'] ??
                  t['ref'] ??
                  (lead is Map ? lead['bookingRef'] : null) ??
                  '')
              .toString()
              .toLowerCase();
      final client =
          (t['client_company'] ??
                  t['clientCompany'] ??
                  t['client'] ??
                  (lead is Map ? lead['clientCompany'] : null) ??
                  '')
              .toString()
              .toLowerCase();
      final route =
          (t['route'] ??
                  t['destination'] ??
                  t['route_parks'] ??
                  t['routeParks'] ??
                  (lead is Map ? lead['routeParks'] : null) ??
                  '')
              .toString()
              .toLowerCase();
      final status = (t['status'] ?? '').toString().toLowerCase();
      return ref.contains(q) ||
          client.contains(q) ||
          route.contains(q) ||
          status.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final id = _driverId;
      final data = widget.useCurrentAssignments
          ? await ApiService.fetchMyAssignedTrips()
          : id != null
          ? await ApiService.fetchDriverTrips(id)
          : await ApiService.fetchMyAssignedTrips();
      if (!mounted) return;
      setState(() {
        _trips = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load trips: $e')));
    }
  }

  void _showOdometerSheet(Map<String, dynamic> trip) {
    final tripId = trip['id'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OdometerSheet(trip: trip, tripId: tripId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _driverName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const Text(
              'My Day-to-Day Safari Movement',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
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
              child: _filtered.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 100),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.route_outlined,
                                size: 56,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withOpacity(0.4),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No trips assigned yet',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Trips assigned to $_driverName will\nappear here.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) =>
                          _tripCard(_filtered[i] as Map<String, dynamic>),
                    ),
            ),
    );
  }

  Widget _tripCard(Map<String, dynamic> trip) {
    final theme = Theme.of(context);
    final lead = trip['lead'];
    final ref =
        trip['booking_ref'] ??
        trip['bookingRef'] ??
        trip['ref'] ??
        (lead is Map ? lead['bookingRef'] : null) ??
        '-';
    final client =
        trip['client_company'] ??
        trip['clientCompany'] ??
        trip['client'] ??
        (lead is Map ? lead['clientCompany'] : null) ??
        '-';
    final route =
        trip['route'] ??
        trip['route_parks'] ??
        trip['routeParks'] ??
        trip['destination'] ??
        (lead is Map ? lead['routeParks'] : null) ??
        'Route not specified';
    final status = trip['status'] ?? 'Pending';
    final startDate =
        trip['start_date'] ??
        trip['startDate'] ??
        (lead is Map ? lead['startDate'] : null) ??
        '';
    final endDate =
        trip['end_date'] ??
        trip['endDate'] ??
        (lead is Map ? lead['endDate'] : null) ??
        '';
    final vehicleMap = trip['vehicle'];
    final vehicle = vehicleMap is Map
        ? '${vehicleMap['make'] ?? ''} ${vehicleMap['model'] ?? ''} ${(vehicleMap['plateNo'] ?? vehicleMap['vehicleNo'] ?? '').toString().trim()}'
              .trim()
        : (trip['vehicle_plate'] ?? trip['vehiclePlate'] ?? '');
    final odometerCount =
        (trip['odometer_logs'] as List?)?.length ??
        trip['odometer_log_count'] ??
        0;

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

    return Container(
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
                if (route.isNotEmpty)
                  _infoRow(Icons.location_on_outlined, route.toString(), theme),
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
              ],
            ),
          ),

          // Odometer summary strip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  'Odometer Log',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
}

// ────────────────────────────────────────────────
// Odometer log bottom sheet
// ────────────────────────────────────────────────

class _OdometerSheet extends StatefulWidget {
  const _OdometerSheet({required this.trip, required this.tripId});

  final Map<String, dynamic> trip;
  final dynamic tripId;

  @override
  State<_OdometerSheet> createState() => _OdometerSheetState();
}

class _OdometerSheetState extends State<_OdometerSheet> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _saving = false;
  bool _showEntryEditor = false;
  Map<String, dynamic>? _editingEntry;
  final _entryFormKey = GlobalKey<FormState>();
  final _locationCtrl = TextEditingController();
  final _readingCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _entryType = 'Stop';

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _readingCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final id = widget.tripId;
      if (id == null) {
        setState(() {
          _entries = [];
          _loading = false;
        });
        return;
      }
      final data = await ApiService.fetchOdometerLogs(id);
      if (!mounted) return;
      setState(() {
        _entries = data
            .map(
              (e) => e is Map<String, dynamic>
                  ? e
                  : Map<String, dynamic>.from(e as Map),
            )
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _addEntry() {
    setState(() {
      _editingEntry = null;
      _entryType = 'Stop';
      _locationCtrl.clear();
      _readingCtrl.clear();
      _notesCtrl.clear();
      _showEntryEditor = true;
    });
  }

  void _editEntry(Map<String, dynamic> entry) {
    setState(() {
      _editingEntry = entry;
      _entryType = (entry['entry_type'] ?? entry['entryType'] ?? 'Stop')
          .toString();
      _locationCtrl.text = entry['location']?.toString() ?? '';
      _readingCtrl.text =
          (entry['odometer_reading'] ?? entry['odometerReading'] ?? '')
              .toString();
      _notesCtrl.text = entry['notes']?.toString() ?? '';
      _showEntryEditor = true;
    });
  }

  void _cancelEditor() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _showEntryEditor = false;
      _editingEntry = null;
      _entryType = 'Stop';
      _locationCtrl.clear();
      _readingCtrl.clear();
      _notesCtrl.clear();
    });
  }

  Future<void> _saveEntry() async {
    if (!_entryFormKey.currentState!.validate()) return;

    final payload = <String, dynamic>{
      'entry_type': _entryType,
      'location': _locationCtrl.text.trim(),
      'odometer_reading': int.parse(_readingCtrl.text.trim()),
      'notes': _notesCtrl.text.trim(),
    };

    setState(() => _saving = true);
    try {
      if (_editingEntry == null) {
        await ApiService.createOdometerLog(widget.tripId, payload);
      } else {
        await ApiService.updateOdometerLog(_editingEntry!['id'], payload);
      }
      await _loadEntries();
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

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Divider(height: 1),
          ),

          // Entries or loading
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(kGoldColor)),
                  )
                : _entries.isEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.speed_outlined,
                        size: 52,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No odometer entries yet',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tap "Add Entry" to record the first\nodometer reading.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) => _entryTile(_entries[i], i, theme),
                  ),
          ),

          if (_showEntryEditor) _buildInlineEntryEditor(theme),

          // Add button
          if (!_showEntryEditor)
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(context).viewInsets.bottom + 16,
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
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text(
                    'Add Stop Entry',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineEntryEditor(ThemeData theme) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        MediaQuery.of(context).viewInsets.bottom + 12,
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
                    items: const [
                      DropdownMenuItem(
                        value: 'Start',
                        child: Text('Start Reading'),
                      ),
                      DropdownMenuItem(
                        value: 'Stop',
                        child: Text('Stop / Location'),
                      ),
                      DropdownMenuItem(
                        value: 'End',
                        child: Text('End Reading'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _entryType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locationCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Location / Place Name',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Location is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _readingCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Odometer Reading (km)',
                      prefixIcon: Icon(Icons.speed_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Reading is required';
                      }
                      if (int.tryParse(v.trim()) == null) {
                        return 'Enter a valid number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
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

  Widget _entryTile(Map<String, dynamic> entry, int index, ThemeData theme) {
    final location = entry['location'] ?? entry['place'] ?? 'Unknown location';
    final reading =
        entry['odometer_reading'] ??
        entry['odometerReading'] ??
        entry['reading'] ??
        '-';
    final notes = entry['notes'] ?? '';
    final entryType = entry['entry_type'] ?? entry['entryType'] ?? 'Stop';

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
                entryType.toString(),
                style: TextStyle(color: typeColor, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // Edit / Delete
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
}
