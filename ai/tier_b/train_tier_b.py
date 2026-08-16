"""Trains the Tier B (variable/discretionary spend) regressor described in
predictive_budgeting_engine_summary.md. Runs on-device (TFLite, inside the
Flutter app) rather than server-side — see
front-end/lib/services/tier_b_inference_service.dart.

Trains on ai/data/processed/tier_b_training_data.csv (produced by
prepare_tier_b_data.py from the real Berka dataset) if it exists; otherwise
falls back to synthetic Faker-generated personas so this still runs before
you've downloaded/prepared real data.

Every feature and the target are RATIOS relative to a 90-day trailing
baseline, not absolute currency amounts — see the FEATURE_COLUMNS comment in
prepare_tier_b_data.py for why (Berka is 1990s Czech koruna; this app's
users spend in Malaysian ringgit, and a model trained to predict an
absolute amount in one currency/scale would be meaningless applied to
another).

The target is the WHOLE REMAINING MONTH's spend (as of a given day), not a
single day's — so a single inference call replaces the old day-by-day
walk-forward loop.

NOTE on scope: an earlier version of this script predicted three quantiles
(p10/p50/p90) for an uncertainty range instead of one point estimate. That
was reverted after repeated real calibration failures during debugging
(clip-ceiling censoring, then quantile crossing, then the shared "base"
term collapsing p10 toward p50 under a monotonicity constraint) — each was
a genuine bug, fixed in turn, but quantile regression via this small
shared-trunk network kept finding new ways to miscalibrate. Rather than
keep iterating indefinitely, this fell back to the single-point-estimate
design that was already verified working end-to-end. Uncertainty
estimation is back on the list of things to solve properly, later.

Usage:
    pip install -r requirements.txt
    python prepare_tier_b_data.py   # optional — only if you've downloaded Berka
    python train_tier_b.py

Re-run any time you want to retrain (see also schedule_retrain.ps1 for
automating this). Rebuild the Flutter app afterward so it bundles the newly
saved .tflite file as its offline default — or rely on the OTA download path
(tier_b_inference_service.dart) to pick it up without a rebuild.
"""

from pathlib import Path

import holidays
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.metrics import mean_absolute_error
from sklearn.model_selection import train_test_split

PROCESSED_DATA_PATH = Path(__file__).parent.parent / "data" / "processed" / "tier_b_training_data.csv"

# Saved to both: ai/models/ is the versioned source of truth (also what the
# backend serves for OTA downloads — see insight.routes.js), front-end/assets/
# is the bundled offline-default copy Flutter ships inside the app itself.
MODEL_OUTPUT_PATHS = [
    Path(__file__).parent.parent / "models" / "tier_b_regressor.tflite",
    Path(__file__).parent.parent.parent / "front-end" / "assets" / "models" / "tier_b_regressor.tflite",
]

DAYS_PER_PERSONA = 200
MIN_BASELINE_FLOOR = 1.0

# Ceilings picked from real Berka percentiles (checked directly, not
# guessed): the unclipped 90th percentile of remaining_month_ratio is ~38
# and the 99th is ~110, so an earlier ceiling of 30 was clipping away the
# top ~10%+ of the real distribution.
ROLL_RATIO_CLIP_MAX = 15.0
TARGET_RATIO_CLIP_MAX = 150.0

# name, average daily spend, weekend multiplier, day-to-day noise, monthly budget
PERSONAS = [
    {"name": "student", "base": 15, "weekend_mult": 1.8, "noise": 6, "budget": 500},
    {"name": "young_professional", "base": 35, "weekend_mult": 1.5, "noise": 12, "budget": 1200},
    {"name": "high_earner", "base": 70, "weekend_mult": 1.2, "noise": 20, "budget": 3000},
]

# Must match FEATURE_COLUMNS/TARGET_COLUMN in prepare_tier_b_data.py.
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
TARGET_COLUMN = "remaining_month_ratio"

# Reused for the synthetic fallback path too, for consistency with the real
# (Berka/Czech) path — it's just a stand-in feature either way (see
# prepare_tier_b_data.py's FEATURE_COLUMNS comment).
_SYNTHETIC_HOLIDAYS = sorted(holidays.CZ(years=range(2024, 2027)).keys())
_HOLIDAY_DATES = np.array(_SYNTHETIC_HOLIDAYS, dtype="datetime64[D]")


def days_since_payday(d):
    # Synthetic proxy: this app has no real income/payday data, so paydays
    # are assumed to land on the 1st and 15th of the month.
    return min(abs(d.day - 1), abs(d.day - 15))


def days_to_holiday(dates):
    dates64 = dates.values.astype("datetime64[D]")
    idx = np.clip(np.searchsorted(_HOLIDAY_DATES, dates64), 1, len(_HOLIDAY_DATES) - 1)
    before, after = _HOLIDAY_DATES[idx - 1], _HOLIDAY_DATES[idx]
    dist_before = np.abs((dates64 - before).astype("timedelta64[D]").astype(int))
    dist_after = np.abs((after - dates64).astype("timedelta64[D]").astype(int))
    return np.minimum(dist_before, dist_after)


def remaining_month_amount(df, month_key):
    reverse_cumsum = (
        df.groupby(month_key)["amount"].apply(lambda s: s[::-1].cumsum()[::-1]).reset_index(level=0, drop=True)
    )
    return reverse_cumsum - df["amount"]


