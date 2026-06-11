import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LeaseCalendarScreen extends StatefulWidget {
  const LeaseCalendarScreen({super.key});

  @override
  State<LeaseCalendarScreen> createState() => _LeaseCalendarScreenState();
}

class _LeaseCalendarScreenState extends State<LeaseCalendarScreen> {
  bool _loading = true;
  String _error = '';

  Map<String, List<Map<String, dynamic>>> _calendarAllocations =
      <String, List<Map<String, dynamic>>>{};
  int _calendarMonth = DateTime.now().month;
  int _calendarYear = DateTime.now().year;
  String _selectedDateKey = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calendarMonth = now.month;
    _calendarYear = now.year;
    _selectedDateKey = _toDateKey(now);
    _load();
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
      final leadsRaw = await ApiService.fetchList(
        '/leads',
      ).catchError((_) => <dynamic>[]);
      final allocationsRaw = await ApiService.fetchList(
        '/safari-allocations',
      ).catchError((_) => <dynamic>[]);

      final calendarAllocations = _buildCalendarAllocations(
        allocationsRaw,
        vehiclesRaw,
        leadsRaw,
      );

      if (!mounted) return;
      setState(() {
        _calendarAllocations = calendarAllocations;
        final hasSelection =
            _selectedDateKey.isNotEmpty &&
            (_calendarAllocations[_selectedDateKey]?.isNotEmpty ?? false);
        if (!hasSelection) {
          _selectedDateKey =
              _firstAllocatedDateInCurrentMonth() ?? _selectedDateKey;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _previousMonth() {
    setState(() {
      if (_calendarMonth == 1) {
        _calendarMonth = 12;
        _calendarYear -= 1;
      } else {
        _calendarMonth -= 1;
      }
      _selectedDateKey =
          _firstAllocatedDateInCurrentMonth() ?? _selectedDateKey;
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
      _selectedDateKey =
          _firstAllocatedDateInCurrentMonth() ?? _selectedDateKey;
    });
  }

  List<int?> _calendarDays(int year, int month) {
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final days = <int?>[];

    for (int i = 0; i < firstDay.weekday % 7; i++) {
      days.add(null);
    }
    for (int i = 1; i <= lastDay.day; i++) {
      days.add(i);
    }
    return days;
  }

  String _toDateKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String? _firstAllocatedDateInCurrentMonth() {
    final prefix =
        '${_calendarYear.toString().padLeft(4, '0')}-${_calendarMonth.toString().padLeft(2, '0')}-';
    final dates =
        _calendarAllocations.keys
            .where((key) => key.startsWith(prefix))
            .toList()
          ..sort();
    if (dates.isEmpty) return null;
    return dates.first;
  }

  String _monthLabel(int year, int month) {
    return '${_monthLong(month)} $year';
  }

  String _monthShort(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }

  String _monthLong(int month) {
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
    return names[(month - 1).clamp(0, 11)];
  }

  String _formatDisplayDate(String dateKey) {
    final parsed = DateTime.tryParse(dateKey);
    if (parsed == null) return dateKey;
    return '${_monthLong(parsed.month)} ${parsed.day}, ${parsed.year}';
  }

  Color _statusDotColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return const Color(0xFF34D399);
      case 'completed':
        return const Color(0xFF818CF8);
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFFB7185);
      default:
        return const Color(0xFF60A5FA);
    }
  }

