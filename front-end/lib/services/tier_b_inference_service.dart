import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// On-device Tier B (variable spend) inference via TFLite; Tier A and the rest of the forecast still come from GET /api/insights/forecast. Predicts the whole remaining month directly (one interpreter call, "as of" today using history strictly before today). Fixed/variable split mirrors back-end/src/ml/forecaster.js#detectRecurringGroups (keep both in sync). Model is OTA: checks GET /api/insights/model/version once/day and downloads a newer one over the bundled asset default.
class TierBInferenceService {
  static Interpreter? _interpreter;

  static const _fixedVarianceThreshold = 0.05;
  static const _fixedIntervalMinDays = 26;
  static const _fixedIntervalMaxDays = 34;
  static const _minHistoryDays = 30;
  static const _baselineWindowDays = 90;
  static const _baselineFloor = 1.0;

  // Must match ROLL_RATIO_CLIP_MAX/TARGET_RATIO_CLIP_MAX in ai/prepare_tier_b_data.py / train_tier_b.py or inputs go out-of-distribution; values from real Berka percentiles (an earlier guess of 30 clipped the top ~10%+).
  static const _rollRatioClipMax = 15.0;
  static const _targetRatioClipMax = 150.0;

  static const _bundledModelAsset = 'assets/models/tier_b_regressor.tflite';
  static const _downloadedModelFileName = 'tier_b_regressor_downloaded.tflite';
  static const _versionPrefsKey = 'tier_b_model_version';
  static const _lastCheckedPrefsKey = 'tier_b_model_last_checked';
  static const _updateCheckInterval = Duration(days: 1);