def generate_persona_timeseries(persona, rng):
    """Day-by-day synthetic generation so budget_friction and the payday
    boost can react to the persona's own running month-to-date spend."""
    dates = pd.date_range("2025-01-01", periods=DAYS_PER_PERSONA, freq="D")
    rows = []
    month_to_date = 0.0
    current_month = None

    for current_date in dates:
        if current_month != current_date.month:
            current_month = current_date.month
            month_to_date = 0.0

        is_weekend = current_date.dayofweek >= 5
        dsp = days_since_payday(current_date)

        base = persona["base"] * (persona["weekend_mult"] if is_weekend else 1.0)
        payday_boost = persona["base"] * 0.4 * max(0, 1 - dsp / 4)
        friction = min(month_to_date / persona["budget"], 2.0)
        friction_damping = max(0.5, 1 - friction * 0.25)

        noise = rng.normal(0, persona["noise"])
        amount = max(0.0, (base + payday_boost) * friction_damping + noise)

        rows.append({"date": current_date, "amount": amount})
        month_to_date += amount

    return pd.DataFrame(rows)


def engineer_synthetic_features(df, budget):
    df = df.sort_values("date").reset_index(drop=True)

    roll_3d_avg = df["amount"].shift(1).rolling(3, min_periods=1).mean()
    roll_7d_avg = df["amount"].shift(1).rolling(7, min_periods=1).mean()
    roll_14d_avg = df["amount"].shift(1).rolling(14, min_periods=1).mean()
    roll_14d_std = df["amount"].shift(1).rolling(14, min_periods=2).std().fillna(0)
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

    month_key = df["date"].dt.to_period("M")
    df["month_to_date_spend"] = df.groupby(month_key)["amount"].cumsum().shift(1).fillna(0)
    df["budget_friction"] = (df["month_to_date_spend"] / budget).clip(upper=2.0)

    df[TARGET_COLUMN] = (remaining_month_amount(df, month_key) / roll_90d_avg).clip(upper=TARGET_RATIO_CLIP_MAX)

    return df.dropna(subset=["roll_3d_ratio", TARGET_COLUMN]).reset_index(drop=True)


def load_training_data():
    if PROCESSED_DATA_PATH.exists():
        print(f"Training on real data from {PROCESSED_DATA_PATH}")
        return pd.read_csv(PROCESSED_DATA_PATH, parse_dates=["date"]).sort_values("date").reset_index(drop=True)

    print("No processed real dataset found at", PROCESSED_DATA_PATH)
    print("Training on synthetic personas instead (run prepare_tier_b_data.py first for real data).")

    rng = np.random.default_rng(42)
    frames = [engineer_synthetic_features(generate_persona_timeseries(p, rng), p["budget"]) for p in PERSONAS]
    return pd.concat(frames, ignore_index=True).sort_values("date").reset_index(drop=True)


def build_model(train_features):
    normalizer = tf.keras.layers.Normalization(axis=-1)
    normalizer.adapt(train_features.to_numpy())

    model = tf.keras.Sequential(
        [
            tf.keras.Input(shape=(len(FEATURE_COLUMNS),)),
            normalizer,
            tf.keras.layers.Dense(64, activation="relu"),
            tf.keras.layers.Dense(32, activation="relu"),
            tf.keras.layers.Dense(1),
        ]
    )
    # Huber (not MSE): remaining_month_ratio is heavily right-skewed even in
    # log-space, so a few large errors could otherwise dominate the gradient.
    model.compile(optimizer="adam", loss=tf.keras.losses.Huber(delta=1.0), metrics=["mae"])
    return model


def main():
    data = load_training_data()

    # Time-based split (not random) so the test set is always "the future"
    # relative to training, matching how the model will actually be used.
    split_idx = int(len(data) * 0.8)
    train, test = data.iloc[:split_idx], data.iloc[split_idx:]

    # remaining_month_ratio is heavily right-skewed (median ~5.5, but a
    # legitimate tail out to 150) — log1p compresses that range into
    # something the network can fit smoothly. Predictions are converted
    # back via expm1 (see below and tier_b_inference_service.dart, which
    # must do the same on-device).
    log_train_target = np.log1p(train[TARGET_COLUMN].to_numpy())

    # Random (not Keras' default unshuffled-last-10%) validation split.
    # `data` is globally time-sorted across ~4300 accounts, so an unshuffled
    # suffix is a narrow, non-representative slice (whichever accounts
    # happen to have late timestamps) rather than a real sample of the
    # training distribution — every earlier attempt at this model showed
    # val_loss looking great for ~2 epochs then climbing immediately after,
    # regardless of architecture, which pointed at the validation split
    # itself, not the model. The held-out TEST set above stays chronological
    # (it must, to genuinely test "the future"); only this inner train/val
    # split is shuffled.
    train_features, val_features, train_target, val_target = train_test_split(
        train[FEATURE_COLUMNS].to_numpy(), log_train_target, test_size=0.1, random_state=42
    )

    model = build_model(train[FEATURE_COLUMNS])
    model.fit(
        train_features,
        train_target,
        epochs=80,
        # A large batch size keeps steps/epoch reasonable regardless of
        # dataset size (real Berka-derived data is ~5M rows; synthetic is
        # ~500) — early stopping cuts training short once validation loss
        # stops improving.
        batch_size=2048,
        validation_data=(val_features, val_target),
        callbacks=[tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=8, restore_best_weights=True)],
        verbose=2,
    )

    log_predictions = model.predict(test[FEATURE_COLUMNS].to_numpy(), verbose=0).flatten()
    predictions = np.expm1(log_predictions)
    actual = test[TARGET_COLUMN].to_numpy()

    print(f"Trained on {len(train)} rows, tested on {len(test)} rows.")
    print(f"Test MAE: {mean_absolute_error(actual, predictions):.3f} (remaining-month-ratio units)")
    print(f"Mean actual ratio in test set: {actual.mean():.3f}")

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    for output_path in MODEL_OUTPUT_PATHS:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(tflite_model)
        print(f"Saved model to {output_path}")


if __name__ == "__main__":
    main()
