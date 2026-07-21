"""Reshapes the real Berka dataset (PKDD'99 Financial Dataset — ~1,000,000
real, anonymized Czech bank transactions across ~4,500 accounts) into the
daily per-account features Tier B trains on — see train_tier_b.py and
predictive_budgeting_engine_summary.md.

Berka isn't bundled with this repo — Kaggle requires an authenticated
download. Grab "The Berka Dataset" yourself and place its `trans.csv` at
ai/data/raw/berka/trans.csv before running this script:
    https://www.kaggle.com/datasets/marceloventura/the-berka-dataset

train_tier_b.py falls back to synthetic data if you skip this step, so it's
optional, not required for the pipeline to run.

Usage:
    python prepare_tier_b_data.py
"""

import sys
from pathlib import Path

import holidays
import numpy as np
import pandas as pd

RAW_PATH = Path(__file__).parent / "data" / "raw" / "berka" / "trans.csv"
PROCESSED_PATH = Path(__file__).parent / "data" / "processed" / "tier_b_training_data.csv"

# Berka's own withdrawal-type Czech labels — anything that isn't income
# ('PRIJEM') is treated as discretionary spend for this proxy. This app has
# no income tracking either (see forecaster.js), so "spend" here mirrors
# that same expenses-only framing.
WITHDRAWAL_TYPES = {"VYDAJ", "VYBER"}

# Must match FEATURE_COLUMNS in train_tier_b.py — the processed CSV's
# columns are what that script trains on directly.
#
# Everything here is a RATIO relative to each account's own trailing 90-day
# average, not an absolute currency amount. Berka's amounts are in 1990s
# Czech koruna; this app's users spend in Malaysian ringgit — a model that
# predicts an absolute amount learned from one currency/scale would be
# meaningless applied to a completely different one. Ratios relative to an
# account's own baseline are scale-invariant, so the same trained model
# transfers sensibly regardless of the absolute numbers involved. The
# on-device Dart inference (tier_b_inference_service.dart) must compute the
# same ratios (relative to that real user's own roll_90d_avg) and multiply
# the model's predicted ratio back by that baseline to get a real amount.
#
# days_to_holiday uses Czech public holidays here (this is Czech data) and
# hardcoded Malaysian fixed-date holidays on the Dart side — the actual
# calendar dates differ by country, but the *feature concept* ("proximity
# to a holiday changes spending") transfers, same reasoning already used
# for days_since_payday.
FEATURE_COLUMNS = [
    "roll_3d_ratio",
    "roll_7d_ratio",
    "roll_14d_ratio",
    "day_of_week",
    "is_weekend",
    "days_since_payday",
    "budget_friction",
    "is_month_end",
    "spend_volatility_ratio",
    "days_to_holiday",
    "days_remaining_ratio",
]
# The target is now the WHOLE REMAINING MONTH's spend (as of that row's
# day), not a single day's — see remaining_month_ratio() below. This lets
# inference make one direct prediction instead of walking forward
# day-by-day and accumulating error along the way.
TARGET_COLUMN = "remaining_month_ratio"

MIN_DAYS_OF_HISTORY = 30
MIN_BASELINE_FLOOR = 1.0  # avoids divide-by-zero for near-dormant accounts

# Ratios are clipped to a sane range for the same reason budget_friction
# already was: a near-dormant account (baseline pinned at MIN_BASELINE_FLOOR)
# hitting one ordinary-sized withdrawal can otherwise produce a ratio in the
# tens of thousands, which dominates training and prevents the model from
# learning the typical-case pattern at all.
# Ceilings picked from real Berka percentiles (checked directly, not
# guessed): the unclipped 90th percentile of remaining_month_ratio is ~38
# and the 99th is ~110, so an earlier, unverified ceiling of 30 was
# clipping away the top ~10%+ of the real distribution — including the
# model's entire p90 region, which is why the first trained model's
# quantiles came out badly miscalibrated. 150 sits just above the 99th
# percentile; only genuinely pathological cases (a near-dormant account,
# baseline pinned at MIN_BASELINE_FLOOR, hit by one real transaction —
# max observed was >37,000) get clipped now.
ROLL_RATIO_CLIP_MAX = 15.0
TARGET_RATIO_CLIP_MAX = 150.0

CZ_HOLIDAYS = sorted(holidays.CZ(years=range(1993, 1998)).keys())
_HOLIDAY_DATES = np.array(CZ_HOLIDAYS, dtype="datetime64[D]")


def parse_berka_date(yymmdd):
    # Berka dates are YYMMDD, e.g. 930101 -> 1993-01-01. The dataset only
    # spans 1993-1996, so there's no century-rollover ambiguity.
    digits = str(int(yymmdd)).zfill(6)
    return pd.Timestamp(year=1900 + int(digits[0:2]), month=int(digits[2:4]), day=int(digits[4:6]))


def days_since_payday(d):
    return min(abs(d.day - 1), abs(d.day - 15))


def days_to_holiday(dates):
    """Vectorized nearest-holiday distance (in days) for a Series of dates."""
    dates64 = dates.values.astype("datetime64[D]")
    idx = np.searchsorted(_HOLIDAY_DATES, dates64)
    idx = np.clip(idx, 1, len(_HOLIDAY_DATES) - 1)
    before = _HOLIDAY_DATES[idx - 1]
    after = _HOLIDAY_DATES[idx]
    dist_before = np.abs((dates64 - before).astype("timedelta64[D]").astype(int))
    dist_after = np.abs((after - dates64).astype("timedelta64[D]").astype(int))
    return np.minimum(dist_before, dist_after)