  ({Color bg, Color border, Color text}) _statusBadgeColors(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return (
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFF6EE7B7),
          text: const Color(0xFF065F46),
        );
      case 'completed':
        return (
          bg: const Color(0xFFEDE9FE),
          border: const Color(0xFFC4B5FD),
          text: const Color(0xFF4C1D95),
        );
      case 'cancelled':
      case 'canceled':
        return (
          bg: const Color(0xFFFFF1F2),
          border: const Color(0xFFFDA4AF),
          text: const Color(0xFF9F1239),
        );
      default:
        return (
          bg: const Color(0xFFEFF6FF),
          border: const Color(0xFF93C5FD),
          text: const Color(0xFF1E40AF),
        );
    }
  }

  Map<String, List<Map<String, dynamic>>> _buildCalendarAllocations(
    List<dynamic> allocations,
    List<dynamic> vehicles,
    List<dynamic> leads,
  ) {
    final byDate = <String, List<Map<String, dynamic>>>{};

    final vehicleById = <String, Map>{
      for (final item in vehicles)
        if (item is Map) (item['id'] ?? '').toString(): item,
    };

    final leadById = <String, Map>{
      for (final item in leads)
        if (item is Map) (item['id'] ?? '').toString(): item,
    };

    for (final row in allocations) {
      if (row is! Map) continue;

      final leadId = (row['lead_id'] ?? row['leadId'] ?? '').toString();
      final lead = (row['lead'] is Map) ? row['lead'] as Map : leadById[leadId];
      if (lead == null) continue;

      final start = DateTime.tryParse(
        (lead['start_date'] ?? lead['startDate'] ?? '').toString(),
      );
      final end = DateTime.tryParse(
        (lead['end_date'] ?? lead['endDate'] ?? '').toString(),
      );
      if (start == null || end == null) continue;

      final vehicleId = (row['vehicle_id'] ?? row['vehicleId'] ?? '')
          .toString();
      final nestedVehicle = row['vehicle'];
      final vehicle = nestedVehicle is Map
          ? nestedVehicle
          : vehicleById[vehicleId];

      final nestedDriver = row['driver'];
      final driverName = nestedDriver is Map
          ? (nestedDriver['name'] ?? 'Unknown').toString()
          : 'Unknown';

      for (
        DateTime day = DateTime(start.year, start.month, start.day);
        !day.isAfter(DateTime(end.year, end.month, end.day));
        day = day.add(const Duration(days: 1))
      ) {
        final key = _toDateKey(day);
        final dayList = byDate.putIfAbsent(key, () => <Map<String, dynamic>>[]);
        dayList.add({
          'bookingRef': lead['booking_ref'] ?? lead['bookingRef'] ?? '-',
          'registrationNo':
              vehicle?['registration_no'] ??
              vehicle?['registrationNo'] ??
              vehicle?['plate_no'] ??
              vehicle?['plateNo'] ??
              'Unknown',
          'vehicleMake':
              vehicle?['make'] ??
              vehicle?['vehicle_make'] ??
              vehicle?['brand'] ??
              '',
          'vehicleModel': vehicle?['model'] ?? vehicle?['vehicle_model'] ?? '',
          'driverName': driverName,
          'status': row['status'] ?? 'Assigned',
          'startDate': _toDateKey(start),
          'endDate': _toDateKey(end),
          'routeParks':
              lead['route'] ??
              lead['route_parks'] ??
              lead['routeParks'] ??
              lead['destination'] ??
              '',
        });
      }
    }

    return byDate;
  }

  Widget _allocationDetailCard(Map<String, dynamic> alloc) {
    final bookingRef = (alloc['bookingRef'] ?? '-').toString();
    final status = (alloc['status'] ?? 'Assigned').toString();
    final reg = (alloc['registrationNo'] ?? 'Unknown').toString();
    final driver = (alloc['driverName'] ?? 'Unknown').toString();
    final route = (alloc['routeParks'] ?? '').toString();
    final make = (alloc['vehicleMake'] ?? '').toString();
    final model = (alloc['vehicleModel'] ?? '').toString();
    final startDate = (alloc['startDate'] ?? '').toString();
    final endDate = (alloc['endDate'] ?? '').toString();
    final badge = _statusBadgeColors(status);
    final vehicleLabel = [make, model].where((s) => s.isNotEmpty).join(' ');

    String dateRange = '';
    if (startDate.isNotEmpty && endDate.isNotEmpty) {
      final s = DateTime.tryParse(startDate);
      final e = DateTime.tryParse(endDate);
      if (s != null && e != null) {
        dateRange =
            '${_monthShort(s.month)} ${s.day} – ${_monthShort(e.month)} ${e.day}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E8EE)),
        color: const Color(0xFFFCFDFF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: Color(0xFFE5E8EE))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.tour_outlined,
                  color: Color(0xFFB88910),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bookingRef,
                    style: const TextStyle(
                      color: Color(0xFF0F1F3D),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badge.bg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badge.border),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: badge.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECF7FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.directions_car_outlined,
                        color: Color(0xFF0E82C2),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reg,
                            style: const TextStyle(
                              color: Color(0xFF101828),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (vehicleLabel.isNotEmpty)
                            Text(
                              vehicleLabel,
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (dateRange.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          dateRange,
                          style: const TextStyle(
                            color: Color(0xFF475467),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFFAF5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFF0E9F6E),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver,
                            style: const TextStyle(
                              color: Color(0xFF101828),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (route.isNotEmpty)
                            Text(
                              'Route: $route',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedAllocations =
        _calendarAllocations[_selectedDateKey] ?? <Map<String, dynamic>>[];
    final days = _calendarDays(_calendarYear, _calendarMonth);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Lease Calendar',
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load lease calendar\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E8EE)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5E2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.event_available_outlined,
                                color: Color(0xFFB88910),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Lease Calendar',
                                    style: TextStyle(
                                      color: Color(0xFF0F1F3D),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Safari vehicle and driver assignments',
                                    style: TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: _previousMonth,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE5E8EE),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.chevron_left_rounded,
                                  size: 18,
                                  color: Color(0xFF475467),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              child: Text(
                                _monthLabel(_calendarYear, _calendarMonth),
                                style: const TextStyle(
                                  color: Color(0xFF344054),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: _nextMonth,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE5E8EE),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: Color(0xFF475467),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: const [
                            Expanded(child: _WeekdayLabel('S')),
                            Expanded(child: _WeekdayLabel('M')),
                            Expanded(child: _WeekdayLabel('T')),
                            Expanded(child: _WeekdayLabel('W')),
                            Expanded(child: _WeekdayLabel('T')),
                            Expanded(child: _WeekdayLabel('F')),
                            Expanded(child: _WeekdayLabel('S')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: days.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: 4,
                                crossAxisSpacing: 4,
                                childAspectRatio: 0.85,
                              ),
                          itemBuilder: (context, index) {
                            final day = days[index];
                            if (day == null) return const SizedBox.shrink();

                            final dateKey = _toDateKey(
                              DateTime(_calendarYear, _calendarMonth, day),
                            );
                            final dayAllocs =
                                _calendarAllocations[dateKey] ??
                                <Map<String, dynamic>>[];
                            final isSelected = _selectedDateKey == dateKey;
                            final isToday =
                                _toDateKey(DateTime.now()) == dateKey;
                            final hasBookings = dayAllocs.isNotEmpty;

                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedDateKey = dateKey),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF1D4E89)
                                      : hasBookings
                                      ? const Color(0xFFEFFBF6)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF1D4E89)
                                        : isToday
                                        ? const Color(0xFFDDB15C)
                                        : hasBookings
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFE5E8EE),
                                    width: isToday && !isSelected ? 1.5 : 1,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 4,
                                ),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$day',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : isToday
                                            ? const Color(0xFFB88910)
                                            : const Color(0xFF334155),
                                        fontSize: 12,
                                        fontWeight: isSelected || isToday
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        height: 1,
                                      ),
                                    ),
                                    if (hasBookings)
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          ...List.generate(
                                            dayAllocs.length.clamp(0, 3),
                                            (i) => Container(
                                              width: 5,
                                              height: 5,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: isSelected
                                                    ? Colors.white.withValues(
                                                        alpha: 0.85,
                                                      )
                                                    : _statusDotColor(
                                                        (dayAllocs[i]['status'] ??
                                                                '')
                                                            .toString(),
                                                      ),
                                              ),
                                            ),
                                          ),
                                          if (dayAllocs.length > 3)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 1,
                                              ),
                                              child: Text(
                                                '+',
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : const Color(0xFF667085),
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1,
                                                ),
                                              ),
                                            ),
                                        ],
                                      )
                                    else
                                      const SizedBox(height: 5),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: const [
                            _CalLegend(
                              color: Color(0xFF60A5FA),
                              label: 'Assigned',
                            ),
                            _CalLegend(
                              color: Color(0xFF34D399),
                              label: 'Confirmed',
                            ),
                            _CalLegend(
                              color: Color(0xFF818CF8),
                              label: 'Completed',
                            ),
                            _CalLegend(
                              color: Color(0xFFFB7185),
                              label: 'Cancelled',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E8EE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedDateKey.isEmpty
                                    ? 'Select a date'
                                    : _formatDisplayDate(_selectedDateKey),
                                style: const TextStyle(
                                  color: Color(0xFF0F1F3D),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F2F5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${selectedAllocations.length} allocation${selectedAllocations.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  color: Color(0xFF475467),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (selectedAllocations.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.event_available_outlined,
                                    color: Color(0xFFCBD5E1),
                                    size: 36,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'No bookings on this date',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Tap a highlighted date to view allocations',
                                    style: TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Column(
                            children: selectedAllocations
                                .map(_allocationDetailCard)
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CalLegend extends StatelessWidget {
  const _CalLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF667085),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
