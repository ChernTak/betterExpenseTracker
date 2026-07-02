import 'package:flutter/material.dart';

import '../../features/ai_insights/presentation/screens/ai_insights_screen.dart';
import '../../features/budget/presentation/screens/budgets_screen.dart';
import '../../features/budget/presentation/screens/guide_screen.dart';
import '../../features/expense/presentation/screens/add_expense_screen.dart';

/// The post-login app shell: a single Scaffold hosting the four bottom-nav
/// tabs (Guide/Input/Budgets/Insights) from the design, each kept alive in
/// an IndexedStack so switching tabs doesn't refetch or lose scroll state.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['Sovereign Guide', 'Add Expense', 'Budgets', 'Insights'];

  void _goToGuide() => setState(() => _index = 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(
        index: _index,
        children: [
          const GuideScreen(),
          AddExpenseScreen(onSaved: _goToGuide),
          const BudgetsScreen(),
          const InsightsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Guide'),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Input',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Budgets',
          ),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Insights'),
        ],
      ),
    );
  }
}
