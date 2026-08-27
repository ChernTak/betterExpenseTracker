package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Android clears all Geofencing registrations on every device reboot — this
 * re-registers from the list [GeofenceManager.register] cached locally via
 * [GeofencePrefs], entirely independent of the backend or Dart being
 * reachable at boot time. No-ops if the user never enabled background
 * alerts (no cached locations means nothing to re-register).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val cached = GeofencePrefs.getCachedLocations(context)
        if (cached.isEmpty()) return

        GeofenceManager.register(context, cached) { success, error ->
            if (!success) {
                Log.e("BootReceiver", "Failed to re-register geofences after boot: $error")
            }
        }
    }
}
