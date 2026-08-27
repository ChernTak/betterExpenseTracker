package com.example.expense_tracker

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Storage for the high-spend-area geofencing nudge, kept deliberately
 * separate from Flutter's own `flutter_secure_storage` (which backs the
 * app's real JWT storage) because that store is AES-encrypted via Android's
 * Keystore and isn't meant to be read from arbitrary native code without
 * replicating flutter_secure_storage's own undocumented file/key layout.
 *
 * Instead, when background-location consent is granted, the Dart side hands
 * a *copy* of the current token + API base URL over explicitly via
 * [MainActivity]'s "cacheCredentials" channel call, so [GeofenceReceiver] can
 * still authenticate a POST to the backend even when no Flutter engine is
 * running at all (the whole point of this feature). This copy is plain
 * (unencrypted) SharedPreferences — a deliberate, narrower-scope trade-off,
 * cleared via "clearGeofencingData" on logout or when the toggle is turned
 * off.
 */
object GeofencePrefs {
    private const val PREFS_NAME = "geofence_prefs"
    private const val KEY_TOKEN = "auth_token"
    private const val KEY_BASE_URL = "api_base_url"
    private const val KEY_LOCATIONS = "cached_locations"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun saveCredentials(context: Context, token: String, baseUrl: String) {
        prefs(context).edit()
            .putString(KEY_TOKEN, token)
            .putString(KEY_BASE_URL, baseUrl)
            .apply()
    }

    fun getToken(context: Context): String? = prefs(context).getString(KEY_TOKEN, null)

    fun getBaseUrl(context: Context): String? = prefs(context).getString(KEY_BASE_URL, null)

    /** [locations] is the raw list of maps as fetched from GET /api/nudge/high-risk-locations. */
    fun saveLocations(context: Context, locations: List<Map<String, Any?>>) {
        val array = JSONArray()
        for (loc in locations) {
            val obj = JSONObject()
            obj.put("location_id", loc["location_id"])
            obj.put("latitude", loc["latitude"])
            obj.put("longitude", loc["longitude"])
            obj.put("radius_meters", loc["radius_meters"])
            array.put(obj)
        }
        prefs(context).edit().putString(KEY_LOCATIONS, array.toString()).apply()
    }

    /** Used by [BootReceiver] to re-register without needing Dart/the backend reachable. */
    fun getCachedLocations(context: Context): List<GeofenceManager.LocationEntry> {
        val raw = prefs(context).getString(KEY_LOCATIONS, null) ?: return emptyList()
        val array = JSONArray(raw)
        val result = mutableListOf<GeofenceManager.LocationEntry>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            result.add(
                GeofenceManager.LocationEntry(
                    locationId = obj.getString("location_id"),
                    latitude = obj.getDouble("latitude"),
                    longitude = obj.getDouble("longitude"),
                    radiusMeters = obj.getInt("radius_meters"),
                )
            )
        }
        return result
    }

    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
    }
}
