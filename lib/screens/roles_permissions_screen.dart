import 'package:flutter/material.dart';
import '../services/api_service.dart';

const _kSherGold = Color(0xFFC9A961);

/// Read-only matrix that shows which permissions are assigned to which system
/// roles. Mirrors the web client's `RolesPermissions.jsx` page.
class RolesPermissionsScreen extends StatefulWidget {
  const RolesPermissionsScreen({super.key});

  @override
  State<RolesPermissionsScreen> createState() => _RolesPermissionsScreenState();
}

class _Role {
  _Role({required this.name, required this.permissions});

  final String name;
  final Set<String> permissions;
}

class _RolesPermissionsScreenState extends State<RolesPermissionsScreen> {
  bool _loading = true;
  String? _error;

  List<_Role> _roles = const <_Role>[];
  List<String> _allPermissions = const <String>[];

  static const Map<String, _RoleStyle> _roleStyles = {
    'Admin': _RoleStyle(Color(0xFFEFF6FF), Color(0xFF2563EB)),
    'Operations': _RoleStyle(Color(0xFFF5F3FF), Color(0xFF7C3AED)),
    'Finance': _RoleStyle(Color(0xFFFFFBEB), Color(0xFFD97706)),
    'Driver': _RoleStyle(Color(0xFFECFDF5), Color(0xFF059669)),
    'Viewer': _RoleStyle(Color(0xFFECFEFF), Color(0xFF0891B2)),
  };
  static const _RoleStyle _defaultStyle = _RoleStyle(
    Color(0xFFF1F5F9),
    Color(0xFF475569),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await ApiService.fetchRolesPermissions();

      final rolesRaw = payload['roles'];
      final permsRaw = payload['permissions'];

      final roles = <_Role>[];
      if (rolesRaw is List) {
        for (final r in rolesRaw) {
          if (r is Map) {
            final name = (r['name'] ?? '').toString();
            final perms = r['permissions'];
            final permSet = <String>{};
            if (perms is List) {
              for (final p in perms) {
                permSet.add(p.toString());
              }
            }
            if (name.isNotEmpty) {
              roles.add(_Role(name: name, permissions: permSet));
            }
          }
        }
      }

      final allPerms = <String>[];
      if (permsRaw is List) {
        for (final p in permsRaw) {
          allPerms.add(p.toString());
        }
      }

      if (!mounted) return;
      setState(() {
        _roles = roles;
        _allPermissions = allPerms;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load roles and permissions.';
        _loading = false;
      });
    }
  }

  Map<String, List<String>> _groupPermissions(List<String> perms) {
    final out = <String, List<String>>{};
    for (final p in perms) {
      final module = p.split('.').first;
      out.putIfAbsent(module, () => <String>[]).add(p);
    }
    return out;
  }

  String _formatModule(String module) {
    final cleaned = module.replaceAll('_', ' ');
    return cleaned
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  String _formatAction(String perm) {
    final parts = perm.split('.');
    if (parts.length < 2) return 'Access';
    final action = parts
        .sublist(1)
        .join(' ')
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim();
    if (action.isEmpty) return 'Access';
    return action
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  String _formatLabel(String perm) {
    final parts = perm.split('.');
    return '${_formatModule(parts.first)} - ${_formatAction(perm)}';
  }

  _RoleStyle _styleFor(String role) => _roleStyles[role] ?? _defaultStyle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Roles & Permissions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: AnimatedRotation(
              turns: _loading ? 1 : 0,
              duration: const Duration(seconds: 1),
              child: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _kSherGold,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              if (_error != null) ...[
                _errorBanner(_error!),
                const SizedBox(height: 16),
              ],
              _buildStats(),
              const SizedBox(height: 16),
              if (!_loading && _roles.isNotEmpty) ...[
                _buildRoleBadges(),
                const SizedBox(height: 16),
              ],
              _buildMatrixCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Roles & Permissions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'View which permissions are assigned to each system role.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
      ],
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final groups = _groupPermissions(_allPermissions);
    final adminPerms = _roles
        .firstWhere(
          (r) => r.name == 'Admin',
          orElse: () => _Role(name: '', permissions: <String>{}),
        )
        .permissions;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _statCard('Total Roles', '${_roles.length}', const Color(0xFF1E293B)),
        _statCard(
          'Total Permissions',
          '${_allPermissions.length}',
          const Color(0xFFD97706),
        ),
        _statCard(
          'Permission Groups',
          '${groups.length}',
          const Color(0xFF2563EB),
        ),
        _statCard(
          'Admin Permissions',
          adminPerms.isEmpty ? '—' : '${adminPerms.length}',
          const Color(0xFF059669),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadges() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SYSTEM ROLES',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _roles.map((role) {
              final style = _styleFor(role.name);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: style.background,
                  border: Border.all(color: style.foreground.withOpacity(0.25)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: style.foreground,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      role.name,
                      style: TextStyle(
                        color: style.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${role.permissions.length})',
                      style: TextStyle(
                        color: style.foreground.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMatrixCard() {
    if (_loading) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: _kSherGold),
        ),
      );
    }

    if (_roles.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Text(
            'No data available.',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    final groups = _groupPermissions(_allPermissions);
    final groupNames = groups.keys.toList()..sort();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFFFFBF2)),
          columnSpacing: 18,
          columns: [
            const DataColumn(
              label: Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'PERMISSION',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            ..._roles.map((role) {
              final style = _styleFor(role.name);
              return DataColumn(
                label: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: style.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: style.foreground.withOpacity(0.25),
                    ),
                  ),
                  child: Text(
                    role.name,
                    style: TextStyle(
                      color: style.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }),
          ],
          rows: [
            for (final module in groupNames) ...[
              DataRow(
                color: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                cells: [
                  DataCell(
                    Text(
                      _formatModule(module).toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  for (var _ in _roles) const DataCell(SizedBox()),
                ],
              ),
              ...groups[module]!.map(
                (perm) => DataRow(
                  cells: [
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatLabel(perm),
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            perm,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final role in _roles)
                      DataCell(
                        Center(
                          child: role.permissions.contains(perm)
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF10B981),
                                  size: 20,
                                )
                              : const Icon(
                                  Icons.cancel_outlined,
                                  color: Color(0xFFCBD5E1),
                                  size: 20,
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleStyle {
  const _RoleStyle(this.background, this.foreground);

  final Color background;
  final Color foreground;
}
