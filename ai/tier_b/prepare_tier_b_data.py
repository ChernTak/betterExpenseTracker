"""Turns the raw Berka bank-transaction dataset into the daily per-account
features Tier B trains on (see train_tier_b.py).

Kaggle needs a login to download Berka, so grab it yourself and drop
trans.csv at ai/data/raw/berka/trans.csv:
    https://www.kaggle.com/datasets/marceloventura/the-berka-dataset

Optional - train_tier_b.py just falls back to synthetic data if you skip it.

Usage:
    python prepare_tier_b_data.py
"""

import sys
from pathlib import Path

import holidays
import numpy as np
import pandas as pd

RAW_PATH = Path(__file__).parent.parent / "data" / "raw" / "berka" / "trans.csv"
PROCESSED_PATH = Path(__file__).parent.parent / "data" / "processed" / "tier_b_training_data.csv"

# Berka's withdrawal-type labels - anything that isn't income (PRIJEM) counts as spend, same expenses-only framing this app uses (see forecaster.js).
WITHDRAWAL_TYPES = {"VYDAJ", "VYBER"}

# Must match FEATURE_COLUMNS in train_tier_b.py. Everything here is a ratio vs each account's own 90-day baseline, not a raw amount, since Berka's in Czech koruna and users spend in ringgit - a ratio-based model transfers, an absolute-amount one wouldn't. days_to_holiday uses Czech holidays here and Malaysian ones on the Dart side, same idea either way.
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
# Target is the whole remaining month's spend, not just one day - lets inference predict directly instead of walking forward and accumulating error.
TARGET_COLUMN = "remaining_month_ratio"

MIN_DAYS_OF_HISTORY = 30
MIN_BASELINE_FLOOR = 1.0  # avoids divide-by-zero for near-dormant accounts

# Clip ceilings come from real Berka percentiles (p90 ~38, p99 ~110) - 150 covers everything but the rare near-dormant account whose one transaction spikes the ratio (max seen was >37,000).
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

    # Reindex onto every calendar day so rolling windows track real elapsed time, not just the last N transactions regardless of gaps.
    full_range = pd.date_range(account_daily["date"].min(), account_daily["date"].max(), freq="D")
    amounts = account_daily.set_index("date")["amount"].reindex(full_range, fill_value=0.0)
    df = pd.DataFrame({"date": full_range, "amount": amounts.values})

    roll_3d_avg = df["amount"].shift(1).rolling(3, min_periods=1).mean()
    roll_7d_avg = df["amount"].shift(1).rolling(7, min_periods=1).mean()
    roll_14d_avg = df["amount"].shift(1).rolling(14, min_periods=1).mean()
    roll_14d_std = df["amount"].shift(1).rolling(14, min_periods=2).std().fillna(0)
    # Baseline every ratio (including the target) is expressed against - see the FEATURE_COLUMNS note above.
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

    # Berka has no real budget concept, so each account's own trailing 90-day average spend (scaled to a month) stands in for one.
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
