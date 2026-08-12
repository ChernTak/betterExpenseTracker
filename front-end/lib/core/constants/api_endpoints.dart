class ApiEndpoints {
  // Testing on a physical Android phone over Wi-Fi, so we use the PC's LAN
  // IP address instead of the emulator-only alias 10.0.2.2. The phone and
  // PC must be on the same Wi-Fi network, and Windows Firewall must allow
  // inbound connections on this port.
  //
  // The IP is passed in at build/run time via --dart-define=API_BASE_URL=...
  // (see front-end/dart_defines.example.json) instead of being hardcoded, since
  // it changes whenever the PC reconnects to Wi-Fi or gets a new DHCP lease.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.210.115.94:3000',
  );

  static const String expenses = '$baseUrl/api/expenses';
  static const String auth = '$baseUrl/api/auth';
  static const String budgets = '$baseUrl/api/budgets';
  static const String ocr = '$baseUrl/api/ocr';
  static const String categories = '$baseUrl/api/categories';
  static const String insights = '$baseUrl/api/insights';
  static const String income = '$baseUrl/api/income';
  static const String admin = '$baseUrl/api/admin';
  static const String recommendations = '$baseUrl/api/recommendations';

  static String expenseCreate() => '$expenses/post';
  static String expenseCategorize() => '$expenses/categorize';
  static String expenseFetchAll() => '$expenses/fetch';
  static String expenseById(String id) => '$expenses/$id';
  static String expenseUpdate(String id) => '$expenses/update/$id';
  static String expenseDelete(String id) => '$expenses/delete/$id';

  static String authRegister() => '$auth/register';
  static String authLogin() => '$auth/login';
  static String authGuest() => '$auth/guest';
  static String authRequestPasswordReset() => '$auth/reset-password';
  static String authConfirmPasswordReset() => '$auth/reset-password/confirm';
  static String authFcmToken() => '$auth/fcm-token';
  static String authLocationConsent() => '$auth/location-consent';

  // FR3.1/FR3.4 — omit month/year to default to the current month (backend does the same)
  static String budgetsList({int? month, int? year}) {
    final params = <String>[];
    if (month != null) params.add('month=$month');
    if (year != null) params.add('year=$year');
    return params.isEmpty ? budgets : '$budgets?${params.join('&')}';
  }

  static String budgetUpdate(String id) => '$budgets/$id';
  static String budgetDelete(String id) => '$budgets/$id';
  static String budgetAlerts({int limit = 20}) =>
      '$budgets/alerts?limit=$limit';

  static String ocrParse() => '$ocr/parse';

  static String categoryUpdate(String id) => '$categories/$id';
  static String categoryDelete(String id) => '$categories/$id';
  static String categoryReorder() => '$categories/reorder';

  static String insightsForecast() => '$insights/forecast';
  static String insightsPredictions() => '$insights/predictions';
  static String insightsModelVersion() => '$insights/model/version';
  static String insightsModelFile() => '$insights/model/file';

  static String incomeUpdate(String id) => '$income/$id';
  static String incomeDelete(String id) => '$income/$id';

  // Location-based food recommendation feature
  static String recommendationsFood({
    required double lat,
    required double lng,
    double? radius,
    List<String>? cuisines,
    bool? halal,
    String? visitFilter,
  }) {
    final params = <String>['lat=$lat', 'lng=$lng'];
    if (radius != null) params.add('radius=$radius');
    if (cuisines != null && cuisines.isNotEmpty) params.add('cuisines=${cuisines.join(',')}');
    if (halal == true) params.add('halal=true');
    if (visitFilter != null) params.add('visitFilter=$visitFilter');
    return '$recommendations/food?${params.join('&')}';
  }

  static String recommendationVenueDetail(String provider, String providerPlaceId) =>
      '$recommendations/food/venues/$provider/${Uri.encodeComponent(providerPlaceId)}';

  // venue['photoUrl'] from the recommendations/detail response is already a
  // path relative to the server root (e.g. '/api/recommendations/food/photo/...')
  // — the backend doesn't reliably know its own externally-reachable host
  // given this project's LAN-IP/adb-reverse setup, so it returns a path and
  // this just prefixes the baseUrl the client already knows.
  static String recommendationVenuePhoto(String photoPath) => '$baseUrl$photoPath';

  // FR1.7 — admin-only account management
  static String adminUsers() => '$admin/users';
  static String adminDeactivateUser(String userId) => '$admin/users/$userId/deactivate';
  static String adminReactivateUser(String userId) => '$admin/users/$userId/reactivate';
  static String adminDeleteUser(String userId) => '$admin/users/$userId';

  // PDPA compliance additions — deletion grace period, DSAR export, consent
  // history and admin accountability (see back-end/src/routes/admin.routes.js)
  static String adminCancelDeletion(String userId) => '$admin/users/$userId/cancel-deletion';
  static String adminPurgeUser(String userId, {bool force = false}) =>
      '$admin/users/$userId/purge${force ? '?force=true' : ''}';
  static String adminExportUser(String userId) => '$admin/users/$userId/export';
  static String adminConsentHistory(String userId) => '$admin/users/$userId/consent-history';
  static String adminAuditLog() => '$admin/audit-log';
  static String adminPurgeRecommendationLogs(int olderThanDays) =>
      '$admin/recommendation-logs/purge?olderThanDays=$olderThanDays';
  static String adminPurgeStaleGuests(int olderThanDays) =>
      '$admin/guests/purge?olderThanDays=$olderThanDays';
}
