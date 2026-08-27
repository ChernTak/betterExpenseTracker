package com.example.expense_tracker

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

/**
 * Registers/unregisters the high-spend-area geofences with Google Play
 * Services' native geofencing (GeofencingClient) — the OS-level mechanism
 * that delivers an ENTER transition to [GeofenceReceiver] even if this app's
 * process has been killed, without needing a persistent foreground service.
 *
 * Caller must already hold ACCESS_FINE_LOCATION + ACCESS_BACKGROUND_LOCATION
 * (checked on the Dart side via permission_handler before this is invoked —
 * [SuppressLint] here just silences the compiler's static permission lint,
 * not an actual bypass).
 */
object GeofenceManager {
    data class LocationEntry(
        val locationId: String,
        val latitude: Double,
        val longitude: Double,
        val radiusMeters: Int,
    )

    private fun client(context: Context): GeofencingClient =
        LocationServices.getGeofencingClient(context)

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }

    @SuppressLint("MissingPermission")
    fun register(context: Context, locations: List<LocationEntry>, onResult: (Boolean, String?) -> Unit) {
        // OS hard cap is 100 geofences on Android — well above the seeded
        // Klang Valley mall/department-store list, but capped defensively.
        val geofences = locations.take(100).map { loc ->
            Geofence.Builder()
                .setRequestId(loc.locationId)
                .setCircularRegion(loc.latitude, loc.longitude, loc.radiusMeters.toFloat())
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                .build()
        }

        if (geofences.isEmpty()) {
            onResult(true, null)
            return
        }

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofences(geofences)
            .build()

        client(context).addGeofences(request, pendingIntent(context))
            .addOnSuccessListener {
                GeofencePrefs.saveLocations(context, locations.map {
                    mapOf(
                        "location_id" to it.locationId,
                        "latitude" to it.latitude,
                        "longitude" to it.longitude,
                        "radius_meters" to it.radiusMeters,
                    )
                })
                onResult(true, null)
            }
            .addOnFailureListener { e -> onResult(false, e.message) }
    }

    fun unregister(context: Context, onResult: (Boolean, String?) -> Unit) {
        client(context).removeGeofences(pendingIntent(context))
            .addOnSuccessListener {
                GeofencePrefs.clear(context)
                onResult(true, null)
            }
            .addOnFailureListener { e -> onResult(false, e.message) }
    }
}
