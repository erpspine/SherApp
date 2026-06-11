import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/driver_trips_screen.dart';
import 'screens/drivers_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/odometer_sync_service.dart';

void main() {
  // Single, app-wide sync worker. It lives for the lifetime of the process and
  // drains the local odometer outbox whenever the device is online.
  final syncService = OdometerSyncService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        Provider<OdometerSyncService>.value(value: syncService),
      ],
      child: _AppBootstrap(sync: syncService, child: const SherErpApp()),
    ),
  );
}

/// Starts/stops the [OdometerSyncService] in lockstep with the user's
/// authentication state. Drivers go offline → outbox grows → sync resumes on
/// next login or connectivity event.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap({required this.sync, required this.child});

  final OdometerSyncService sync;
  final Widget child;

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  bool _started = false;

  @override
  void dispose() {
    widget.sync.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loggedIn && !_started) {
      _started = true;
      widget.sync.start();
    } else if (!auth.loggedIn && _started) {
      _started = false;
      widget.sync.stop();
    }
    return widget.child;
  }
}

class SherErpApp extends StatelessWidget {
  const SherErpApp({super.key});

  Future<Map<String, dynamic>?> _resolveDriver(AuthProvider auth) async {
    if (!auth.hasRole('Driver')) return null;
    // Always resolve from `/me` so role routing uses the active token's
    // identity, never stale cached user data from a previous session.
    return ApiService.refreshMeCache();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return MaterialApp(
      title: 'Sher ERP',
      debugShowCheckedModeBanner: false,
      theme: SherTheme.lightTheme,
      home: auth.loading
          ? const _Splash()
          : auth.loggedIn
          ? _LandingRouter(auth: auth, resolveDriver: _resolveDriver)
          : const LoginScreen(),
    );
  }
}

/// Routes the user to the right landing screen for their role:
///
/// - **Driver**: straight into their assigned trips list (no drawer, no
///   bottom nav). Falls back to the generic [DriversScreen] if the cached
///   profile cannot be resolved.
/// - **Everyone else**: the standard [HomeScreen] shell.
class _LandingRouter extends StatelessWidget {
  const _LandingRouter({required this.auth, required this.resolveDriver});

  final AuthProvider auth;
  final Future<Map<String, dynamic>?> Function(AuthProvider) resolveDriver;

  @override
  Widget build(BuildContext context) {
    if (!auth.hasRole('Driver')) return const HomeScreen();

    return FutureBuilder<Map<String, dynamic>?>(
      future: resolveDriver(auth),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Splash();
        }
        final user = snapshot.data;
        if (user == null) {
          // Cached profile missing — fall back to the driver landing screen
          // which prompts for re-login.
          return const DriversScreen();
        }
        return DriverTripsScreen(driver: user, useCurrentAssignments: true);
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
