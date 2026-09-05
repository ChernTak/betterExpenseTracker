const alertModel = require('../models/alert.mode');
const userModel = require('../models/user.model');
const highRiskLocationModel = require('../models/highRiskLocation.model');
const { sendPushNotification } = require('../utils/pushNotifier');
const { PRICE_TIER_MYR_BANDS, DEFAULT_PRICE_TIER, NUDGE_SAVINGS_THRESHOLD_MYR, MEAL_TIME_WINDOWS } = require('../config/dining');

// Host runs in Asia/Kuala_Lumpur, so plain local Date getters already give Malaysia wall-clock time.
function isMealTimeNow() {
  const hour = new Date().getHours();
  return MEAL_TIME_WINDOWS.some((w) => hour >= w.startHour && hour < w.endHour);
}

function estimatedPriceMYR(priceTier) {
  const band = PRICE_TIER_MYR_BANDS[priceTier ?? DEFAULT_PRICE_TIER] || PRICE_TIER_MYR_BANDS[DEFAULT_PRICE_TIER];
  return band.max === Infinity ? band.min : (band.min + band.max) / 2;
}

function startOfLocalDay() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

// Section 2.4.3-style loss-framed copy, same idea as
// budget.service.js#buildAlertMessage: state what's at stake, not just a fact.
function buildNudgeMessage(venue, savings) {
  const distanceLabel = venue.distanceM < 1000 ? `${Math.round(venue.distanceM)}m` : `${(venue.distanceM / 1000).toFixed(1)}km`;
  return `Save RM${savings.toFixed(0)} by eating at ${venue.name} — ${distanceLabel} away.`;
}

// Fires at most once per budget/day and only during a meal-time window, so it reads as timely rather than spam.
exports.maybeSendLossAversionNudge = async ({ userId, budgetId, mealCap, venues }) => {
  if (!budgetId || mealCap == null || venues.length === 0) return null;
  if (!isMealTimeNow()) return null;

  const cheapest = venues[0]; // venues are already price/distance-ranked by recommendation.service
  const savings = mealCap - estimatedPriceMYR(cheapest.priceTier);
  if (savings < NUDGE_SAVINGS_THRESHOLD_MYR) return null;

  const alreadySent = await alertModel.findRecentAlert(budgetId, 'location_nudge', startOfLocalDay());
  if (alreadySent.rows.length > 0) return null;

  const message = buildNudgeMessage(cheapest, savings);

  const alertResult = await alertModel.createAlert({
    userId,
    budgetId,
    alertType: 'location_nudge',
    message,
  });
  const alertId = alertResult.rows[0].alert_id;

  const userResult = await userModel.findById(userId);
  const fcmToken = userResult.rows[0]?.fcm_token;

  await sendPushNotification(fcmToken, {
    title: 'Nearby savings',
    body: message,
    data: { type: 'location_nudge', venueId: cheapest.id, budgetId, alertId },
  });

  return { venue: cheapest, savings, message };
};

// Fires the moment geofencing reports entry into a high-spend location, before any purchase — unlike checkAndSendAlerts which fires after an expense is saved. Reuses the 'location_nudge' alert_type already wired to the frontend.
exports.maybeSendHighRiskLocationNudge = async ({ userId, locationId }) => {
  const locationResult = await highRiskLocationModel.getById(locationId);
  const location = locationResult.rows[0];
  if (!location) return null;

  // Dedupe once per user per location per day so walking past the same mall repeatedly doesn't spam nudges.
  const alreadySent = await alertModel.findRecentLocationAlert(
    userId,
    locationId,
    'location_nudge',
    startOfLocalDay(),
  );
  if (alreadySent.rows.length > 0) return null;

  const message = `You're near ${location.name} — sometimes a spot where spending adds up. Want to line something up on your Wishlist before you decide?`;

  const alertResult = await alertModel.createAlert({
    userId,
    locationId,
    alertType: 'location_nudge',
    message,
  });
  const alertId = alertResult.rows[0].alert_id;

  const userResult = await userModel.findById(userId);
  const fcmToken = userResult.rows[0]?.fcm_token;

  await sendPushNotification(fcmToken, {
    title: 'Heads up',
    body: message,
    data: { type: 'location_nudge', locationId, alertId },
  });

  return { location, message };
};

// GET /api/nudge/high-risk-locations — reference data for the Android app to
// register as geofences once background-location consent is granted.
exports.listHighRiskLocations = async (req, res) => {
  try {
    const result = await highRiskLocationModel.listAll();
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('List high-risk locations error', err);
    return res.status(500).json({ message: 'Failed to fetch high-risk locations', error: err.message });
  }
};

// POST /api/nudge/location-entered — called by the native Android geofencing
// bridge when a registered geofence fires an ENTER transition.
exports.handleLocationEntered = async (req, res) => {
  const { locationId } = req.body;
  if (!locationId) {
    return res.status(400).json({ message: 'locationId is required' });
  }

  try {
    const result = await exports.maybeSendHighRiskLocationNudge({ userId: req.user.userId, locationId });
    if (result === null) {
      return res.status(200).json({ message: 'No nudge sent (unknown location or already sent today)' });
    }
    return res.status(201).json({ message: 'Location nudge sent', data: result });
  } catch (err) {
    console.error('Handle location entered error', err);
    return res.status(500).json({ message: 'Failed to process location entry', error: err.message });
  }
};
