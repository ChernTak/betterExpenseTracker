# AI module — expense auto-categorization

Trains a model that predicts an expense's category (the same
`kExpenseCategories` enum the app already uses: `food_dining`,
`transport`, `shopping`, `groceries`, `entertainment`, `health_medical`,
`utilities`, `education`, `travel`, `personal_care`, `subscription`,
`investment`, `other`) from its merchant name / description. Backs the
not-yet-built `ml_categorizer_ds.dart` on the Flutter side (FR — auto
category suggestion).

## Folder layout

```
ai/
  data/
    raw/          # datasets as downloaded/exported, untouched (gitignored — see below)
    processed/    # cleaned + relabeled data, ready to train on (gitignored)
  models/         # trained model artifacts (.pkl / .joblib / .tflite) (gitignored)
  requirements.txt
```

`data/raw/`, `data/processed/`, and `models/` are gitignored — datasets
and trained binaries don't belong in git history (they get large fast,
and datasets are usually re-downloadable). Only the folder structure
itself (via `.gitkeep` files) and this README are tracked.

## Where to put a dataset

Drop whatever you download/export straight into `ai/data/raw/`,
unmodified — e.g. `ai/data/raw/personal_expense_classification.csv`.
Do any cleaning/relabeling in a script that reads from `data/raw/` and
writes to `data/processed/`, so the original download is never
mutated and can be regenerated from scratch if the cleaning logic
changes.

## Dataset options

Two real, currently available candidates (found via web search, not
verified in depth — check each one's license/fields before committing
to it):

- **Personal Expense Classification Dataset** (Kaggle) — merchant +
  description → category, categories close to this app's own set.
  Best first choice: smallest gap between the dataset's labels and
  `kExpenseCategories`.
  https://www.kaggle.com/datasets/sahideseker/personal-expense-classification-dataset
- **Credit Card Transactions Dataset** (Kaggle) — ~1.85M real
  transactions with merchant + category fields. Much larger and more
  realistic, but its categories will need remapping onto
  `kExpenseCategories` and it'll need cleaning before use.
  https://www.kaggle.com/datasets/priyamchoksi/credit-card-transactions-dataset

A third option once the app has real usage: export labeled expenses
from the Postgres `expenses` table (merchant_name + category the user
actually picked) as first-party training data — this will match your
own users' spending patterns far better than any public dataset, but
needs enough real usage first to have volume.

## Suggested approach

A lightweight TF-IDF vectorizer (over merchant name + description)
feeding a Logistic Regression or LinearSVC classifier is a good fit
here — this is a short-text classification problem over a small,
fixed label set, not something that needs a deep learning stack or a
GPU. `requirements.txt` reflects that (pandas + scikit-learn + joblib
for saving the trained model).

## Tier B spend forecast (prepare_tier_b_data.py / train_tier_b.py)

A second, unrelated model lives in this same folder: the "Tier B"
variable/discretionary spend regressor from
`predictive_budgeting_engine_summary.md`, which feeds the end-of-month
forecast on the Insights tab. Unlike the categorization model above, this
one runs **on-device** — the trained model is executed locally by
`front-end/lib/services/tier_b_inference_service.dart`; the Node backend
(`back-end/src/ml/forecaster.js`) only ever computes the JS heuristic
fallback, never a trained prediction.

It predicts the **whole remaining month's spend** (as of "today") as a
single point estimate, expressed as a **ratio relative to that account's
own trailing 90-day average** (not an absolute currency amount — see the
comment in `prepare_tier_b_data.py` for why), from 11 features: rolling
3/7/14-day spend ratios, spend volatility, day-of-week, a synthetic
payday-proximity signal, days to the nearest public holiday, whether today
is near month-end, days remaining in the month, and how close the account
is to its monthly budget ("budget friction").

