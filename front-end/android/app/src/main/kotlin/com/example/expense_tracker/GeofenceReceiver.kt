package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Fired directly by Google Play Services on a geofence ENTER transition —
 * this runs even if the Flutter engine / whole app process is dead, which is
 * the entire point of using native geofencing instead of a Flutter package
 * (see the plan's comparison of easy_geofencing vs flutter_background_geolocation
 * vs this approach).
 *
 * Deliberately does NOT try to wake/bridge into Dart: it POSTs straight to
 * POST /api/nudge/location-entered using the token cached by
 * [GeofencePrefs] (via MainActivity's "cacheCredentials" channel call), so
 * this works with zero dependency on the Flutter engine being alive. The
 * actual user-visible nudge arrives through the existing FCM push
 * notification the backend sends from that same endpoint — tapping it opens
 * the app via the existing notification_handler.dart flow, unchanged.
 */
class GeofenceReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "GeofenceReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) {
            Log.e(TAG, "Geofencing error code: ${event.errorCode}")
            return
        }
        if (event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return

        val token = GeofencePrefs.getToken(context)
        val baseUrl = GeofencePrefs.getBaseUrl(context)
        if (token == null || baseUrl == null) {
            Log.w(TAG, "No cached credentials — user hasn't enabled background alerts, or logged out since.")
            return
        }

        val triggeringIds = event.triggeringGeofences?.map { it.requestId } ?: return

        // BroadcastReceiver.onReceive must return quickly (~10s budget from
        // the OS) but network I/O can't run on this thread — a short-lived
        // background thread per entry is enough for a single small POST and
        // avoids pulling in a coroutines/WorkManager dependency for this.
        Thread {
            for (locationId in triggeringIds) {
                postLocationEntered(baseUrl, token, locationId)
            }
        }.start()
    }

    private fun postLocationEntered(baseUrl: String, token: String, locationId: String) {
        try {
            val url = URL("$baseUrl/api/nudge/location-entered")
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.doOutput = true
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000

            val body = JSONObject().put("locationId", locationId).toString()
            connection.outputStream.use { it.write(body.toByteArray()) }

            val status = connection.responseCode
            Log.i(TAG, "location-entered POST for $locationId -> HTTP $status")
            connection.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to report geofence entry for $locationId", e)
        }
    }
}
