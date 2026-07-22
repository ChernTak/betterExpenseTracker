import 'package:flutter/material.dart';

import '../../features/ai_insights/presentation/screens/ai_insights_screen.dart';
import '../../features/budget/presentation/screens/budgets_screen.dart';
import '../../features/budget/presentation/screens/guide_screen.dart';
import '../../features/expense/presentation/screens/add_expense_screen.dart';
import '../../features/food_recommendation/presentation/screens/food_recommendation_screen.dart';
import '../../route.dart';
import '../../services/auth_service.dart';
import '../../services/category_service.dart';
import '../constants/app_colors.dart';

/// The post-login app shell: a single Scaffold hosting the five bottom-nav
/// tabs (Guide/Food/Input/Budgets/Insights), each kept alive in an
/// IndexedStack so switching tabs doesn't refetch or lose scroll state.
/// Input sits in a raised circular button docked in a notch of the bottom
/// bar, matching a common banking-app layout (tab order/labels per the
/// 2026-07-22 request — Food and Insights are placeholders/first-pass and
/// expected to be refined later).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _guideIndex = 0;
  static const _foodIndex = 1;
  static const _inputIndex = 2;
  static const _budgetIndex = 3;
  static const _insightsIndex = 4;

  int _index = _guideIndex;

  static const _titles = ['Sovereign Guide', 'Food Recommendations', 'Add Expense', 'Budgets', 'Insights'];

  @override
  void initState() {
    super.initState();
    // Warm CategoryService's static cache before any tab first renders, so
    // the very first icon/color/label lookup doesn't fall back to a generic
    // placeholder while the network request is still in flight.
    CategoryService().fetchCategories();
  }

  void _goToGuide() => setState(() => _index = _guideIndex);

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can log back in anytime with your email and password.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;

    await AuthService().logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
  }

  void _selectTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Log out')],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const GuideScreen(),
          const FoodRecommendationScreen(),
          AddExpenseScreen(onSaved: _goToGuide),
          const BudgetsScreen(),
          const InsightsScreen(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _selectTab(_inputIndex),
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 4,
        tooltip: 'Input',
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
      // SafeArea keeps the bar clear of the gesture-nav inset on devices
      // like the Pixel. No explicit `height` on BottomAppBar — guessing
      // fixed pixel budgets against it produced worse overflows each time
      // (7px unset -> 11px @72 -> 19px @64, tested on-device); _NavBarItem
      // instead scales its own content to fit whatever height it's given.
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavBarItem(
                icon: Icons.explore_outlined,
                selectedIcon: Icons.explore,
                label: 'Guide',
                selected: _index == _guideIndex,
                onTap: () => _selectTab(_guideIndex),
              ),
              _NavBarItem(
                icon: Icons.restaurant_outlined,
                selectedIcon: Icons.restaurant,
                label: 'Food',
                selected: _index == _foodIndex,
                onTap: () => _selectTab(_foodIndex),
              ),
              // Space for the notch the FloatingActionButton sits in.
              const SizedBox(width: 48),
              _NavBarItem(
                icon: Icons.pie_chart_outline,
                selectedIcon: Icons.pie_chart,
                label: 'Budget',
                selected: _index == _budgetIndex,
                onTap: () => _selectTab(_budgetIndex),
              ),
              _NavBarItem(
                icon: Icons.insights_outlined,
                selectedIcon: Icons.insights,
                label: 'Insights',
                selected: _index == _insightsIndex,
                onTap: () => _selectTab(_insightsIndex),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          // Scales down instead of overflowing if BottomAppBar ever resolves
          // a tighter height than this content wants (device/theme/text-scale
          // dependent — see the build() comment for why fixed pixel heights
          // didn't reliably work here).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? selectedIcon : icon, color: color, size: 24),
                const SizedBox(height: 3),
                Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
