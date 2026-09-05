import 'dart:convert';

import 'package:expense_tracker/services/feature_flag_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fresh install, flag endpoint reachable: caches and returns the server value', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'voiceHandsFreeEnabled': false}), 200);
    });
    final service = FeatureFlagService(client: client);

    final enabled = await service.isVoiceHandsFreeEnabled();

    expect(enabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('feature_flag_voice_hands_free'), isFalse);
  });

  // The core contract: this feature must work with zero connectivity ever,
  // so a network failure can never be allowed to disable it.
  test('fails open when the backend is unreachable', () async {
    final client = MockClient((request) async {
      throw const SocketExceptionStub();
    });
    final service = FeatureFlagService(client: client);

    final enabled = await service.isVoiceHandsFreeEnabled();

    expect(enabled, isTrue);
  });

  test('fails open on a non-200 response without caching it', () async {
    final client = MockClient((request) async => http.Response('error', 500));
    final service = FeatureFlagService(client: client);

    final enabled = await service.isVoiceHandsFreeEnabled();

    expect(enabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('feature_flag_voice_hands_free'), isNull);
  });

  test('recently-cached value is returned without a new network call (throttle)', () async {
    SharedPreferences.setMockInitialValues({
      'feature_flag_voice_hands_free': false,
      'feature_flag_last_checked': DateTime.now().millisecondsSinceEpoch,
    });
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      return http.Response(jsonEncode({'voiceHandsFreeEnabled': true}), 200);
    });
    final service = FeatureFlagService(client: client);

    final enabled = await service.isVoiceHandsFreeEnabled();

    expect(enabled, isFalse); // stayed on the cached value
    expect(callCount, 0); // never refetched within the throttle window
  });

  test('stale cache + unreachable backend keeps the last-known value', () async {
    SharedPreferences.setMockInitialValues({
      'feature_flag_voice_hands_free': false,
      'feature_flag_last_checked': DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
    });
    final client = MockClient((request) async {
      throw const SocketExceptionStub();
    });
    final service = FeatureFlagService(client: client);

    final enabled = await service.isVoiceHandsFreeEnabled();

    // Refresh was attempted (cache was stale) but failed, so the previous
    // false is preserved rather than falling back to the true default.
    expect(enabled, isFalse);
  });
}

/// A minimal stand-in for a thrown network error — MockClient's handler
/// just needs to throw *something* to simulate "backend unreachable"; the
/// real exception type (SocketException, TimeoutException, etc.) doesn't
/// matter since FeatureFlagService catches all of them the same way.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
