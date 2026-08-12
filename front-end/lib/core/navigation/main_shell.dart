import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/ai_insights/presentation/screens/ai_insights_screen.dart';
import '../../features/budget/presentation/screens/budgets_screen.dart';
import '../../features/budget/presentation/screens/guide_screen.dart';
import '../../features/expense/presentation/screens/add_expense_screen.dart';
import '../../features/expense/presentation/voice/voice_capture_controller.dart';
import '../../features/expense/presentation/voice/voice_confirmation_sheet.dart';
import '../../features/food_recommendation/presentation/screens/food_recommendation_screen.dart';
import '../../route.dart';
import '../../services/auth_service.dart';
import '../../services/category_service.dart';
import '../constants/app_colors.dart';

/// The post-login app shell: a single Scaffold hosting the five bottom-nav
/// tabs (Guide/Budget/Input/Food/Insights), each kept alive in an
/// IndexedStack so switching tabs doesn't refetch or lose scroll state.
/// Input sits in a raised circular button docked in a notch of the bottom
/// bar, matching a common banking-app layout (tab order/labels per the
/// 2026-08-12 request — Food and Insights are placeholders/first-pass and
/// expected to be refined later).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _guideIndex = 0;
  static const _budgetIndex = 1;
  static const _inputIndex = 2;
  static const _foodIndex = 3;
  static const _insightsIndex = 4;

  int _index = _guideIndex;

  // Measured post-frame from _bottomBarKey so the body's keyboard padding
  // (below) can subtract it back out — the body's Scaffold-allocated area
  // already stops above this bar regardless of keyboard, so compensating by
  // the *full* keyboard height double-counts it and leaves a blank gap.
  final _bottomBarKey = GlobalKey();
  double _bottomBarHeight = 0;

  void _measureBottomBar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final height = _bottomBarKey.currentContext?.size?.height;
      if (height != null && height != _bottomBarHeight && mounted) {
        setState(() => _bottomBarHeight = height);
      }
    });
  }

  static const _titles = ['Sovereign Guide', 'Budgets', 'Add Expense', 'Food Recommendations', 'Insights'];

  // FR4.4 — hands-free wake-word ("Ok App") voice expense logging. Kept
  // opt-in (not started automatically) since it means a persistent
  // foreground mic listener; the toggle's chosen state is remembered across
  // app restarts the same way GPS consent is (see AuthService.updateLocationConsent).
  static const _handsFreePrefsKey = 'voice_hands_free_enabled';
  late final VoiceCaptureController _voiceController;

  @override
  void initState() {
    super.initState();
    // Warm CategoryService's static cache before any tab first renders, so
    // the very first icon/color/label lookup doesn't fall back to a generic
    // placeholder while the network request is still in flight.
    CategoryService().fetchCategories();

    _voiceController = VoiceCaptureController();
    _voiceController.addListener(_onVoiceStateChanged);
    _restoreHandsFreePreference();
  }

  Future<void> _restoreHandsFreePreference() async {
    // WakeWordService (vosk_flutter_2) is Android-only — see its doc
    // comment — so there's no hands-free state to restore elsewhere.
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_handsFreePrefsKey) ?? false) {
      await _voiceController.startHandsFree();
    }
  }

  void _onVoiceStateChanged() {
    if (!mounted) return;
    switch (_voiceController.status) {
      case VoiceCaptureStatus.parsed:
      case VoiceCaptureStatus.parseFailed:
        VoiceConfirmationSheet.show(context, _voiceController);
      case VoiceCaptureStatus.noSpeechDetected:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Didn't catch that — say \"Ok App\" to try again.")),
        );
      case VoiceCaptureStatus.permissionDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is needed for hands-free voice logging.'),
          ),
        );
      case VoiceCaptureStatus.unsupportedPlatform:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hands-free listening needs Android — try the Voice button on Input instead.'),
          ),
        );
      case VoiceCaptureStatus.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_voiceController.errorMessage ?? 'Voice listening failed.')),
        );
      case VoiceCaptureStatus.idle:
      case VoiceCaptureStatus.listeningForWake:
      case VoiceCaptureStatus.transcribing:
        break;
    }
    setState(() {}); // refreshes the mic icon in the AppBar
  }

  Future<void> _toggleHandsFree() async {
    final prefs = await SharedPreferences.getInstance();

    if (_voiceController.isHandsFreeActive) {
      await _voiceController.stopHandsFree();
      await prefs.setBool(_handsFreePrefsKey, false);
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enable hands-free voice logging?'),
        content: const Text(
          'While the app is open, it will keep listening for the wake '
          'phrase "Ok App", entirely on-device — audio never leaves your '
          'phone. Say it followed by an expense, e.g. "Ok App, spent '
          'twelve dollars on lunch at McDonald\'s today". Listening stops '
          'if you close the app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enable')),
        ],
      ),
    );
    if (confirmed != true) return;

    await _voiceController.startHandsFree();
    await prefs.setBool(_handsFreePrefsKey, true);
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
  void dispose() {
    _voiceController.removeListener(_onVoiceStateChanged);
    _voiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handsFreeActive = _voiceController.isHandsFreeActive;
    _measureBottomBar();
    final keyboardPadding = (MediaQuery.of(context).viewInsets.bottom - _bottomBarHeight).clamp(
      0.0,
      double.infinity,
    );
    return Scaffold(
      // False so the bottom nav bar and the FAB docked in its notch stay
      // pinned to the screen bottom instead of riding up with the keyboard
      // (the default `true` resizes the whole Scaffold, including those,
      // whenever a text field on a tab like Add Expense gets focus). The
      // body's own Padding below still shifts scrollable content clear of
      // the keyboard, so fields remain reachable.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          // Hands-free wake-word listening (WakeWordService/vosk_flutter_2)
          // is Android-only (see its doc comment) — the toggle isn't shown
          // where it could only ever fail; iOS still has the Voice
          // tap-to-talk button on the Input screen.
          if (Platform.isAndroid)
            IconButton(
              onPressed: _toggleHandsFree,
              icon: Icon(handsFreeActive ? Icons.mic : Icons.mic_off_outlined),
              color: handsFreeActive ? AppColors.primary : null,
              tooltip: handsFreeActive
                  ? 'Hands-free voice logging is on — tap to turn off'
                  : 'Turn on hands-free voice logging ("Ok App")',
            ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Log out'),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: keyboardPadding),
        child: IndexedStack(
          index: _index,
          children: [
            const GuideScreen(),
            const BudgetsScreen(),
            AddExpenseScreen(onSaved: _goToGuide),
            const FoodRecommendationScreen(),
            const InsightsScreen(),
          ],
        ),
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
        key: _bottomBarKey,
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
                icon: Icons.pie_chart_outline,
                selectedIcon: Icons.pie_chart,
                label: 'Budget',
                selected: _index == _budgetIndex,
                onTap: () => _selectTab(_budgetIndex),
              ),
              // Space for the notch the FloatingActionButton sits in.
              const SizedBox(width: 48),
              _NavBarItem(
                icon: Icons.restaurant_outlined,
                selectedIcon: Icons.restaurant,
                label: 'Food',
                selected: _index == _foodIndex,
                onTap: () => _selectTab(_foodIndex),
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
