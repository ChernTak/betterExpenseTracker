"""Evaluates Tier B prediction accuracy against real outcomes — run this
manually once a month has closed (a still-open month's "actual" total is a
moving target, so it's excluded).

Compares each row in forecast_predictions_log
(back-end/database/migrations/022_forecast_predictions_log.sql, written by
tier_b_inference_service.dart via POST /api/insights/predictions) against
that user's actual total expenses for the same month, reporting:
  - point accuracy: MAE of the p50 prediction vs. actual
  - calibration: how often actual spend fell within [p10, p90] (should be
    close to 80% if the quantiles are well-calibrated)

This is a report script, not a live dashboard — matches this project's
existing "you run it yourself" pattern for anything monitoring-adjacent.

Usage:
    python evaluate_tier_b.py
"""

import os
from datetime import date
from pathlib import Path

import numpy as np
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

BACKEND_ENV_PATH = Path(__file__).parent.parent / "back-end" / ".env"


def get_connection():
    load_dotenv(BACKEND_ENV_PATH)
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ["DB_PORT"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
    )


def main():
    today = date.today()
    conn = get_connection()

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            SELECT prediction_id, user_id, month, year, predicted_p10, predicted_p50, predicted_p90, model_version
            FROM forecast_predictions_log
            WHERE (year < %s) OR (year = %s AND month < %s)
            ORDER BY year, month
            """,
            (today.year, today.year, today.month),
        )
        predictions = cur.fetchall()

        if not predictions:
            print("No predictions from closed months to evaluate yet.")
            conn.close()
            return

        errors = []
        within_range = 0
        for row in predictions:
            cur.execute(
                """
                SELECT COALESCE(SUM(amount), 0) AS total
                FROM expenses
                WHERE user_id = %s
                  AND EXTRACT(MONTH FROM transaction_date) = %s
                  AND EXTRACT(YEAR FROM transaction_date) = %s
                """,
                (row["user_id"], row["month"], row["year"]),
            )
            actual = float(cur.fetchone()["total"])

            p10, p50, p90 = (float(row["predicted_p10"]), float(row["predicted_p50"]), float(row["predicted_p90"]))
            errors.append(abs(actual - p50))
            in_range = p10 <= actual <= p90
            within_range += int(in_range)

            print(
                f"  {row['year']}-{row['month']:02d} user={row['user_id']}: "
                f"predicted p10/p50/p90 = {p10:.2f}/{p50:.2f}/{p90:.2f}, actual = {actual:.2f} "
                f"({'within range' if in_range else 'OUTSIDE range'})"
            )

    conn.close()

    print(f"\nEvaluated {len(predictions)} prediction(s) from closed months.")
    print(f"Median (p50) MAE: RM {np.mean(errors):.2f}")
    print(
        f"Calibration: actual spend fell within [p10, p90] {within_range}/{len(predictions)} times "
        f"({within_range / len(predictions):.0%} — target ~80%)"
    )


if __name__ == "__main__":
    main()
