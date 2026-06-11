import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/permission_gate.dart';
import 'dashboard_screen.dart';
import 'fuel_requisitions_screen.dart';
import 'long_term_leasing_screen.dart';
import 'lease_calendar_screen.dart';
import 'leads_screen.dart';
import 'invoices_screen.dart';
import 'drivers_screen.dart';
import 'payments_screen.dart';
import 'quotations_screen.dart';
import 'roles_permissions_screen.dart';
import 'settings_screen.dart';
import 'vehicle_availability_screen.dart';
import 'vehicles_screen.dart';
import 'job_cards_screen.dart';
import 'vehicle_checklist_screen.dart';
import 'login_screen.dart';

class _MenuItem {
  const _MenuItem({
    required this.title,
    required this.icon,
    required this.screenBuilder,
    this.permission,
  });

  final String title;
  final IconData icon;
  final Widget Function() screenBuilder;

  /// Required permission to view this entry. `null` means no gate.
  /// Mirrors the `permission` field on `menuGroups` in the web sidebar.
  final String? permission;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  late final Future<Map<String, dynamic>?> _profileFuture = _resolveProfile();

  Future<Map<String, dynamic>?> _resolveProfile() async {
    try {
      final me = await ApiService.refreshMeCache();
      if (me != null) return me;
    } catch (_) {
      // Fall back to locally cached profile if /me fails temporarily.
    }
    return ApiService.getCurrentUser();
  }

  // Permission keys mirror those defined in the web sidebar (see
  // `shererp/src/components/Sidebar.jsx`). Keep these in sync with the
  // backend's permission list so role-based gating is consistent across
  // clients.
  late final List<_MenuItem> _menuItems = [
    _MenuItem(
      title: 'Dashboard',
      icon: Icons.dashboard_outlined,
      screenBuilder: () => DashboardScreen(),
      permission: 'dashboard.view',
    ),
    _MenuItem(
      title: 'Leads',
      icon: Icons.assignment_outlined,
      screenBuilder: () => LeadsScreen(),
      permission: 'leads.view',
    ),
    _MenuItem(
      title: 'Quotations',
      icon: Icons.request_quote_outlined,
      screenBuilder: () => QuotationsScreen(),
      permission: 'quotations.view',
    ),
    _MenuItem(
      title: 'Proforma Invoice',
      icon: Icons.description_outlined,
      screenBuilder: () => InvoicesScreen(proforma: true),
      permission: 'proforma-invoices.view',
    ),
    _MenuItem(
      title: 'Invoices',
      icon: Icons.receipt_long_outlined,
      screenBuilder: () => InvoicesScreen(),
      permission: 'invoices.view',
    ),
    _MenuItem(
      title: 'Payments',
      icon: Icons.payment_outlined,
      screenBuilder: () => PaymentsScreen(),
      permission: 'invoice-payments.view',
    ),
    _MenuItem(
      title: 'Driver Movement',
      icon: Icons.person_outlined,
      screenBuilder: () => DriversScreen(),
      // Requires access to safari allocations / driver trip movement.
      permission: 'safari-allocations.view',
    ),
    _MenuItem(
      title: 'Long Term Leasing',
      icon: Icons.key_outlined,
      screenBuilder: () => LongTermLeasingScreen(),
      permission: 'vehicles.view',
    ),
    _MenuItem(
      title: 'Vehicles',
      icon: Icons.directions_car_outlined,
      screenBuilder: () => VehiclesScreen(),
      permission: 'vehicles.view',
    ),
    _MenuItem(
      title: 'Vehicle Availability',
      icon: Icons.calendar_month_outlined,
      screenBuilder: () => const VehicleAvailabilityScreen(),
      permission: 'vehicles.view',
    ),
    _MenuItem(
      title: 'Lease Calendar',
      icon: Icons.event_available_outlined,
      screenBuilder: () => const LeaseCalendarScreen(),
      permission: 'vehicles.view',
    ),
    _MenuItem(
      title: 'Fuel Requisitions',
      icon: Icons.local_gas_station_outlined,
      screenBuilder: () => FuelRequisitionsScreen(),
      permission: 'fuel-requisitions.view',
    ),
    _MenuItem(
      title: 'Job Cards',
      icon: Icons.checklist_outlined,
      screenBuilder: () => JobCardsScreen(),
      permission: 'job-cards.view',
    ),
    _MenuItem(
      title: 'Pre/Post Checklists',
      icon: Icons.fact_check_outlined,
      screenBuilder: () => VehicleChecklistScreen(),
      permission: 'job-cards.view',
    ),
    _MenuItem(
      title: 'Roles & Permissions',
      icon: Icons.shield_outlined,
      screenBuilder: () => const RolesPermissionsScreen(),
      // Keep this admin-only in the app shell.
      permission: 'users.delete',
    ),
    _MenuItem(
      title: 'Settings',
      icon: Icons.settings_outlined,
      screenBuilder: () => SettingsScreen(),
      permission: 'settings.view',
    ),
  ];

  int _navIndexForScreen(int screenIndex) {
    switch (screenIndex) {
      case 0:
        return 0; // Home
      case 8:
        return 1; // Fleet
      case 12:
        return 2; // Job Cards
      default:
        return 3; // More
    }
  }

