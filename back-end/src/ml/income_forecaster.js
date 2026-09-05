// Tier C probabilistic income/payday prediction, pure functions. Additive only — deliberately not fed into dailySafeToSpend, since an uncertain income guess shouldn't silently change that number.

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const MIN_OCCURRENCES = 2;
const CONFIDENCE_MIN = 0.3;
const CONFIDENCE_MAX = 0.95;

// pg's DATE columns are local-midnight JS Dates that shift a day under getUTC*()/toISOString() in a UTC+8 host (already bit forecaster.js's Tier A); normalize to UTC-midnight once here.
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

// Groups income by normalized source, requiring >=2 entries per group since a single entry says nothing about cadence.
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

// Models next payday as a method-of-moments Normal approximation centered on lastDate + avgIntervalDays, spread = intervalStdDev; confidence comes from the interval's coefficient of variation — tighter spacing means more confident.
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

// entries: last ~6 months of income_log rows (amount, source, received_date); returns one prediction per recurring stream, empty if none detected yet.
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