  // Fixed-date Malaysian holidays only; movable lunar/Islamic dates would need a yearly-updated calendar this app doesn't have.
  static const _malaysiaFixedHolidays = [
    [1, 1], // New Year's Day
    [5, 1], // Labour Day
    [8, 31], // National Day
    [9, 16], // Malaysia Day
    [12, 25], // Christmas
  ];

  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<File> _downloadedModelFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_downloadedModelFileName');
  }

  Future<void> _maybeDownloadNewerModel() async {
    final prefs = await SharedPreferences.getInstance();
    final lastChecked = prefs.getInt(_lastCheckedPrefsKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastChecked != null &&
        now - lastChecked < _updateCheckInterval.inMilliseconds) {
      return; // checked recently enough — avoid a network round-trip on every Insights open
    }

    try {
      final versionResponse = await http.get(
        Uri.parse(ApiEndpoints.insightsModelVersion()),
        headers: await _authHeaders(),
      );
      if (versionResponse.statusCode != 200) return;

      final serverVersion =
          (jsonDecode(versionResponse.body) as Map<String, dynamic>)['version']
              as String;
      await prefs.setInt(_lastCheckedPrefsKey, now);

      if (prefs.getString(_versionPrefsKey) == serverVersion)
        return; // already up to date

      final fileResponse = await http.get(
        Uri.parse(ApiEndpoints.insightsModelFile()),
        headers: await _authHeaders(),
      );
      if (fileResponse.statusCode != 200) return;

      final file = await _downloadedModelFile();
      await file.writeAsBytes(fileResponse.bodyBytes);
      await prefs.setString(_versionPrefsKey, serverVersion);
      _interpreter = null; // force the next load to pick up the new file
    } catch (_) {
      // offline or server unreachable — keep using whatever's already loaded
    }
  }

  Future<Interpreter> _loadInterpreter() async {
    if (_interpreter != null) return _interpreter!;

    await _maybeDownloadNewerModel();

    final downloaded = await _downloadedModelFile();
    if (await downloaded.exists()) {
      try {
        return _interpreter = Interpreter.fromFile(downloaded);
      } catch (_) {
        // downloaded file corrupt/incompatible — fall back to the bundled asset
      }
    }

    return _interpreter = await Interpreter.fromAsset(_bundledModelAsset);
  }

  /// Version of the model that produced the last prediction, for logging only (ai/evaluate_tier_b.py) — not used at inference time.
  Future<String> currentModelVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_versionPrefsKey) ?? 'bundled';
  }

  /// Returns null (caller should fall back to the server heuristic) if there's too little history, no budget, or the model fails to load.
  Future<double?> predictRemainingMonthSpend({
    required List<dynamic> expenses,
    required double totalBudget,
    required DateTime today,
  }) async {
    if (totalBudget <= 0) return null;

    final todayDate = DateTime(today.year, today.month, today.day);
    final variableExpenses = _excludeFixedExpenses(expenses);
    if (variableExpenses.isEmpty) return null;

    final series = _buildDailySeries(variableExpenses, todayDate);
    final historyStart = variableExpenses
        .map((e) => _dateOnly(DateTime.parse(e['transaction_date'] as String)))
        .reduce((a, b) => a.isBefore(b) ? a : b);

    if (todayDate.difference(historyStart).inDays < _minHistoryDays)
      return null;

    Interpreter interpreter;
    try {
      interpreter = await _loadInterpreter();
    } catch (_) {
      return null;
    }

    // "As of today" — every feature below uses history strictly BEFORE
    // today, matching training's shift(1) exclusion of the row's own day.
    final baselineStart = _laterOf(
      historyStart,
      todayDate.subtract(const Duration(days: _baselineWindowDays)),
    );
    final baseline = math.max(
      _averageBetween(series, from: baselineStart, toExclusive: todayDate),
      _baselineFloor,
    );

    double rollRatio(int windowDays) {
      final start = _laterOf(
        historyStart,
        todayDate.subtract(Duration(days: windowDays)),
      );
      return math.min(
        _averageBetween(series, from: start, toExclusive: todayDate) / baseline,
        _rollRatioClipMax,
      );
    }

    final volatilityStart = _laterOf(
      historyStart,
      todayDate.subtract(const Duration(days: 14)),
    );
    final volatility = math.min(
      _stddevBetween(series, from: volatilityStart, toExclusive: todayDate) /
          baseline,
      _rollRatioClipMax,
    );

    final monthStart = DateTime(todayDate.year, todayDate.month, 1);
    final monthToDate = _averageBetween(
      series,
      from: monthStart.isBefore(historyStart) ? historyStart : monthStart,
      toExclusive: todayDate,
      sumInstead: true,
    );
    final budgetFriction = math.min(monthToDate / totalBudget, 2.0);

    final daysInMonth = DateTime(todayDate.year, todayDate.month + 1, 0).day;
    final dayOfWeek =
        todayDate.weekday - 1; // Dart Mon=1..Sun=7 -> Python-style Mon=0..Sun=6
    final isWeekend = dayOfWeek >= 5 ? 1.0 : 0.0;
    final daysSincePayday = math
        .min((todayDate.day - 1).abs(), (todayDate.day - 15).abs())
        .toDouble();
    final isMonthEnd = (daysInMonth - todayDate.day) < 3 ? 1.0 : 0.0;
    final daysRemainingRatio = (daysInMonth - todayDate.day) / daysInMonth;
    final daysToHoliday = _daysToNearestHoliday(todayDate);

    final input = [
      [
        rollRatio(3),
        rollRatio(7),
        rollRatio(14),
        dayOfWeek.toDouble(),
        isWeekend,
        daysSincePayday,
        budgetFriction,
        isMonthEnd,
        volatility,
        daysToHoliday,
        daysRemainingRatio,
      ],
    ];
    final output = List.generate(1, (_) => List.filled(1, 0.0));
    interpreter.run(input, output);

    // Model was trained on log1p(remaining_month_ratio); undo with expm1 before using as a ratio.
    final predictedRatio = (math.exp(output[0][0]) - 1).clamp(
      0.0,
      _targetRatioClipMax,
    );

    return predictedRatio * baseline;
  }

  double _daysToNearestHoliday(DateTime date) {
    var minDistance = 366;
    for (final yearOffset in [-1, 0, 1]) {
      for (final monthDay in _malaysiaFixedHolidays) {
        final holiday = DateTime(
          date.year + yearOffset,
          monthDay[0],
          monthDay[1],
        );
        final distance = date.difference(holiday).inDays.abs();
        if (distance < minDistance) minDistance = distance;
      }
    }
    return minDistance.toDouble();
  }

  List<Map<String, dynamic>> _excludeFixedExpenses(List<dynamic> expenses) {
    final rows = expenses.cast<Map<String, dynamic>>();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in rows) {
      final merchant = (e['merchant_name'] as String? ?? '')
          .trim()
          .toLowerCase();
      final key = merchant.isNotEmpty
          ? 'merchant:$merchant'
          : 'category:${e['category']}';
      groups.putIfAbsent(key, () => []).add(e);
    }

    final fixedIds = <String>{};
    for (final group in groups.values) {
      if (group.length < 2) continue;

      final sorted = [...group]
        ..sort(
          (a, b) => DateTime.parse(
            a['transaction_date'] as String,
          ).compareTo(DateTime.parse(b['transaction_date'] as String)),
        );
      final amounts = sorted
          .map((r) => (r['amount'] as num).toDouble())
          .toList();
      final avgAmount = amounts.reduce((a, b) => a + b) / amounts.length;
      if (avgAmount <= 0) continue;

      final variance = _stddev(amounts, avgAmount) / avgAmount;

      final intervals = <double>[];
      for (var i = 1; i < sorted.length; i++) {
        final a = DateTime.parse(sorted[i - 1]['transaction_date'] as String);
        final b = DateTime.parse(sorted[i]['transaction_date'] as String);
        intervals.add(b.difference(a).inDays.toDouble());
      }
      final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;

      if (variance <= _fixedVarianceThreshold &&
          avgInterval >= _fixedIntervalMinDays &&
          avgInterval <= _fixedIntervalMaxDays) {
        fixedIds.addAll(sorted.map((r) => r['expense_id'] as String));
      }
    }

    return rows.where((e) => !fixedIds.contains(e['expense_id'])).toList();
  }

  double _stddev(List<double> values, double mean) {
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _laterOf(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  Map<DateTime, double> _buildDailySeries(
    List<Map<String, dynamic>> expenses,
    DateTime today,
  ) {
    final totals = <DateTime, double>{};
    for (final e in expenses) {
      final date = _dateOnly(DateTime.parse(e['transaction_date'] as String));
      if (date.isAfter(today)) continue;
      totals[date] = (totals[date] ?? 0) + (e['amount'] as num).toDouble();
    }
    return totals;
  }

  /// Days absent from [series] count as 0 spend, matching the training data's calendar-day 0-fill (prepare_tier_b_data.py).
  double _averageBetween(
    Map<DateTime, double> series, {
    required DateTime from,
    required DateTime toExclusive,
    bool sumInstead = false,
  }) {
    if (!from.isBefore(toExclusive)) return 0;

    double sum = 0;
    var count = 0;
    var d = from;
    while (d.isBefore(toExclusive)) {
      sum += series[d] ?? 0;
      count++;
      d = d.add(const Duration(days: 1));
    }

    if (sumInstead) return sum;
    return count == 0 ? 0 : sum / count;
  }

  double _stddevBetween(
    Map<DateTime, double> series, {
    required DateTime from,
    required DateTime toExclusive,
  }) {
    if (!from.isBefore(toExclusive)) return 0;

    final values = <double>[];
    var d = from;
    while (d.isBefore(toExclusive)) {
      values.add(series[d] ?? 0);
      d = d.add(const Duration(days: 1));
    }
    if (values.length < 2) return 0;

    final mean = values.reduce((a, b) => a + b) / values.length;
    return _stddev(values, mean);
  }
}