def remaining_month_amount(df, month_key):
    """For each row, the sum of `amount` on every LATER day in the same
    calendar month (excludes the row's own day)."""
    reverse_cumsum = (
        df.groupby(month_key)["amount"].apply(lambda s: s[::-1].cumsum()[::-1]).reset_index(level=0, drop=True)
    )
    return reverse_cumsum - df["amount"]


def load_raw():
    if not RAW_PATH.exists():
        sys.exit(
            f"Missing {RAW_PATH}.\n"
            "Download 'The Berka Dataset' from Kaggle and place trans.csv there:\n"
            "  https://www.kaggle.com/datasets/marceloventura/the-berka-dataset\n"
            "(train_tier_b.py works fine on synthetic data if you skip this.)"
        )

    df = pd.read_csv(RAW_PATH, sep=None, engine="python")
    df.columns = [c.strip().lower() for c in df.columns]

    required = {"account_id", "date", "type", "amount"}
    missing = required - set(df.columns)
    if missing:
        sys.exit(
            f"trans.csv is missing expected column(s): {sorted(missing)}. "
            f"Found columns: {list(df.columns)}. This script assumes the "
            "standard Berka/PKDD'99 schema (account_id, date, type, amount, ...) "
            "— adjust the column names above if your Kaggle mirror differs."
        )
    return df


def build_daily_withdrawals(df):
    df = df[df["type"].isin(WITHDRAWAL_TYPES)].copy()
    df["date"] = df["date"].apply(parse_berka_date)
    return df.groupby(["account_id", "date"], as_index=False)["amount"].sum()


def engineer_features(account_daily):
    account_daily = account_daily.sort_values("date").reset_index(drop=True)

    # Reindex onto every calendar day (0-spend where there's no transaction)
    # so rolling windows reflect true elapsed time, not just "the last N
    # transactions" regardless of gaps.
    full_range = pd.date_range(account_daily["date"].min(), account_daily["date"].max(), freq="D")
    amounts = account_daily.set_index("date")["amount"].reindex(full_range, fill_value=0.0)
    df = pd.DataFrame({"date": full_range, "amount": amounts.values})

    roll_3d_avg = df["amount"].shift(1).rolling(3, min_periods=1).mean()
    roll_7d_avg = df["amount"].shift(1).rolling(7, min_periods=1).mean()
    roll_14d_avg = df["amount"].shift(1).rolling(14, min_periods=1).mean()
    roll_14d_std = df["amount"].shift(1).rolling(14, min_periods=2).std().fillna(0)
    # The baseline every ratio (including the target) is expressed against —
    # see the FEATURE_COLUMNS comment above for why this must be a ratio,
    # not an absolute amount.
    roll_90d_avg = df["amount"].shift(1).rolling(90, min_periods=14).mean().clip(lower=MIN_BASELINE_FLOOR)

    df["roll_3d_ratio"] = (roll_3d_avg / roll_90d_avg).clip(upper=ROLL_RATIO_CLIP_MAX)
    df["roll_7d_ratio"] = (roll_7d_avg / roll_90d_avg).clip(upper=ROLL_RATIO_CLIP_MAX)
    df["roll_14d_ratio"] = (roll_14d_avg / roll_90d_avg).clip(upper=ROLL_RATIO_CLIP_MAX)
    df["spend_volatility_ratio"] = (roll_14d_std / roll_90d_avg).clip(upper=ROLL_RATIO_CLIP_MAX)
    df["day_of_week"] = df["date"].dt.dayofweek
    df["is_weekend"] = (df["day_of_week"] >= 5).astype(int)
    df["days_since_payday"] = df["date"].apply(days_since_payday)
    df["days_to_holiday"] = days_to_holiday(df["date"])

    days_in_month = df["date"].dt.days_in_month
    day_of_month = df["date"].dt.day
    df["is_month_end"] = ((days_in_month - day_of_month) < 3).astype(int)
    df["days_remaining_ratio"] = (days_in_month - day_of_month) / days_in_month

    # Berka has no explicit budget concept, so each account's own trailing
    # 90-day average spend (scaled to a month) stands in for "their typical
    # monthly budget" — an approximation, not a real budget figure.
    approx_monthly_budget = (roll_90d_avg * 30).clip(lower=MIN_BASELINE_FLOOR)
    month_key = df["date"].dt.to_period("M")
    month_to_date = df.groupby(month_key)["amount"].cumsum().shift(1).fillna(0)
    df["budget_friction"] = (month_to_date / approx_monthly_budget).clip(upper=2.0)

    df[TARGET_COLUMN] = (remaining_month_amount(df, month_key) / roll_90d_avg).clip(upper=TARGET_RATIO_CLIP_MAX)

    return df.dropna(subset=["roll_3d_ratio", "budget_friction", TARGET_COLUMN])


def main():
    raw = load_raw()
    daily = build_daily_withdrawals(raw)

    frames = []
    for _, group in daily.groupby("account_id"):
        if len(group) < MIN_DAYS_OF_HISTORY:
            continue
        frames.append(engineer_features(group))

    if not frames:
        sys.exit("No account had enough history after filtering — check trans.csv contents.")

    data = pd.concat(frames, ignore_index=True)
    PROCESSED_PATH.parent.mkdir(parents=True, exist_ok=True)
    data[["date", "amount", TARGET_COLUMN] + FEATURE_COLUMNS].to_csv(PROCESSED_PATH, index=False)
    print(f"Wrote {len(data)} rows from {len(frames)} accounts to {PROCESSED_PATH}")


if __name__ == "__main__":
    main()
