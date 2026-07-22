const EARTH_RADIUS_M = 6371000;

function toRadians(deg) {
  return (deg * Math.PI) / 180;
}

// Great-circle distance between two lat/lng points, in metres.
exports.distanceMeters = (lat1, lng1, lat2, lng2) => {
  const dLat = toRadians(lat2 - lat1);
  const dLng = toRadians(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_M * c;
};

// Hard spatial filter — keeps only venues within radiusM of (lat, lng),
// and fills in distanceM via Haversine for any venue Foursquare didn't
// already annotate with its own distance.
exports.filterWithinRadius = (venues, { lat, lng }, radiusM) => {
  return venues
    .map((venue) => {
      const distanceM =
        venue.distanceM ?? (venue.lat != null && venue.lng != null
          ? exports.distanceMeters(lat, lng, venue.lat, venue.lng)
          : Infinity);
      return { ...venue, distanceM };
    })
    .filter((venue) => venue.distanceM <= radiusM);
};
