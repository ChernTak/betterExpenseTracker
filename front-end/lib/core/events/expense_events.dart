import 'package:flutter/foundation.dart';

/// Fires whenever an expense or budget is created/edited so sibling tabs
/// (Guide, Budgets) kept alive in the same IndexedStack know to refetch —
/// there's no push/pop between them for RouteAware to hook into.
final ValueNotifier<int> expenseDataChanged = ValueNotifier<int>(0);

void notifyExpenseDataChanged() => expenseDataChanged.value++;
