import 'package:flutter/foundation.dart';

/// Fires on category add/edit/delete/reorder so sibling tabs kept alive in the IndexedStack know to refetch.
final ValueNotifier<int> categoriesChanged = ValueNotifier<int>(0);

void notifyCategoriesChanged() => categoriesChanged.value++;
