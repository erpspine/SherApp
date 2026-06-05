import 'package:flutter/material.dart';
import '../services/api_service.dart';

class VehicleAvailabilityScreen extends StatefulWidget {
  const VehicleAvailabilityScreen({super.key});

  @override
  State<VehicleAvailabilityScreen> createState() =>
      _VehicleAvailabilityScreenState();
}

class _VehicleAvailabilityScreenState extends State<VehicleAvailabilityScreen> {
  bool _loading = true;
  String _error = '';

  List<Map<String, dynamic>> _vehicles = <Map<String, dynamic>>[];
  Map<int, List<Map<String, dynamic>>> _vehicleAllocations =
      <int, List<Map<String, dynamic>>>{};

  DateTime _timelineStart = DateTime.now();
  DateTime _timelineEnd = DateTime.now().add(const Duration(days: 89));

  int _calendarMonth = DateTime.now().month;
  int _calendarYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calendarMonth = now.month;
    _calendarYear = now.year;
    _updateTimelineRange();
    _load();
  }

  void _updateTimelineRange() {
    _timelineStart = DateTime(_calendarYear, _calendarMonth, 1);
    _timelineEnd = _timelineStart.add(const Duration(days: 89));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final vehiclesRaw = await ApiService.fetchList(
        '/vehicles',
      ).catchError((_) => <dynamic>[]);
      final allocationsRaw = await ApiService.fetchList(
        '/safari-allocations',
      ).catchError((_) => <dynamic>[]);
      final leadsRaw = await ApiService.fetchList(
        '/leads',
      ).catchError((_) => <dynamic>[]);

      final vehicles = vehiclesRaw is List ? vehiclesRaw : <dynamic>[];
      final allocations = allocationsRaw is List ? allocationsRaw : <dynamic>[];
      final leads = leadsRaw is List ? leadsRaw : <dynamic>[];

      // Index leads by ID
      final leadsById = <String, Map<String, dynamic>>{};
      for (final item in leads) {
        if (item is Map) {
          leadsById[(item['id'] ?? '').toString()] = Map<String, dynamic>.from(
            item,
          );
        }
      }

      // Group allocations by vehicle
      final allocsByVehicle = <int, List<Map<String, dynamic>>>{};
      for (final raw in allocations) {
        if (raw is! Map) continue;
        final alloc = Map<String, dynamic>.from(raw);

        final vehicleId = int.tryParse(
          (alloc['vehicle_id'] ?? alloc['vehicleId'] ?? '').toString(),
        );
        if (vehicleId == null) continue;

        final leadId = (alloc['lead_id'] ?? alloc['leadId'] ?? '').toString();
        final lead = (alloc['lead'] is Map)
            ? alloc['lead'] as Map
            : leadsById[leadId];

        if (lead == null) continue;

        final start = _parseDate(lead['start_date'] ?? lead['startDate']);
        final end = _parseDate(lead['end_date'] ?? lead['endDate']);
        if (start == null || end == null) continue;

        allocsByVehicle
            .putIfAbsent(vehicleId, () => <Map<String, dynamic>>[])
            .add({
              'bookingRef': lead['booking_ref'] ?? lead['bookingRef'] ?? '-',
              'startDate': start,
              'endDate': end,
              'status': alloc['status'] ?? 'Assigned',
              'driverName': (alloc['driver'] is Map)
                  ? (alloc['driver']['name'] ?? 'Unknown').toString()
                  : 'Unknown',
              'routeParks':
                  lead['route'] ??
                  lead['route_parks'] ??
                  lead['routeParks'] ??
                  '',
            });
      }

      setState(() {
        _vehicles = (vehicles is List)
            ? vehicles
                  .whereType<Map<String, dynamic>>()
                  .map((v) => Map<String, dynamic>.from(v))
                  .toList()
            : <Map<String, dynamic>>[];
        _vehicleAllocations = allocsByVehicle;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  void _previousMonth() {
    setState(() {
      if (_calendarMonth == 1) {
        _calendarMonth = 12;
        _calendarYear -= 1;
      } else {
        _calendarMonth -= 1;
      }
      _updateTimelineRange();
    });
  }

  void _nextMonth() {
    setState(() {
      if (_calendarMonth == 12) {
        _calendarMonth = 1;
        _calendarYear += 1;
      } else {
        _calendarMonth += 1;
      }
      _updateTimelineRange();
    });
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return const Color(0xFF34D399);
      case 'completed':
        return const Color(0xFF818CF8);
      case 'cancelled':
        return const Color(0xFFFB7185);
      default:
        return const Color(0xFF60A5FA);
    }
  }

  String _monthLabel(int year, int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[(month - 1).clamp(0, 11)]} $year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Vehicle Availability',
          style: TextStyle(
            color: Color(0xFF0F1F3D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.refresh,
                  color: Color(0xFF475467),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFB88910),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Error loading data',
                    style: TextStyle(
                      color: Color(0xFF0F1F3D),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : _vehicles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.directions_car_outlined,
                    color: const Color(0xFFB88910).withOpacity(0.5),
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No vehicles available',
                    style: TextStyle(
                      color: Color(0xFF0F1F3D),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header with Month Navigation ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFE5E8EE),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month,
                            color: Color(0xFFB88910),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _monthLabel(_calendarYear, _calendarMonth),
                              style: const TextStyle(
                                color: Color(0xFF0F1F3D),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _previousMonth,
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.chevron_left,
                                color: Color(0xFF475467),
                                size: 20,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _nextMonth,
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.chevron_right,
                                color: Color(0xFF475467),
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Legend ──
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5E2).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _Legend(color: Color(0xFF60A5FA), label: 'Assigned'),
                          _Legend(color: Color(0xFF34D399), label: 'Confirmed'),
                          _Legend(color: Color(0xFF818CF8), label: 'Completed'),
                          _Legend(color: Color(0xFFFB7185), label: 'Cancelled'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Vehicle Timeline List ──
                    ..._vehicles.map((vehicle) {
                      final vehicleId = int.tryParse(
                        (vehicle['id'] ?? '').toString(),
                      );
                      final allocations = vehicleId != null
                          ? (_vehicleAllocations[vehicleId] ??
                                <Map<String, dynamic>>[])
                          : <Map<String, dynamic>>[];

                      return _VehicleTimelineCard(
                        vehicle: vehicle,
                        allocations: allocations,
                        timelineStart: _timelineStart,
                        timelineEnd: _timelineEnd,
                        statusColor: _statusColor,
                      );
                    }),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Helper Widgets
// ════════════════════════════════════════════════════════════════════════════

class _VehicleTimelineCard extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final List<Map<String, dynamic>> allocations;
  final DateTime timelineStart;
  final DateTime timelineEnd;
  final Function(String) statusColor;

  const _VehicleTimelineCard({
    required this.vehicle,
    required this.allocations,
    required this.timelineStart,
    required this.timelineEnd,
    required this.statusColor,
  });

  String get regNo =>
      (vehicle['registration_no'] ??
              vehicle['registrationNo'] ??
              vehicle['plate_no'] ??
              '-')
          .toString();
  String get make => (vehicle['make'] ?? 'Unknown').toString();
  String get model => (vehicle['model'] ?? '').toString();
  String get status => (vehicle['status'] ?? 'Available').toString();

  @override
  Widget build(BuildContext context) {
    final numDays = timelineEnd.difference(timelineStart).inDays + 1;
    final dayWidth = 20.0;
    final totalWidth = dayWidth * numDays;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E8EE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Vehicle Header ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE0E7FF), Color(0xFFF5F3FF)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: Color(0xFF6366F1),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        regNo,
                        style: const TextStyle(
                          color: Color(0xFF0F1F3D),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$make $model'.trim(),
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusBgColor(status),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: _getStatusTextColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${allocations.length} booking${allocations.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF475467),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // ── Timeline ──
          if (allocations.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE5E8EE),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date header
                        SizedBox(
                          width: totalWidth,
                          child: Row(
                            children: List.generate(numDays, (i) {
                              final date = timelineStart.add(Duration(days: i));
                              final isStart = i == 0;
                              final isEnd = i == numDays - 1;
                              return SizedBox(
                                width: dayWidth,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isStart || date.day == 1)
                                      Text(
                                        '${date.day}',
                                        style: const TextStyle(
                                          color: Color(0xFF667085),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      )
                                    else
                                      const SizedBox(height: 14),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Bookings
                        ...allocations.map((alloc) {
                          final start = alloc['startDate'] as DateTime;
                          final end = alloc['endDate'] as DateTime;
                          final startIdx = start
                              .difference(timelineStart)
                              .inDays;
                          final endIdx = end.difference(timelineStart).inDays;
                          final duration = (endIdx - startIdx).clamp(
                            0,
                            numDays,
                          );
                          final offset = startIdx.clamp(0, numDays - 1);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SizedBox(
                              width: totalWidth,
                              child: Stack(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      left: offset * dayWidth,
                                    ),
                                    child: Container(
                                      width: ((duration + 1) * dayWidth).clamp(
                                        dayWidth,
                                        totalWidth - offset * dayWidth,
                                      ),
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color:
                                            (statusColor(
                                                      alloc['status'] ??
                                                          'Assigned',
                                                    )
                                                    as Color)
                                                .withOpacity(0.2),
                                        border: Border.all(
                                          color:
                                              statusColor(
                                                    alloc['status'] ??
                                                        'Assigned',
                                                  )
                                                  as Color,
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: Center(
                                          child: Text(
                                            alloc['bookingRef'] ?? '-',
                                            style: TextStyle(
                                              color:
                                                  statusColor(
                                                        alloc['status'] ??
                                                            'Assigned',
                                                      )
                                                      as Color,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No bookings in this period',
                style: TextStyle(
                  color: const Color(0xFF667085).withOpacity(0.7),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'on lease':
        return const Color(0xFFDDF6E9);
      case 'available':
        return const Color(0xFFE0E7FF);
      case 'maintenance':
        return const Color(0xFFFFEDD5);
      default:
        return const Color(0xFFF0F2F5);
    }
  }

  Color _getStatusTextColor(String status) {
    switch (status.toLowerCase()) {
      case 'on lease':
        return const Color(0xFF065F46);
      case 'available':
        return const Color(0xFF3730A3);
      case 'maintenance':
        return const Color(0xFF92400E);
      default:
        return const Color(0xFF475467);
    }
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF475467),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
