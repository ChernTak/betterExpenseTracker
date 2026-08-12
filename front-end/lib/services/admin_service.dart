import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// A row from GET /api/admin/users. password_hash is never returned by the
/// backend (see back-end/src/models/user.model.js findAllForAdmin).
///
/// mobile_number is masked in the list response (PDPA data-minimization —
/// see findAllForAdmin) — only GET /api/admin/users/:id returns it in full,
/// which is why this same class is reused for both endpoints rather than
/// having a separate "detail" type: the shape is identical, only how much
/// of mobile_number is visible differs server-side.
class AdminUser {
  final String userId;
  final String email;
  final String username;
  final String role;
  final bool isGuest;
  final bool isActive;
  final bool isLocked;
  final String? mobileNumber;
  final DateTime? deactivatedAt;
  final DateTime? deletionRequestedAt;
  final DateTime createdAt;

  const AdminUser({
    required this.userId,
    required this.email,
    required this.username,
    required this.role,
    required this.isGuest,
    required this.isActive,
    required this.isLocked,
    required this.mobileNumber,
    required this.deactivatedAt,
    required this.deletionRequestedAt,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      userId: json['user_id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      role: json['role'] as String,
      isGuest: json['is_guest'] as bool,
      isActive: json['is_active'] as bool,
      isLocked: json['is_locked'] as bool,
      mobileNumber: json['mobile_number'] as String?,
      deactivatedAt: json['deactivated_at'] != null ? DateTime.parse(json['deactivated_at'] as String) : null,
      deletionRequestedAt:
          json['deletion_requested_at'] != null ? DateTime.parse(json['deletion_requested_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// A row from GET /api/admin/users/:id/consent-history (consent_log table).
class ConsentLogEntry {
  final String consentType;
  final bool granted;
  final DateTime changedAt;

  const ConsentLogEntry({required this.consentType, required this.granted, required this.changedAt});

  factory ConsentLogEntry.fromJson(Map<String, dynamic> json) {
    return ConsentLogEntry(
      consentType: json['consent_type'] as String,
      granted: json['granted'] as bool,
      changedAt: DateTime.parse(json['changed_at'] as String),
    );
  }
}

/// A row from GET /api/admin/audit-log (admin_audit_log table) — the
/// accountability trail of admin actions against user records.
class AdminAuditEntry {
  final String action;
  final String? targetEmail;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  const AdminAuditEntry({
    required this.action,
    required this.targetEmail,
    required this.details,
    required this.createdAt,
  });

  factory AdminAuditEntry.fromJson(Map<String, dynamic> json) {
    return AdminAuditEntry(
      action: json['action'] as String,
      targetEmail: json['target_email'] as String?,
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Service layer for FR1.7 (admin account management: view/deactivate/delete).
/// Every call requires a JWT for an account with role='admin' — the backend
/// enforces this via admin.middleware.js regardless of what the client sends.
class AdminService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/admin/users
  Future<List<AdminUser>> fetchUsers() async {
    try {
      final response = await http.get(Uri.parse(ApiEndpoints.adminUsers()), headers: await _authHeaders());
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return (body['users'] as List<dynamic>)
            .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(body['message'] ?? 'Failed to load users');
      }
    } catch (e) {
      throw Exception('Error loading users: $e');
    }
  }

  /// GET /api/admin/users/:id — full (unmasked) profile. Audit-logged
  /// server-side as a "view_profile" action every time it's called.
  Future<AdminUser> fetchUser(String userId) async {
    final response = await http.get(Uri.parse(ApiEndpoints.adminDeleteUser(userId)), headers: await _authHeaders());
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Failed to load user (status ${response.statusCode})');
    }
    return AdminUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  /// PATCH /api/admin/users/:id/deactivate
  Future<void> deactivateUser(String userId) => _patch(ApiEndpoints.adminDeactivateUser(userId));

  /// PATCH /api/admin/users/:id/reactivate
  Future<void> reactivateUser(String userId) => _patch(ApiEndpoints.adminReactivateUser(userId));

  /// PATCH /api/admin/users/:id/cancel-deletion — reverses a pending
  /// deletion request within the grace period.
  Future<void> cancelDeletion(String userId) => _patch(ApiEndpoints.adminCancelDeletion(userId));

  Future<void> _patch(String url) async {
    final response = await http.patch(Uri.parse(url), headers: await _authHeaders());
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Request failed (status ${response.statusCode})');
    }
  }

  /// DELETE /api/admin/users/:id — soft: requests deletion (deactivates,
  /// starts the grace-period clock). Permanent removal only happens via
  /// [purgeUser] once that period elapses (PDPA erasure with a
  /// recoverability window, FR1.7).
  Future<void> deleteUser(String userId) async {
    final response = await http.delete(Uri.parse(ApiEndpoints.adminDeleteUser(userId)), headers: await _authHeaders());
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to request deletion (status ${response.statusCode})');
    }
  }

  /// DELETE /api/admin/users/:id/purge — permanent. Rejected with a 400
  /// (surfaced as an Exception here) until the grace period has elapsed,
  /// unless [force] is set.
  Future<void> purgeUser(String userId, {bool force = false}) async {
    final response = await http.delete(
      Uri.parse(ApiEndpoints.adminPurgeUser(userId, force: force)),
      headers: await _authHeaders(),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to purge user (status ${response.statusCode})');
    }
  }

  /// GET /api/admin/users/:id/export — a DSAR export of everything the app
  /// holds on this user. Returned as pretty-printed JSON text for display;
  /// the caller doesn't need it as a parsed object.
  Future<String> exportUser(String userId) async {
    final response = await http.get(Uri.parse(ApiEndpoints.adminExportUser(userId)), headers: await _authHeaders());
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to export user data (status ${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// GET /api/admin/users/:id/consent-history
  Future<List<ConsentLogEntry>> fetchConsentHistory(String userId) async {
    final response =
        await http.get(Uri.parse(ApiEndpoints.adminConsentHistory(userId)), headers: await _authHeaders());
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Failed to load consent history (status ${response.statusCode})');
    }
    return (body['consentHistory'] as List<dynamic>)
        .map((e) => ConsentLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/admin/audit-log — the accountability trail of admin actions.
  Future<List<AdminAuditEntry>> fetchAuditLog() async {
    final response = await http.get(Uri.parse(ApiEndpoints.adminAuditLog()), headers: await _authHeaders());
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Failed to load audit log (status ${response.statusCode})');
    }
    return (body['auditLog'] as List<dynamic>).map((e) => AdminAuditEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// DELETE /api/admin/recommendation-logs/purge — retention purge of raw
  /// GPS coordinates stored by the food-recommendation feature. Returns the
  /// number of rows deleted.
  Future<int> purgeRecommendationLogs(int olderThanDays) async {
    final response = await http.delete(
      Uri.parse(ApiEndpoints.adminPurgeRecommendationLogs(olderThanDays)),
      headers: await _authHeaders(),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Failed to purge recommendation logs (status ${response.statusCode})');
    }
    return body['deletedCount'] as int;
  }

  /// DELETE /api/admin/guests/purge — PDPA storage-limitation cleanup for
  /// "Continue as Guest" accounts abandoned past the given inactivity
  /// threshold (see user.model.js purgeStaleGuests for how "inactive" is
  /// computed). Returns the number of accounts deleted.
  Future<int> purgeStaleGuests(int olderThanDays) async {
    final response = await http.delete(
      Uri.parse(ApiEndpoints.adminPurgeStaleGuests(olderThanDays)),
      headers: await _authHeaders(),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Failed to purge stale guest accounts (status ${response.statusCode})');
    }
    return body['deletedCount'] as int;
  }
}
