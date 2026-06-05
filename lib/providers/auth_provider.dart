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
  bool hasRole(String role) => _roles.contains(role);

  /// True when the current user holds [permission]. Admins implicitly have
  /// every permission, mirroring the web client's behaviour.
  bool hasPermission(String? permission) {
    if (permission == null || permission.isEmpty) return true;
    if (hasRole('Admin')) return true;
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
        _roles = await ApiService.getRoles();
        _permissions = await ApiService.getPermissions();
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
    _loading = true;
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
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Network error. Check your connection.';
      _loading = false;
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
