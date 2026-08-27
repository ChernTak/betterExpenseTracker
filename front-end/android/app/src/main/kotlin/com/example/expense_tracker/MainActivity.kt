package com.example.expense_tracker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Dart-facing bridge for the high-spend-area geofencing nudge (see
 * geofence_service.dart, GeofenceManager.kt, GeofencePrefs.kt,
 * GeofenceReceiver.kt). All the actual work happens natively so it keeps
 * working even when the Flutter engine isn't running — this channel only
 * needs to exist for the foreground actions (enabling the feature,
 * registering the current location list, disabling it again).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.example.expense_tracker/geofencing"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "cacheCredentials" -> {
                    val token = call.argument<String>("token")
                    val baseUrl = call.argument<String>("baseUrl")
                    if (token == null || baseUrl == null) {
                        result.error("INVALID_ARGS", "token and baseUrl are required", null)
                        return@setMethodCallHandler
                    }
                    GeofencePrefs.saveCredentials(applicationContext, token, baseUrl)
                    result.success(null)
                }

                "registerGeofences" -> {
                    @Suppress("UNCHECKED_CAST")
                    val rawLocations = call.argument<List<Map<String, Any>>>("locations") ?: emptyList()
                    val entries = rawLocations.map {
                        GeofenceManager.LocationEntry(
                            locationId = it["locationId"] as String,
                            latitude = (it["latitude"] as Number).toDouble(),
                            longitude = (it["longitude"] as Number).toDouble(),
                            radiusMeters = (it["radiusMeters"] as Number).toInt(),
                        )
                    }
                    GeofenceManager.register(applicationContext, entries) { success, error ->
                        if (success) result.success(null) else result.error("REGISTER_FAILED", error, null)
                    }
                }

                "clearGeofencingData" -> {
                    GeofenceManager.unregister(applicationContext) { success, error ->
                        if (success) result.success(null) else result.error("UNREGISTER_FAILED", error, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
