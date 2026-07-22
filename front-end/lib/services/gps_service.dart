import 'package:geolocator/geolocator.dart';

/// Wraps `geolocator` for the food-recommendation feature. Denial/disabled
/// service returns null rather than throwing — same "don't crash the flow"
/// pattern as fcm_service.dart's permission handling.
class GpsService {
  Future<Position?> getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
    } catch (_) {
      return null;
    }
  }
}
