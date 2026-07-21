// Tier C — probabilistic income/payday prediction (see
// predictive_budgeting_engine_summary.md). Pure functions, no DB access —
// same style as forecaster.js's Tier A. Additive to the existing forecast:
// this does NOT feed into dailySafeToSpend's formula (see the plan's scope
// note) — an uncertain income prediction shouldn't silently change the
// number that tells a user how much they can safely spend today.

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const MIN_OCCURRENCES = 2;
const CONFIDENCE_MIN = 0.3;
const CONFIDENCE_MAX = 0.95;

// pg returns DATE columns as JS Dates built from LOCAL midnight, so reading
// them back with toISOString()/getUTC*() silently shifts a day whenever the
// server's local timezone is ahead of UTC — this bit forecaster.js's Tier A
// once already (see its toDateOnly comment). Normalizing to UTC-midnight
// once here avoids repeating that bug.
function toDateOnly(date) {
  const d = new Date(date);
  return new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
}

function normalizeSource(source) {
  return (source || '').trim().toLowerCase() || 'unlabeled';
}

function daysBetween(a, b) {
  return Math.abs(new Date(b) - new Date(a)) / MS_PER_DAY;
}

function mean(values) {
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

function stddev(values, avg) {
  return Math.sqrt(mean(values.map((v) => (v - avg) ** 2)));
}

// Groups income entries by normalized source (e.g. "Salary", "Freelance"),
// requiring >=2 entries per group to compute interval statistics — a
// single entry says nothing about cadence.
function detectRecurringIncome(incomeEntries) {
  const groups = new Map();

  for (const entry of incomeEntries) {
    const key = normalizeSource(entry.source);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(entry);
  }

  const recurringGroups = [];
  for (const [source, rows] of groups) {
    if (rows.length < MIN_OCCURRENCES) continue;

    const sorted = [...rows].sort((a, b) => new Date(a.received_date) - new Date(b.received_date));
    const amounts = sorted.map((r) => Number(r.amount));
    const avgAmount = mean(amounts);
    const amountStdDev = stddev(amounts, avgAmount);

    const intervals = [];
    for (let i = 1; i < sorted.length; i += 1) {
      intervals.push(daysBetween(sorted[i - 1].received_date, sorted[i].received_date));
    }
    const avgIntervalDays = mean(intervals);
    // A single interval (exactly 2 occurrences) has no variance to measure
    // — assume a modest 15% spread rather than claiming false certainty.
    const intervalStdDev = intervals.length > 1 ? stddev(intervals, avgIntervalDays) : avgIntervalDays * 0.15;

    recurringGroups.push({
      source,
      avgAmount,
      amountStdDev,
      avgIntervalDays,
      intervalStdDev,
      lastDate: sorted[sorted.length - 1].received_date,
      occurrences: sorted.length,
    });
  }

  return recurringGroups;
}

// The Bayesian piece: models the next payday as centered on
// lastDate + avgIntervalDays, with spread = intervalStdDev (a
// method-of-moments Normal approximation over observed intervals — a
// simple, honest treatment given this app's data volume, not a heavy stats
// library). confidence comes from the interval's coefficient of variation:
// tighter historical spacing between paydays means a tighter, more
// confident window.
function predictNextIncome(group) {
  const predictedDate = new Date(new Date(group.lastDate).getTime() + group.avgIntervalDays * MS_PER_DAY);
  const windowStart = new Date(predictedDate.getTime() - group.intervalStdDev * MS_PER_DAY);
  const windowEnd = new Date(predictedDate.getTime() + group.intervalStdDev * MS_PER_DAY);

  const coefficientOfVariation = group.avgIntervalDays > 0 ? group.intervalStdDev / group.avgIntervalDays : 1;
  const confidence = Math.min(CONFIDENCE_MAX, Math.max(CONFIDENCE_MIN, 1 - coefficientOfVariation));

  return {
    source: group.source,
    expectedAmount: Math.round(group.avgAmount * 100) / 100,
    amountRangeLow: Math.round(Math.max(0, group.avgAmount - group.amountStdDev) * 100) / 100,
    amountRangeHigh: Math.round((group.avgAmount + group.amountStdDev) * 100) / 100,
    windowStart: windowStart.toISOString().slice(0, 10),
    windowEnd: windowEnd.toISOString().slice(0, 10),
    confidence: Math.round(confidence * 100) / 100,
    occurrences: group.occurrences,
  };
}

// entries: last ~6 months of a user's income_log rows (amount, source,
// received_date). Returns one prediction per detected recurring income
// stream — an empty array if nothing recurring has been logged yet.
function buildIncomeForecast(entries) {
  const normalizedEntries = entries.map((e) => ({ ...e, received_date: toDateOnly(e.received_date) }));
  const groups = detectRecurringIncome(normalizedEntries);
  return groups.map((group) => predictNextIncome(group));
}

module.exports = {
  detectRecurringIncome,
  predictNextIncome,
  buildIncomeForecast,
};
