const mapsConfig = require('../config/maps');

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

// Hard spatial filter — keeps venues within radiusM, filling in distanceM via Haversine when Foursquare didn't provide it.
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

// Thin composition layer over config/maps.js: passes query/options through as-is, then applies the radius filter.
exports.findNearbyVenues = async (query, options) => {
  const { venues: rawVenues, providerStatus } = await mapsConfig.searchVenues(query, options);
  const venues = exports.filterWithinRadius(rawVenues, { lat: query.lat, lng: query.lng }, query.radiusM);
  return { venues, providerStatus };
};
