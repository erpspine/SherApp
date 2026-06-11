import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// Wraps [child] and only renders it when the authenticated user holds
/// [permission]. Otherwise, renders [denied] (defaults to [AccessDeniedView]).
///
/// Mirrors the behaviour of the web client's `PermissionRoute` in
/// `src/App.jsx`. A null/empty [permission] is treated as "no gate" and the
/// [child] is always rendered. Admins bypass every permission check (this is
/// enforced inside [AuthProvider.hasPermission]).
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.denied,
  });

  /// Permission key (e.g. `vehicles.view`). `null` or empty disables the gate.
  final String? permission;

  /// Widget shown when the permission is granted.
  final Widget child;

  /// Optional widget shown when the permission is denied. Defaults to
  /// [AccessDeniedView].
  final Widget? denied;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.hasPermission(permission)) return child;
    return denied ?? const AccessDeniedView();
  }
}

/// Friendly placeholder shown when the current user lacks the permission
/// required to view a screen. Mirrors the web client's `AccessDenied` card.
class AccessDeniedView extends StatelessWidget {
  const AccessDeniedView({super.key, this.title, this.message});

  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFFDE68A)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title ?? 'Access Denied',
                          style: const TextStyle(
                            color: Color(0xFF78350F),
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message ??
                        'You do not have permission to view this page. '
                            'Please contact your administrator to grant '
                            'access.',
                    style: const TextStyle(
                      color: Color(0xFF78350F),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Convenience widget that renders [child] only when the user holds
/// [permission]. Useful for hiding individual action buttons inline.
class IfPermitted extends StatelessWidget {
  const IfPermitted({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
  });

  final String? permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.hasPermission(permission)) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
