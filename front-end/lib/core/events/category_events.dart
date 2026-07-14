import 'package:flutter/foundation.dart';

/// Fires whenever a category is added/edited/deleted/reordered so sibling
/// tabs (Input, Budgets, Guide) kept alive in the same IndexedStack know to
/// refetch — mirrors expense_events.dart's expenseDataChanged ping pattern.
final ValueNotifier<int> categoriesChanged = ValueNotifier<int>(0);

void notifyCategoriesChanged() => categoriesChanged.value++;
