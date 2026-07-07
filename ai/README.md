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
  models/         # trained model artifacts (.pkl / .joblib) (gitignored)
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
