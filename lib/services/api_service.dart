import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/paged_result.dart';
import 'offline_cache_service.dart';

class ApiService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _tokenTypeKey = 'auth_token_type';
  static const _userKey = 'auth_user';
  static const _rolesKey = 'auth_roles';
  static const _permissionsKey = 'auth_permissions';
  static const _rememberMeKey = 'auth_remember_me';

  static Future<String?> getToken() => _storage.read(key: _tokenKey);

  static Future<List<String>> getRoles() async {
    final raw = await _storage.read(key: _rolesKey);
    return _decodeStringList(raw);
  }

  static Future<List<String>> getPermissions() async {
    final raw = await _storage.read(key: _permissionsKey);
    return _decodeStringList(raw);
  }

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  static Future<bool> getRememberMe() async {
    final value = await _storage.read(key: _rememberMeKey);
    return value == 'true';
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  static Future<void> saveAuthSession({
    required String token,
    String? tokenType,
    Map<String, dynamic>? user,
    List<String>? roles,
    List<String>? permissions,
    required bool rememberMe,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _rememberMeKey, value: rememberMe.toString());

    if (tokenType != null && tokenType.isNotEmpty) {
      await _storage.write(key: _tokenTypeKey, value: tokenType);
    } else {
      await _storage.delete(key: _tokenTypeKey);
    }

    if (user != null) {
      await _storage.write(key: _userKey, value: jsonEncode(user));
    } else {
      await _storage.delete(key: _userKey);
    }

    await _storage.write(
      key: _rolesKey,
      value: jsonEncode(roles ?? const <String>[]),
    );
    await _storage.write(
      key: _permissionsKey,
      value: jsonEncode(permissions ?? const <String>[]),
    );
  }

  static Future<void> clearToken() => _storage.delete(key: _tokenKey);

  static Future<void> clearAuthSession() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _tokenTypeKey),
      _storage.delete(key: _userKey),
      _storage.delete(key: _rolesKey),
      _storage.delete(key: _permissionsKey),
      _storage.delete(key: _rememberMeKey),
    ]);
  }

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (auth) {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  static dynamic _parse(http.Response res) {
    dynamic body;
    try {
      body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    } catch (_) {
      body = <String, dynamic>{'message': res.body};
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    throw ApiException(
      res.statusCode,
      body is Map
          ? (body['message']?.toString() ??
                'Request failed (${res.statusCode})')
          : 'Request failed (${res.statusCode})',
    );
  }

  static Future<dynamic> get(String path) async {
    final res = await http.get(
      Uri.parse('$kApiBaseUrl$path'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  static Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final res = await http.post(
      Uri.parse('$kApiBaseUrl$path'),
      headers: await _headers(auth: auth),
      body: jsonEncode(body),
    );
    return _parse(res);
  }

  static Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('$kApiBaseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _parse(res);
  }

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(
      Uri.parse('$kApiBaseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _parse(res);
  }

  static Future<dynamic> delete(String path) async {
    final res = await http.delete(
      Uri.parse('$kApiBaseUrl$path'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  static Future<Uint8List> downloadBytes(String path) async {
    final res = await http.get(
      Uri.parse('$kApiBaseUrl$path'),
      headers: await _headers(),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }

    _parse(res);
    throw ApiException(res.statusCode, 'Download failed (${res.statusCode})');
  }

  static Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    String? fileField,
    String? filePath,
    String? methodOverride,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$kApiBaseUrl$path'));
    req.headers.addAll(await _headers());
    req.headers.remove('Content-Type');

    req.fields.addAll(fields);
    if (methodOverride != null && methodOverride.isNotEmpty) {
      req.fields['_method'] = methodOverride;
    }

    if (fileField != null && filePath != null && filePath.isNotEmpty) {
      req.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    final data = await post('/login', {
      'email': email,
      'password': password,
    }, auth: false);

    final tokenRaw =
        data['token'] ?? data['access_token'] ?? data['data']?['token'];
    if (tokenRaw == null) throw ApiException(401, 'No token in response');

    final token = tokenRaw.toString();
    final tokenType = (data['token_type'] ?? data['tokenType'] ?? 'Bearer')
        .toString();

    final userRaw = data['user'] ?? data['data']?['user'];
    Map<String, dynamic>? user;
    if (userRaw is Map<String, dynamic>) {
      user = userRaw;
    } else if (userRaw is Map) {
      user = Map<String, dynamic>.from(userRaw);
    }

    final rolesRaw = data['roles'] ?? data['data']?['roles'];
    final permissionsRaw = data['permissions'] ?? data['data']?['permissions'];

    final roles = rolesRaw is List
        ? rolesRaw.map((e) => e.toString()).toList()
        : <String>[];
    final permissions = permissionsRaw is List
        ? permissionsRaw.map((e) => e.toString()).toList()
        : <String>[];

    await saveAuthSession(
      token: token,
      tokenType: tokenType,
      user: user,
      roles: roles,
      permissions: permissions,
      rememberMe: rememberMe,
    );

    // Validate that the backend actually authenticated the account the user
    // typed, not a stale/cached identity.
    final enteredEmail = email.trim().toLowerCase();
    final loginEmail = user?['email']?.toString().trim().toLowerCase();
    if (loginEmail != null &&
        loginEmail.isNotEmpty &&
        loginEmail != enteredEmail) {
      await clearAuthSession();
      throw ApiException(
        401,
        'Authenticated account mismatch. Please sign in again.',
      );
    }

    // Ask the backend who this token belongs to and overwrite any stale local
    // identity/role cache. This prevents accidental cross-account UI state.
    final me = await refreshMeCache();
    final meEmail = me?['email']?.toString().trim().toLowerCase();
    if (meEmail != null && meEmail.isNotEmpty && meEmail != enteredEmail) {
      await clearAuthSession();
      throw ApiException(
        401,
        'Authenticated account mismatch. Please sign in again.',
      );
    }

    return <String, dynamic>{
      'token': token,
      'token_type': tokenType,
      'user': me ?? user,
      'roles': me?['roles'] is List
          ? (me!['roles'] as List).map((e) => e.toString()).toList()
          : roles,
      'permissions': me?['permissions'] is List
          ? (me!['permissions'] as List).map((e) => e.toString()).toList()
          : permissions,
      'rememberMe': rememberMe,
    };
  }

  /// Calls `/me` using the current token and synchronizes local cached user,
  /// roles, and permissions with what the backend reports.
  static Future<Map<String, dynamic>?> refreshMeCache() async {
    final data = await get('/me');
    if (data is! Map) return null;

    final root = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data);

    final dynamic rawUser = root['user'] ?? root['data'] ?? root;
    Map<String, dynamic>? user;
    if (rawUser is Map<String, dynamic>) {
      user = rawUser;
    } else if (rawUser is Map) {
      user = Map<String, dynamic>.from(rawUser);
    }

    List<String> readList(dynamic value) {
      if (value is List) return value.map((e) => e.toString()).toList();
      return const <String>[];
    }

    final roles = readList(root['roles'] ?? user?['roles']);
    final permissions = readList(root['permissions'] ?? user?['permissions']);

    if (user != null) {
      await _storage.write(key: _userKey, value: jsonEncode(user));
    }
    await _storage.write(key: _rolesKey, value: jsonEncode(roles));
    await _storage.write(key: _permissionsKey, value: jsonEncode(permissions));

    if (user != null) {
      user = <String, dynamic>{
        ...user,
        'roles': roles,
        'permissions': permissions,
      };
    }
    return user;
  }

  /// Fetches all roles and permissions defined in the system.
  /// Returns a map: { 'roles': [{name, permissions: [..]}], 'permissions': [..] }
  static Future<Map<String, dynamic>> fetchRolesPermissions() async {
    final data = await get('/roles/permissions');
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static Future<void> logout() async {
    try {
      await post('/logout', <String, dynamic>{});
    } catch (_) {}
    await clearAuthSession();
  }

  static Future<List<dynamic>> fetchList(String path) async {
    final data = await get(path);
    return _extractList(data);
  }

  static Future<List<dynamic>> fetchInspections() async {
    return fetchList('/inspections');
  }

  static Future<Map<String, dynamic>> fetchInspection(int inspectionId) async {
    final data = await get('/inspections/$inspectionId');

    if (data is Map<String, dynamic>) {
      final nested = data['inspection'];
      if (nested is Map<String, dynamic>) return nested;
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    throw ApiException(500, 'Unexpected inspection response format');
  }

  static Future<Map<String, dynamic>> createInspection(
    Map<String, dynamic> payload,
  ) async {
    final data = await post('/inspections', payload);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateInspection(
    int inspectionId,
    Map<String, dynamic> payload,
  ) async {
    final data = await put('/inspections/$inspectionId', payload);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static Future<void> removeInspection(int inspectionId) async {
    await delete('/inspections/$inspectionId');
  }

  static Future<Map<String, dynamic>> uploadInspectionImage(
    int inspectionId,
    String filePath,
  ) async {
    final data = await postMultipart(
      '/inspections/$inspectionId/images',
      fields: {},
      fileField: 'image',
      filePath: filePath,
    );
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static Future<Uint8List> downloadInspectionPdf(int inspectionId) async {
    return downloadBytes('/inspections/$inspectionId/pdf');
  }

  static Future<List<dynamic>> fetchFuelRequisitions() async {
    return fetchList('/fuel-requisitions');
  }

  static Future<Map<String, dynamic>> fetchFuelRequisition(
    int fuelRequisitionId,
  ) async {
    final data = await get('/fuel-requisitions/$fuelRequisitionId');

    if (data is Map<String, dynamic>) {
      final nested =
          data['fuel_requisition'] ?? data['fuelRequisition'] ?? data['data'];
      if (nested is Map<String, dynamic>) return nested;
      if (nested is Map) return Map<String, dynamic>.from(nested);
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    throw ApiException(500, 'Unexpected fuel requisition response format');
  }

  static Future<Map<String, dynamic>> createFuelRequisition(
    Map<String, dynamic> payload,
  ) async {
    final data = await post('/fuel-requisitions', payload);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateFuelRequisition(
    int fuelRequisitionId,
    Map<String, dynamic> payload,
  ) async {
    final data = await put('/fuel-requisitions/$fuelRequisitionId', payload);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static Future<void> removeFuelRequisition(int fuelRequisitionId) async {
    await delete('/fuel-requisitions/$fuelRequisitionId');
  }

  static Future<PagedResult> fetchPaged(
    String path, {
    int page = 1,
    int perPage = 20,
    String? cacheKey,
  }) async {
    final separator = path.contains('?') ? '&' : '?';
    final urlPath = '$path${separator}page=$page&per_page=$perPage';

    try {
      final data = await get(urlPath);
      final paged = _parsePagedResponse(data, fallbackPerPage: perPage);
      if (cacheKey != null && cacheKey.isNotEmpty) {
        await OfflineCacheService.save('${cacheKey}_$page', data);
      }
      return paged;
    } catch (_) {
      if (cacheKey == null || cacheKey.isEmpty) rethrow;

      final cached = await OfflineCacheService.read('${cacheKey}_$page');
      if (cached == null) rethrow;

      final paged = _parsePagedResponse(cached, fallbackPerPage: perPage);
      return PagedResult(
        items: paged.items,
        currentPage: paged.currentPage,
        lastPage: paged.lastPage,
        perPage: paged.perPage,
        total: paged.total,
        fromCache: true,
      );
    }
  }

  static PagedResult _parsePagedResponse(
    dynamic payload, {
    required int fallbackPerPage,
  }) {
    if (payload is List) {
      return PagedResult(
        items: payload,
        currentPage: 1,
        lastPage: 1,
        perPage: payload.length,
        total: payload.length,
      );
    }

    if (payload is Map) {
      final items = _extractList(payload);
      final meta = payload['meta'];

      final currentPage = _toInt(
        meta is Map ? meta['current_page'] : payload['current_page'],
        fallback: 1,
      );
      final lastPage = _toInt(
        meta is Map ? meta['last_page'] : payload['last_page'],
        fallback: 1,
      );
      final perPage = _toInt(
        meta is Map ? meta['per_page'] : payload['per_page'],
        fallback: fallbackPerPage,
      );
      final total = _toInt(
        meta is Map ? meta['total'] : payload['total'],
        fallback: items.length,
      );

      return PagedResult(
        items: items,
        currentPage: currentPage,
        lastPage: lastPage,
        perPage: perPage,
        total: total,
      );
    }

    return const PagedResult(
      items: <dynamic>[],
      currentPage: 1,
      lastPage: 1,
      perPage: 0,
      total: 0,
    );
  }

  static List<dynamic> _extractList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is! Map) return <dynamic>[];

    if (payload['data'] is List) return List<dynamic>.from(payload['data']);

    for (final key in [
      'items',
      'results',
      'inspections',
      'checklists',
      'clients',
      'leads',
      'invoices',
      'payments',
      'quotations',
      'vehicles',
      'safari_allocations',
      'safariAllocations',
    ]) {
      final value = payload[key];
      if (value is List) return List<dynamic>.from(value);
    }

    for (final value in payload.values) {
      if (value is List) return List<dynamic>.from(value);
    }

    return <dynamic>[];
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }

  // ── Drivers ────────────────────────────────────────────────────────────────
  static Future<List<dynamic>> fetchDrivers() async {
    try {
      return await fetchList('/drivers');
    } catch (_) {
      try {
        final users = await fetchList('/users?role=driver');
        if (users.isNotEmpty) return users;
      } catch (_) {}

      final users = await fetchList('/users');
      return users.where((u) {
        if (u is! Map) return false;
        final role = (u['role'] ?? u['user_role'] ?? u['type'] ?? '')
            .toString()
            .toLowerCase();
        if (role.contains('driver')) return true;
        final roles = u['roles'];
        if (roles is List) {
          return roles.any(
            (r) => r.toString().toLowerCase().contains('driver'),
          );
        }
        return false;
      }).toList();
    }
  }

  // ── Driver trips ────────────────────────────────────────────────────────────
  static Future<List<dynamic>> fetchDriverTrips(int driverId) async =>
      _fetchDriverTripsWithFallback(driverId);

  static Future<List<dynamic>> _fetchDriverTripsWithFallback(
    int driverId,
  ) async {
    final paths = <String>[
      '/drivers/$driverId/trips',
      '/users/$driverId/trips',
    ];

    for (final path in paths) {
      try {
        final list = await fetchList(path);
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }

    // SafariAllocationController::index returns all allocations (or already
    // filtered for Driver role). For non-driver users, filter client-side.
    try {
      final allocations = await fetchList('/safari-allocations');
      return allocations.where((a) {
        if (a is! Map) return false;
        final raw = a['driverId'] ?? a['driver_id'] ?? a['driver']?['id'];
        final id = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
        return id == driverId;
      }).toList();
    } catch (_) {
      return <dynamic>[];
    }
  }

  static Future<List<dynamic>> fetchMyAssignedTrips() async {
    try {
      return await fetchList('/safari-allocations');
    } catch (_) {
      final user = await getCurrentUser();
      final raw =
          user?['id'] ??
          user?['user_id'] ??
          user?['userId'] ??
          user?['driverId'];
      final id = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
      if (id == null) return <dynamic>[];
      return _fetchDriverTripsWithFallback(id);
    }
  }

  // ── Odometer logs ───────────────────────────────────────────────────────────
  static Future<List<dynamic>> fetchOdometerLogs(dynamic tripId) async =>
      fetchList('/trips/$tripId/odometer-logs');

  static Future<Map<String, dynamic>> createOdometerLog(
    dynamic tripId,
    Map<String, dynamic> payload,
  ) async {
    final data = await post('/trips/$tripId/odometer-logs', payload);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  /// Same as [createOdometerLog] but uploads an attached photo (odometer
  /// picture) using multipart/form-data. Used by the offline sync worker
  /// when an outbox entry has a `photo_path`.
  static Future<Map<String, dynamic>> createOdometerLogMultipart(
    dynamic tripId, {
    required Map<String, dynamic> payload,
    required String photoField,
    required String photoPath,
  }) async {
    final fields = <String, String>{};
    payload.forEach((key, value) {
      if (value == null) return;
      fields[key] = value is String ? value : value.toString();
    });

    final data = await postMultipart(
      '/trips/$tripId/odometer-logs',
      fields: fields,
      fileField: photoField,
      filePath: photoPath,
    );
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateOdometerLog(
    dynamic logId,
    Map<String, dynamic> payload,
  ) async {
    final data = await put('/odometer-logs/$logId', payload);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static Future<void> deleteOdometerLog(dynamic logId) async =>
      delete('/odometer-logs/$logId');
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
