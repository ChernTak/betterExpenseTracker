const alertModel = require('../models/alert.mode');
const userModel = require('../models/user.model');
const { sendPushNotification } = require('../utils/pushNotifier');
const { PRICE_TIER_MYR_BANDS, DEFAULT_PRICE_TIER, NUDGE_SAVINGS_THRESHOLD_MYR, MEAL_TIME_WINDOWS } = require('../config/dining');

// Host runs in Asia/Kuala_Lumpur (see config/db.js's DATE parser comment),
// so plain local Date getters already give Malaysia wall-clock time — no
// separate timezone conversion needed here.
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

// Called after recommendation.service has a ranked, in-budget venue list.
// Fires at most once per budget/day (dedupe via behavioral_alerts, same
// pattern as budget.service.checkAndSendAlerts) and only during a
// meal-time window, so it reads as a timely nudge rather than spam.
exports.maybeSendLossAversionNudge = async ({ userId, budgetId, mealCap, venues }) => {
  if (!budgetId || mealCap == null || venues.length === 0) return null;
  if (!isMealTimeNow()) return null;

  const cheapest = venues[0]; // venues are already price/distance-ranked by recommendation.service
  const savings = mealCap - estimatedPriceMYR(cheapest.priceTier);
  if (savings < NUDGE_SAVINGS_THRESHOLD_MYR) return null;

  const alreadySent = await alertModel.findRecentAlert(budgetId, 'location_nudge', startOfLocalDay());
  if (alreadySent.rows.length > 0) return null;

  const message = buildNudgeMessage(cheapest, savings);

  const userResult = await userModel.findById(userId);
  const fcmToken = userResult.rows[0]?.fcm_token;

  await sendPushNotification(fcmToken, {
    title: 'Nearby savings',
    body: message,
    data: { type: 'location_nudge', venueId: cheapest.id, budgetId },
  });

  await alertModel.createAlert({
    userId,
    budgetId,
    alertType: 'location_nudge',
    message,
  });

  return { venue: cheapest, savings, message };
};