Note on scope: an earlier version of this model predicted three quantiles
(p10/p50/p90) for an uncertainty range instead of one number. That was
reverted after repeated, genuine calibration failures during debugging —
each one a real, measured bug (a too-tight clip ceiling censoring the top
~10%+ of the target distribution; quantile crossing; a shared "base" term
collapsing p10 toward p50 under a monotonicity constraint) — rather than
keep iterating indefinitely on a small shared-trunk network that kept
finding new ways to miscalibrate. Uncertainty estimation is deferred, not
abandoned; see `train_tier_b.py`'s module docstring for the full history
if picking this back up.

- `prepare_tier_b_data.py` — reshapes the real **Berka dataset** (PKDD'99
  Financial Dataset — ~1,000,000 real, anonymized Czech bank transactions
  across ~4,500 accounts) into daily per-account features. Kaggle requires
  an authenticated download, so grab it yourself and place `trans.csv` at
  `ai/data/raw/berka/trans.csv` before running this script:
  https://www.kaggle.com/datasets/marceloventura/the-berka-dataset
  Optional — `train_tier_b.py` falls back to synthetic data if you skip it.
- `train_tier_b.py` — trains a small Keras neural net (with an embedded
  normalization layer, so the exported model handles feature scaling
  itself; Huber loss on a log1p-transformed target, since
  remaining_month_ratio is heavily right-skewed) on
  `data/processed/tier_b_training_data.csv` if it exists, otherwise on
  synthetic Faker/numpy-generated personas. Converts the result to TFLite
  and saves it to **both** `ai/models/tier_b_regressor.tflite` (versioned
  source of truth — also what the backend serves for OTA download, see
  below) and `front-end/assets/models/tier_b_regressor.tflite` (the
  bundled offline-default copy Flutter ships inside the app itself).
- `evaluate_tier_b.py` — run manually once a month has closed: compares
  logged on-device predictions
  (`forecast_predictions_log`, written via `POST /api/insights/predictions`)
  against that user's real total spend for the month, reporting the
  prediction's MAE and how often actual spend fell within [p10, p90] (a
  degenerate check right now since p10=p50=p90 for a point-estimate model —
  becomes meaningful again if quantiles come back). A report script, not a
  live dashboard.
- `schedule_retrain.ps1` — registers a weekly Windows Task Scheduler job
  that re-runs `prepare_tier_b_data.py` + `train_tier_b.py` so the model
  stays fresh as more/better data becomes available. **This only keeps
  the model fresh on this machine and what the backend can hand out** — it
  doesn't rebuild/redistribute the Flutter app; see "OTA model delivery"
  below for how already-installed apps actually get the update.

```bash
python -m venv .venv
.venv\Scripts\activate          # or: source .venv/bin/activate
pip install -r requirements.txt

python prepare_tier_b_data.py   # optional — only if you've downloaded Berka
python train_tier_b.py          # run once (or whenever you want to retrain)
.\schedule_retrain.ps1          # optional — automates the above two on a weekly schedule
```

### OTA model delivery

The `.tflite` bundled into the Flutter app (`assets/models/`) is only the
**offline default**. On startup, `tier_b_inference_service.dart` checks
`GET /api/insights/model/version` (throttled to once/day) against its own
last-downloaded version; if the backend has a newer one (served from
`ai/models/tier_b_regressor.tflite` — whatever `train_tier_b.py` most
recently wrote there), it downloads it via `GET /api/insights/model/file`
and caches it in the app's local documents directory, using that instead of
the bundled asset from then on. This means retraining
(`schedule_retrain.ps1` or a manual run) reaches already-installed apps
without needing a new app release — the model "version" is just a SHA-256
hash of the file's own bytes (`back-end/src/services/model.service.js`), so
there's no separate version bookkeeping to keep in sync.

Note: `ai/data/raw/personal_expense_classification.csv` (already present in
this folder) is for the categorization model above, not Tier B — it has no
dates or per-account field, so it can't train a time-series regressor.
