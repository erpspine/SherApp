import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import 'long_term_leasing_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String _error = '';

  int _totalFleet = 0;
  int _activeLeases = 0;
  int _openQuotations = 0;
  int _maintenanceCount = 0;
  double _monthlyRevenue = 0;

  List<dynamic> _recentQuotations = <dynamic>[];
  List<Map<String, dynamic>> _revenueSeries = <Map<String, dynamic>>[];
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
      final dashboardRaw = await ApiService.get(
        '/dashboard',
      ).catchError((_) => <String, dynamic>{});
      final vehiclesRaw = await ApiService.fetchList(
        '/vehicles',
      ).catchError((_) => <dynamic>[]);
      final leadsRaw = await ApiService.fetchList(
        '/leads',
      ).catchError((_) => <dynamic>[]);
      final quotationsRaw = await ApiService.fetchList(
        '/quotations',
      ).catchError((_) => <dynamic>[]);
      final proformaRaw = await ApiService.fetchList(
        '/proforma-invoices',
      ).catchError((_) => <dynamic>[]);
      final allocationsRaw = await ApiService.fetchList(
        '/safari-allocations',
      ).catchError((_) => <dynamic>[]);

      final dashboardData = dashboardRaw is Map
          ? (dashboardRaw['data'] ?? dashboardRaw['dashboard'] ?? dashboardRaw)
          : <String, dynamic>{};

      final vehicles = vehiclesRaw;
      final leads = leadsRaw;
      final quotations = quotationsRaw;
      final proformas = proformaRaw;
      final allocations = allocationsRaw;

      final now = DateTime.now();
      final currentMonthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      final monthlyRevenue = proformas.fold<double>(0, (sum, row) {
        final dateStr =
            (row['quoteDate'] ?? row['quote_date'] ?? row['created_at'] ?? '')
                .toString();
        final amount =
            double.tryParse(
              (row['total'] ?? row['total_amount'] ?? 0).toString(),
            ) ??
            0;
        final dt = DateTime.tryParse(dateStr);
        if (dt == null) return sum;
        final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        return key == currentMonthKey ? sum + amount : sum;
      });

      final stats = dashboardData is Map && dashboardData['stats'] is Map
          ? dashboardData['stats'] as Map
          : <String, dynamic>{};
      final hasDashboardMonthlyRevenue = stats.containsKey('monthlyRevenue');
      final dashboardMonthlyRevenue =
          double.tryParse((stats['monthlyRevenue'] ?? 0).toString()) ?? 0;

      final revenueData = _buildRevenueSeries(proformas, months: 6);
      final allocationsByDate = _buildCalendarAllocations(
        allocations,
        vehicles,
        leads,
      );

      final leased = vehicles
          .where(
            (v) => (v['status'] ?? '').toString().toLowerCase() == 'on lease',
          )
          .length;
      final maintenance = vehicles
          .where(
            (v) =>
                (v['status'] ?? '').toString().toLowerCase() == 'maintenance',
          )
          .length;

      if (!mounted) return;
      setState(() {
        _totalFleet = (dashboardData is Map && dashboardData['stats'] is Map)
            ? int.tryParse(
                    (dashboardData['stats']['totalFleet'] ?? vehicles.length)
                        .toString(),
                  ) ??
                  vehicles.length
            : vehicles.length;

        _activeLeases = (dashboardData is Map && dashboardData['stats'] is Map)
            ? int.tryParse(
                    (dashboardData['stats']['activeLeases'] ?? leased)
                        .toString(),
                  ) ??
                  leased
            : leased;

        _openQuotations = quotations.where((q) {
          final s = (q['status'] ?? '').toString().toLowerCase();
          return s == 'draft' || s == 'sent' || s == 'approved';
        }).length;

        _monthlyRevenue = hasDashboardMonthlyRevenue
            ? dashboardMonthlyRevenue
            : monthlyRevenue;
        _maintenanceCount = maintenance;
        _recentQuotations = quotations.take(3).toList();
        _revenueSeries = revenueData;
        _calendarAllocations = allocationsByDate;

        final selectedHasItems =
            _selectedDateKey.isNotEmpty &&
            (_calendarAllocations[_selectedDateKey]?.isNotEmpty ?? false);
        if (!selectedHasItems) {
          _selectedDateKey =
              _firstAllocatedDateInCurrentMonth() ?? _selectedDateKey;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load dashboard\n$_error',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: Theme.of(context).colorScheme.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        children: [
          _header(),
          const SizedBox(height: 16),
          _searchBar(),
          const SizedBox(height: 16),
          _operationsSnapshot(),
          const SizedBox(height: 14),
          _kpiGrid(),
          const SizedBox(height: 18),
          _revenueChartCard(),
          const SizedBox(height: 18),
          _allocationCalendarCard(),
          const SizedBox(height: 18),
          _sectionTitle('Quick Actions'),
          const SizedBox(height: 12),
          _quickActions(),
          const SizedBox(height: 18),
          _recentActivityHeader(),
          const SizedBox(height: 10),
          _activityCard(),
        ],
      ),
    );
  }

  double _fontScale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width <= 360) return 0.84;
    if (width <= 390) return 0.92;
    return 1.0;
  }

  Widget _header() {
    final theme = Theme.of(context);
    final scale = _fontScale(context);

    return SafeArea(
      bottom: false,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good Morning,',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Duncan Osur 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 34 * scale,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sher Vehicle Leasing',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () {},
                icon: Icon(
                  Icons.notifications_none_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 27,
                ),
              ),
              Positioned(
                top: 6,
                right: 7,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5484D),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Center(
                    child: Text(
                      '3',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(kGoldColor),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'DO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8EC), width: 1.1),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Search vehicle, client, quote...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            Icons.tune_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            size: 23,
          ),
        ],
      ),
    );
  }

  Widget _operationsSnapshot() {
    final theme = Theme.of(context);
    final scale = _fontScale(context);
    final utilization = _totalFleet == 0
        ? 0
        : ((_activeLeases / _totalFleet) * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1DFC1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.query_stats_rounded,
                  color: Color(0xFFBD7D00),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'OPERATIONS SNAPSHOT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(kGoldColor),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    fontSize: 20 * scale,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE4E7EC)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  minimumSize: const Size(88, 38),
                  foregroundColor: theme.colorScheme.onSurface,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View All', style: TextStyle(fontSize: 14 * scale)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18 * scale),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _snapshotMetric(
                  icon: Icons.donut_large_rounded,
                  iconBg: const Color(0xFFE6F8F3),
                  iconColor: const Color(0xFF0D8F73),
                  label: 'Fleet Utilization',
                  value: '$utilization%',
                  valueColor: const Color(0xFF0D8F73),
                ),
              ),
              _divider(),
              Expanded(
                child: _snapshotMetric(
                  icon: Icons.attach_money_rounded,
                  iconBg: const Color(0xFFEAF9E2),
                  iconColor: const Color(0xFF3A9A1F),
                  label: 'Monthly Revenue',
                  value: _money(_monthlyRevenue),
                  valueColor: const Color(0xFF0F7A57),
                ),
              ),
              _divider(),
              Expanded(
                child: _snapshotMetric(
                  icon: Icons.description_outlined,
                  iconBg: const Color(0xFFFFF0E5),
                  iconColor: const Color(0xFFD96913),
                  label: 'Open Quotations',
                  value: '$_openQuotations',
                  valueColor: const Color(0xFFD96913),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _snapshotMetric({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    final theme = Theme.of(context);
    final scale = _fontScale(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
              fontSize: 14 * scale,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w800,
                fontSize: 22 * scale,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.08,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
      children: [
        _kpiCard(
          title: 'Total Fleet',
          value: '$_totalFleet',
          subtitle: 'Vehicles Registered',
          icon: Icons.directions_car_outlined,
          tint: const Color(0xFFFFF7E8),
          iconColor: const Color(0xFFBE7A00),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(topLeft: Radius.circular(18)),
          ),
        ),
        _kpiCard(
          title: 'Active Leases',
          value: '$_activeLeases',
          subtitle: 'Currently on lease',
          icon: Icons.assignment_turned_in_outlined,
          tint: const Color(0xFFEFFAF5),
          iconColor: const Color(0xFF0E8E64),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(topRight: Radius.circular(18)),
          ),
        ),
        _kpiCard(
          title: 'Open Quotations',
          value: '$_openQuotations',
          subtitle: 'Draft/Sent/Approved',
          icon: Icons.description_outlined,
          tint: const Color(0xFFFFF2EC),
          iconColor: const Color(0xFFD86A14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(18)),
          ),
        ),
        _kpiCard(
          title: 'This Month Revenue',
          value: _money(_monthlyRevenue),
          subtitle: 'This month',
          icon: Icons.attach_money_rounded,
          tint: const Color(0xFFEAF7FF),
          iconColor: const Color(0xFF1284C4),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(18)),
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color tint,
    required Color iconColor,
    required ShapeBorder shape,
  }) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: shape,
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E8EE), width: 1),
          borderRadius: (shape as RoundedRectangleBorder).borderRadius,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 0.95,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final theme = Theme.of(context);

    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: theme.colorScheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _revenueChartCard() {
    final maxRevenue = _revenueSeries.fold<double>(0, (max, item) {
      final value = double.tryParse((item['revenue'] ?? 0).toString()) ?? 0;
      return value > max ? value : max;
    });
    final yMax = maxRevenue <= 0 ? 1.0 : maxRevenue * 1.2;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E8EE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PI Revenue',
            style: TextStyle(
              color: Color(0xFF0F1F3D),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Last 6 months in USD',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: yMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yMax / 4,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFFE7EBF1), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(enabled: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: yMax / 4,
                      getTitlesWidget: (value, _) {
                        final kValue = (value / 1000).round();
                        return Text(
                          '${kValue}K',
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _revenueSeries.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            (_revenueSeries[idx]['name'] ?? '').toString(),
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    barWidth: 3,
                    color: const Color(0xFF0F766E),
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0F766E).withOpacity(0.26),
                          const Color(0xFFC9A236).withOpacity(0.04),
                        ],
                      ),
                    ),
                    spots: List<FlSpot>.generate(_revenueSeries.length, (i) {
                      final value =
                          double.tryParse(
                            (_revenueSeries[i]['revenue'] ?? 0).toString(),
                          ) ??
                          0;
                      return FlSpot(i.toDouble(), value);
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _allocationCalendarCard() {
    final days = _calendarDays(_calendarYear, _calendarMonth);
    final selectedAllocations =
        _calendarAllocations[_selectedDateKey] ?? <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E8EE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
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
                  Icons.calendar_month_outlined,
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
                      'Vehicle Allocations',
                      style: TextStyle(
                        color: Color(0xFF0F1F3D),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Safari vehicle & driver assignments',
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
                    border: Border.all(color: const Color(0xFFE5E8EE)),
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
                padding: const EdgeInsets.symmetric(horizontal: 7),
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
                    border: Border.all(color: const Color(0xFFE5E8EE)),
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
          // ── Weekday labels ───────────────────────────────────────
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
          // ── Day grid — dots only, no overflow ────────────────────
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                  _calendarAllocations[dateKey] ?? <Map<String, dynamic>>[];
              final isSelected = _selectedDateKey == dateKey;
              final isToday = _toDateKey(DateTime.now()) == dateKey;
              final hasBookings = dayAllocs.isNotEmpty;

              return GestureDetector(
                onTap: () => setState(() => _selectedDateKey = dateKey),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ...List.generate(
                              dayAllocs.length.clamp(0, 3),
                              (i) => Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.white.withOpacity(0.85)
                                      : _statusDotColor(
                                          (dayAllocs[i]['status'] ?? '')
                                              .toString(),
                                        ),
                                ),
                              ),
                            ),
                            if (dayAllocs.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(left: 1),
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
          // ── Legend ───────────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: const [
              _CalLegend(color: Color(0xFF60A5FA), label: 'Assigned'),
              _CalLegend(color: Color(0xFF34D399), label: 'Confirmed'),
              _CalLegend(color: Color(0xFF818CF8), label: 'Completed'),
              _CalLegend(color: Color(0xFFFB7185), label: 'Cancelled'),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFEEF0F4)),
          ),
          // ── Details panel ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDateKey.isEmpty
                      ? 'Select a date'
                      : _formatDisplayDate(_selectedDateKey),
                  style: const TextStyle(
                    color: Color(0xFF0F1F3D),
                    fontSize: 15,
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
          const SizedBox(height: 10),
          if (selectedAllocations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Column(
                  children: const [
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
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: selectedAllocations.map(_allocationDetailCard).toList(),
            ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: _quickActionItem(
              label: 'Add Vehicle',
              icon: Icons.add_circle_outline,
              iconColor: const Color(0xFFDEA100),
              tint: const Color(0xFFFFF8E9),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _quickActionItem(
              label: 'New Quote',
              icon: Icons.note_add_outlined,
              iconColor: const Color(0xFF0F9D67),
              tint: const Color(0xFFEFFAF5),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _quickActionItem(
              label: 'New Job Card',
              icon: Icons.assignment_add,
              iconColor: const Color(0xFF0E82C2),
              tint: const Color(0xFFECF7FF),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _quickActionItem(
              label: 'Safari Allocation',
              icon: Icons.groups_outlined,
              iconColor: const Color(0xFF6C47C5),
              tint: const Color(0xFFF4F1FF),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _quickActionItem(
              label: 'Long Term Lease',
              icon: Icons.key_outlined,
              iconColor: const Color(0xFFB88910),
              tint: const Color(0xFFFFF5E2),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LongTermLeasingScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionItem({
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color tint,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 126,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E8EE), width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentActivityHeader() {
    final theme = Theme.of(context);

    return Row(
      children: [
        _sectionTitle('Recent Activity'),
        const Spacer(),
        TextButton.icon(
          onPressed: () {},
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          label: const Text(
            'View All',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _activityCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E8EE), width: 1),
      ),
      child: Column(
        children: [
          _activityTile(
            icon: Icons.note_alt_outlined,
            iconBg: const Color(0xFFEFFAF5),
            iconColor: const Color(0xFF109B67),
            title: _recentQuotations.isNotEmpty
                ? 'New quotation sent'
                : 'Quotation draft created',
            subtitle: _recentQuotations.isNotEmpty
                ? _recentQuoteSubtitle(_recentQuotations.first)
                : 'No new quote activity found yet',
            time: '2h ago',
            indicatorColor: const Color(0xFF11A86A),
          ),
          _divider(horizontal: true),
          _activityTile(
            icon: Icons.directions_car_outlined,
            iconBg: const Color(0xFFECF7FF),
            iconColor: const Color(0xFF1F89CD),
            title: 'Vehicle added',
            subtitle: '$_totalFleet vehicles currently in fleet',
            time: '5h ago',
            indicatorColor: const Color(0xFF1791DA),
          ),
          _divider(horizontal: true),
          _activityTile(
            icon: Icons.build_outlined,
            iconBg: const Color(0xFFFFF2EA),
            iconColor: const Color(0xFFDF6D1B),
            title: 'Service due soon',
            subtitle: _maintenanceCount == 0
                ? 'No vehicles currently under maintenance'
                : '$_maintenanceCount vehicles are under maintenance',
            time: '1d ago',
            indicatorColor: const Color(0xFFE67E22),
          ),
        ],
      ),
    );
  }

  Widget _activityTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String time,
    required Color indicatorColor,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                time,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider({bool horizontal = false}) {
    if (horizontal) {
      return const Divider(height: 1, thickness: 1, color: Color(0xFFE9ECF1));
    }

    return Container(
      width: 1,
      height: 78,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: const Color(0xFFE9ECF1),
    );
  }

  String _money(double value) {
    final n = value
        .toStringAsFixed(2)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return 'USD $n';
  }

  List<Map<String, dynamic>> _buildRevenueSeries(
    List<dynamic> proformas, {
    int months = 6,
  }) {
    final now = DateTime.now();
    final buckets = <Map<String, dynamic>>[];
    final bucketMap = <String, Map<String, dynamic>>{};

    for (int i = months - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final label = _monthShort(d.month);
      final bucket = <String, dynamic>{
        'key': key,
        'name': label,
        'revenue': 0.0,
      };
      buckets.add(bucket);
      bucketMap[key] = bucket;
    }

    for (final row in proformas) {
      if (row is! Map) continue;
      final dateStr =
          (row['quoteDate'] ?? row['quote_date'] ?? row['created_at'] ?? '')
              .toString();
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) continue;

      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      final bucket = bucketMap[key];
      if (bucket == null) continue;

      final amount =
          double.tryParse(
            (row['total'] ?? row['total_amount'] ?? 0).toString(),
          ) ??
          0;
      bucket['revenue'] = (bucket['revenue'] as double) + amount;
    }

    return buckets;
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
      default: // assigned
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
      default: // assigned
        return (
          bg: const Color(0xFFEFF6FF),
          border: const Color(0xFF93C5FD),
          text: const Color(0xFF1E40AF),
        );
    }
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
          // card header
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
          // card body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Vehicle row
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
                // Driver row
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

  String _formatDisplayDate(String dateKey) {
    final dt = DateTime.tryParse(dateKey);
    if (dt == null) return dateKey;
    return '${_monthLong(dt.month)} ${dt.day}, ${dt.year}';
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

  String _toDateKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
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

  String _recentQuoteSubtitle(dynamic row) {
    if (row is! Map) {
      return 'Recent quotation activity available';
    }

    final id =
        row['quote_no'] ??
        row['quoteNo'] ??
        row['quotation_number'] ??
        row['id'] ??
        '-';
    final clientField = row['client'];

    String client = 'Client';
    final clientName = row['client_name']?.toString().trim();
    if (clientName != null && clientName.isNotEmpty) {
      client = clientName;
    } else if (clientField is Map) {
      final nested =
          clientField['name'] ??
          clientField['client_name'] ??
          clientField['full_name'];
      final nestedName = nested?.toString().trim();
      if (nestedName != null && nestedName.isNotEmpty) {
        client = nestedName;
      }
    } else if (clientField != null) {
      final raw = clientField.toString().trim();
      if (raw.isNotEmpty) {
        client = raw;
      }
    }

    return 'Quote #$id sent to $client';
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String text;

  const _WeekdayLabel(this.text);

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

class _CalLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _CalLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
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