  void _onBottomNavTap(int navIndex) {
    switch (navIndex) {
      case 0:
        setState(() => _selectedIndex = 0);
        break;
      case 1:
        setState(() => _selectedIndex = 8);
        break;
      case 2:
        setState(() => _selectedIndex = 12);
        break;
      case 3:
        _scaffoldKey.currentState?.openDrawer();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDashboard = _selectedIndex == 0;

    return Scaffold(
      key: _scaffoldKey,
      appBar: isDashboard
          ? null
          : AppBar(
              title: Text(_menuItems[_selectedIndex].title),
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    child: const Text(
                      'U',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
      drawer: _buildDrawer(context),
      body: PermissionGate(
        permission: _menuItems[_selectedIndex].permission,
        child: _menuItems[_selectedIndex].screenBuilder(),
      ),
      bottomNavigationBar: _bottomMenu(),
    );
  }

  Widget _bottomMenu() {
    final theme = Theme.of(context);
    final active = _navIndexForScreen(_selectedIndex);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Container(
          height: 82,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFE4E8EE), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              _menuNavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: active == 0,
                onTap: () => _onBottomNavTap(0),
                activeColor: theme.colorScheme.primary,
              ),
              _menuNavItem(
                icon: Icons.directions_car_outlined,
                label: 'Fleet',
                selected: active == 1,
                onTap: () => _onBottomNavTap(1),
                activeColor: theme.colorScheme.primary,
              ),
              _menuNavItem(
                icon: Icons.assignment_outlined,
                label: 'Job Cards',
                selected: active == 2,
                onTap: () => _onBottomNavTap(2),
                activeColor: theme.colorScheme.primary,
              ),
              _menuNavItem(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                selected: active == 3,
                onTap: () => _onBottomNavTap(3),
                activeColor: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuNavItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    const inactiveColor = Color(0xFF737E91);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 26,
                color: selected ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? activeColor : inactiveColor,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final isOperations = auth.roles.any((role) {
      final normalizedRole = role.trim().toLowerCase();
      return normalizedRole == 'operations' || normalizedRole == 'operator';
    });
    const operatorHiddenTitles = {
      'Fuel Requisitions',
      'Settings',
      'Proforma Invoice',
      'Long Term Leasing',
      'Quotations',
      'Roles & Permissions',
    };

    // Compute which menu entries the current user can see. We keep the
    // original indices so taps still map to the correct slot in
    // `_menuItems` (and the bottom-nav routing keeps working).
    final visibleIndices = <int>[];
    for (var i = 0; i < _menuItems.length; i++) {
      final item = _menuItems[i];
      if (isOperations && operatorHiddenTitles.contains(item.title)) {
        continue;
      }
      if (auth.hasPermission(item.permission)) {
        visibleIndices.add(i);
      }
    }

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.88,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            children: [
              const SizedBox(height: 4),
              _drawerBrandBlock(),
              const SizedBox(height: 14),
              _drawerProfileCard(),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: visibleIndices.length,
                  itemBuilder: (_, i) {
                    final idx = visibleIndices[i];
                    final item = _menuItems[idx];
                    final selected = idx == _selectedIndex;
                    return _drawerItem(
                      title: item.title,
                      icon: item.icon,
                      selected: selected,
                      onTap: () {
                        setState(() => _selectedIndex = idx);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await context.read<AuthProvider>().logout();
                    if (!context.mounted) return;
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD62E2E),
                    backgroundColor: const Color(0xFFFFF2F1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text(
                    'Logout',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 26),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'App Version 1.0.0',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerBrandBlock() {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF2),
            borderRadius: BorderRadius.circular(48),
            border: Border.all(color: const Color(0xFFF3E4C2)),
          ),
          child: const Center(
            child: Text(
              'SH\nER',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFC79D3C),
                fontWeight: FontWeight.w800,
                fontSize: 22,
                height: 0.95,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'SHER ERP',
          style: TextStyle(
            color: Color(0xFF1D2D4A),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Vehicle Leasing & Fleet Management',
          style: TextStyle(
            color: Color(0xFF7A879D),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _drawerProfileCard() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name =
            (user?['name'] ?? user?['full_name'] ?? user?['email'] ?? 'User')
                .toString();
        final email = (user?['email'] ?? '').toString();

        String initialsFromName(String value) {
          final parts = value
              .split(RegExp(r'\s+'))
              .where((p) => p.trim().isNotEmpty)
              .toList();
          if (parts.isEmpty) return 'U';
          if (parts.length == 1) {
            final s = parts.first.trim();
            return s.isEmpty
                ? 'U'
                : s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
          }
          return (parts[0][0] + parts[1][0]).toUpperCase();
        }

        final initials = initialsFromName(name);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F7F3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFC9A961),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1D2D4A),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email.isEmpty ? 'Signed in' : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7A879D),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF9A8650),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _drawerItem({
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFBF5E8) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                if (selected)
                  Container(
                    width: 4,
                    height: 30,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC9A961),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )
                else
                  const SizedBox(width: 14),
                Icon(icon, color: const Color(0xFF667085), size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF1D2D4A)
                          : const Color(0xFF344054),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF98A2B3),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
