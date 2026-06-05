import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import 'driver_trips_screen.dart';

class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});

  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  Map<String, dynamic>? _currentUser;
  bool _loading = true;
  String? _error;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _openMyMovementLog();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openMyMovementLog() async {
    setState(() => _loading = true);
    try {
      final user = await ApiService.getCurrentUser();
      if (!mounted) return;

      if (user == null) {
        setState(() {
          _loading = false;
          _error =
              'Unable to resolve logged-in driver profile. Please log in again.';
        });
        return;
      }

      setState(() {
        _currentUser = user;
        _loading = false;
        _error = null;
      });

      if (!_opened) {
        _opened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _currentUser == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DriverTripsScreen(
                driver: _currentUser!,
                useCurrentAssignments: true,
              ),
            ),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to open movement log: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final driverName =
        (_currentUser?['name'] ??
                _currentUser?['full_name'] ??
                _currentUser?['email'] ??
                'Driver')
            .toString();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(color: Color(kGoldColor)),
                    SizedBox(height: 14),
                    Text(
                      'Opening your movement log...',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                )
              : _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 36,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _openMyMovementLog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(kGoldColor),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.route_outlined,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Welcome $driverName',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tap below to open your assigned safari movement log.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_currentUser == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DriverTripsScreen(
                              driver: _currentUser!,
                              useCurrentAssignments: true,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(kGoldColor),
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.speed_outlined),
                      label: const Text('Open My Movement Log'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
