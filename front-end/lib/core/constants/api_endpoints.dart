class ApiEndpoints {
  // LAN IP for testing on a physical device over Wi-Fi; passed via --dart-define=API_BASE_URL since it changes with DHCP leases.
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
  static const String config = '$baseUrl/api/config';
  static const String goals = '$baseUrl/api/goals';
  static const String wishlist = '$baseUrl/api/wishlist';
  static const String nudge = '$baseUrl/api/nudge';

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
  static String authMe() => '$auth/me';
  static String authFcmToken() => '$auth/fcm-token';
  static String authLocationConsent() => '$auth/location-consent';
  static String authBackgroundLocationConsent() => '$auth/background-location-consent';

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

  // FR4.4 remote kill-switch — checked at startup so hands-free voice
  // logging can be disabled server-side without an app update.
  static String configFeatureFlags() => '$config/feature-flags';

  static String ocrParse() => '$ocr/parse';
  // OTA delivery for the on-device receipt NER model (LayoutLMv3) — mirrors
  // insightsModelVersion()/insightsModelFile()'s pattern for Tier B.
  static String ocrModelVersion() => '$ocr/model/version';
  static String ocrModelFile() => '$ocr/model/file';

  static String categoryUpdate(String id) => '$categories/$id';
  static String categoryDelete(String id) => '$categories/$id';
  static String categoryReorder() => '$categories/reorder';

  static String insightsForecast() => '$insights/forecast';
  static String insightsPredictions() => '$insights/predictions';
  static String insightsModelVersion() => '$insights/model/version';
  static String insightsModelFile() => '$insights/model/file';

  static String incomeUpdate(String id) => '$income/$id';
  static String incomeDelete(String id) => '$income/$id';

  static String goalUpdate(String id) => '$goals/$id';
  static String goalDelete(String id) => '$goals/$id';
  static String goalContributions(String id) => '$goals/$id/contributions';

  static String wishlistList({String? status}) =>
      status == null ? wishlist : '$wishlist?status=$status';
  static String wishlistUpdate(String id) => '$wishlist/$id';
  static String wishlistDelete(String id) => '$wishlist/$id';
  static String wishlistConvertToGoal(String id) => '$wishlist/$id/convert-to-goal';

  static String nudgeHighRiskLocations() => '$nudge/high-risk-locations';
  static String nudgeLocationEntered() => '$nudge/location-entered';

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
    if (cuisines != null && cuisines.isNotEmpty)
      params.add('cuisines=${cuisines.join(',')}');
    if (halal == true) params.add('halal=true');
    if (visitFilter != null) params.add('visitFilter=$visitFilter');
    return '$recommendations/food?${params.join('&')}';
  }

  static String recommendationVenueDetail(
    String provider,
    String providerPlaceId,
  ) =>
      '$recommendations/food/venues/$provider/${Uri.encodeComponent(providerPlaceId)}';

  // Backend returns a path (not full URL) since it can't reliably know its own externally-reachable host; prefix baseUrl here.
  static String recommendationVenuePhoto(String photoPath) =>
      '$baseUrl$photoPath';

  // FR1.7 — admin-only account management
  static String adminUsers() => '$admin/users';
  static String adminDeactivateUser(String userId) =>
      '$admin/users/$userId/deactivate';
  static String adminReactivateUser(String userId) =>
      '$admin/users/$userId/reactivate';
  static String adminDeleteUser(String userId) => '$admin/users/$userId';

  // PDPA compliance additions — deletion grace period, DSAR export, consent
  // history and admin accountability (see back-end/src/routes/admin.routes.js)
  static String adminCancelDeletion(String userId) =>
      '$admin/users/$userId/cancel-deletion';
  static String adminPurgeUser(String userId, {bool force = false}) =>
      '$admin/users/$userId/purge${force ? '?force=true' : ''}';
  static String adminExportUser(String userId) => '$admin/users/$userId/export';
  static String adminConsentHistory(String userId) =>
      '$admin/users/$userId/consent-history';
  static String adminAuditLog() => '$admin/audit-log';
  static String adminPurgeRecommendationLogs(int olderThanDays) =>
      '$admin/recommendation-logs/purge?olderThanDays=$olderThanDays';
  static String adminPurgeStaleGuests(int olderThanDays) =>
      '$admin/guests/purge?olderThanDays=$olderThanDays';
}
