import 'package:flutter/foundation.dart';

/// Fires on expense/budget create/edit so sibling tabs kept alive in the IndexedStack know to refetch — no push/pop for RouteAware to hook into.
final ValueNotifier<int> expenseDataChanged = ValueNotifier<int>(0);

void notifyExpenseDataChanged() => expenseDataChanged.value++;
