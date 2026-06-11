import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _loggedIn = false;
  bool _loading = true;
  String? _error;
  List<String> _roles = const <String>[];
  List<String> _permissions = const <String>[];

  bool get loggedIn => _loggedIn;
  bool get loading => _loading;
  String? get error => _error;
  List<String> get roles => _roles;
  List<String> get permissions => _permissions;

  /// True when the current user holds [role].
  bool hasRole(String role) {
    final normalized = role.trim().toLowerCase();
    return _roles.any((r) => r.trim().toLowerCase() == normalized);
  }

  /// True when the current user holds [permission]. Admins implicitly have
  /// every permission, mirroring the web client's behaviour.
  bool hasPermission(String? permission) {
    if (permission == null || permission.isEmpty) return true;
    if (hasRole('admin')) return true;
    return _permissions.contains(permission);
  }

  AuthProvider() {
    _checkToken();
  }

  Future<void> _checkToken() async {
    final token = await ApiService.getToken();
    final rememberMe = await ApiService.getRememberMe();
    final hasToken = token != null && token.isNotEmpty;

    // If user did not choose "remember me", keep login only for current app session.
    if (hasToken && !rememberMe) {
      await ApiService.clearAuthSession();
      _loggedIn = false;
      _roles = const <String>[];
      _permissions = const <String>[];
    } else {
      _loggedIn = hasToken;
      if (hasToken) {
        try {
          final me = await ApiService.refreshMeCache();
          final r = me?['roles'];
          final p = me?['permissions'];
          _roles = r is List ? r.map((e) => e.toString()).toList() : const [];
          _permissions = p is List
              ? p.map((e) => e.toString()).toList()
              : const [];
        } catch (_) {
          // If the token is stale/invalid, drop the session so the app does
          // not continue under a mismatched cached identity.
          await ApiService.clearAuthSession();
          _loggedIn = false;
          _roles = const <String>[];
          _permissions = const <String>[];
        }
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> login(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    _error = null;
    // Always start from a clean auth state so a previous account cannot
    // survive behind a failed or mismatched login attempt.
    await ApiService.clearAuthSession();
    _loggedIn = false;
    _roles = const <String>[];
    _permissions = const <String>[];
    // Keep `_loading` reserved for app bootstrap token checks only.
    // Toggling it during interactive login causes the app root to swap to
    // splash (`home: auth.loading ? _Splash : ...`), rebuilding LoginScreen
    // and clearing the text fields after an invalid-credentials response.
    notifyListeners();
    try {
      final result = await ApiService.login(
        email,
        password,
        rememberMe: rememberMe,
      );
      _loggedIn = true;
      final r = result['roles'];
      final p = result['permissions'];
      _roles = r is List ? r.map((e) => e.toString()).toList() : const [];
      _permissions = p is List ? p.map((e) => e.toString()).toList() : const [];
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loggedIn = false;
      _roles = const <String>[];
      _permissions = const <String>[];
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Network error. Check your connection.';
      _loggedIn = false;
      _roles = const <String>[];
      _permissions = const <String>[];
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await ApiService.logout();
    _loggedIn = false;
    _roles = const <String>[];
    _permissions = const <String>[];
    notifyListeners();
  }
}
