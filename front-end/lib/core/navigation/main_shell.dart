import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/screens/profile_screen.dart';
import '../../features/budget/presentation/screens/budgets_screen.dart';
import '../../features/budget/presentation/screens/guide_screen.dart';
import '../../features/expense/presentation/screens/add_expense_screen.dart';
import '../../features/expense/presentation/voice/voice_capture_controller.dart';
import '../../features/expense/presentation/voice/voice_confirmation_sheet.dart';
import '../../features/food_recommendation/presentation/screens/food_recommendation_screen.dart';
import '../../features/notifications/notification_handler.dart';
import '../../services/category_service.dart';
import '../../services/feature_flag_service.dart';
import '../constants/app_colors.dart';

/// Post-login shell: five bottom-nav tabs kept alive in an IndexedStack; Food is a placeholder, Insights was folded into Budget's Forecast sub-tab.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const _guideIndex = 0;
  static const _budgetIndex = 1;
  static const _inputIndex = 2;
  static const _foodIndex = 3;
  static const _settingsIndex = 4;

  int _index = _guideIndex;

  // Measured post-frame so body padding can subtract the bar height back out — using the full keyboard height double-counts it.
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

  static const _titles = [
    'Sovereign Guide',
    'Budgets',
    'Add Expense',
    'Food Recommendations',
    'Settings',
  ];

  // FR4.4 hands-free wake-word logging; opt-in since it's a persistent mic listener, state persisted like GPS consent.
  static const _handsFreePrefsKey = 'voice_hands_free_enabled';
  static const _batteryTipShownKey = 'voice_battery_tip_shown';
  late final VoiceCaptureController _voiceController;
  final _featureFlagService = FeatureFlagService();

  // Remote kill-switch, checked at startup; defaults true (fails open) since this feature must work offline, so a failed flag check can't gate it shut.
  bool _voiceFeatureAllowed = true;

  // Set before we stop the listener ourselves on backgrounding, so resume restarts it silently instead of showing the OEM-battery-kill recovery snackbar.
  bool _handsFreeSuspendedForBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Warm CategoryService's cache before first render so early icon/color/label lookups don't fall back to a placeholder.
    CategoryService().fetchCategories();

    _voiceController = VoiceCaptureController();
    _voiceController.addListener(_onVoiceStateChanged);
    _restoreHandsFreePreference();

    // Handles a wishlist-nudge notification tap from before this shell (first post-login BuildContext) mounted — stashed until now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationHandler.tryShowPendingWishlistDialog();
    });
  }

  Future<void> _restoreHandsFreePreference() async {
    // WakeWordService (vosk_flutter_2) is Android-only — see its doc
    // comment — so there's no hands-free state to restore elsewhere.
    if (!Platform.isAndroid) return;

    _voiceFeatureAllowed = await _featureFlagService.isVoiceHandsFreeEnabled();
    if (!mounted || !_voiceFeatureAllowed) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_handsFreePrefsKey) ?? false) {
      await _voiceController.startHandsFree();
    }
  }

  // vosk_flutter_2's native thread races Activity teardown into a SIGSEGV; stopping the listener explicitly on backgrounding avoids the crash.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_handsFreeSuspendedForBackground) {
        _handsFreeSuspendedForBackground = false;
        _voiceController.startHandsFree();
      } else {
        _maybeOfferHandsFreeRecovery();
      }
      return;
    }

    if (_voiceController.isHandsFreeActive) {
      _handsFreeSuspendedForBackground = true;
      _voiceController.stopHandsFree();
    }
  }

  Future<void> _maybeOfferHandsFreeRecovery() async {
    if (!Platform.isAndroid || !_voiceFeatureAllowed) return;
    if (_voiceController.isHandsFreeActive) return; // still running fine

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_handsFreePrefsKey) ?? false))
      return; // user turned it off themselves
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Hands-free voice logging was stopped by the system.',
        ),
        action: SnackBarAction(
          label: 'Re-enable',
          onPressed: () => _voiceController.startHandsFree(),
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _onVoiceStateChanged() {
    if (!mounted) return;
    switch (_voiceController.status) {
      case VoiceCaptureStatus.parsed:
      case VoiceCaptureStatus.parseFailed:
        VoiceConfirmationSheet.show(context, _voiceController);
      case VoiceCaptureStatus.noSpeechDetected:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Didn't catch that — say \"Ok App\" to try again."),
          ),
        );
      case VoiceCaptureStatus.permissionDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone permission is needed for hands-free voice logging.',
            ),
          ),
        );
      case VoiceCaptureStatus.unsupportedPlatform:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hands-free listening needs Android — try the Voice button on Input instead.',
            ),
          ),
        );
      case VoiceCaptureStatus.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _voiceController.errorMessage ?? 'Voice listening failed.',
            ),
          ),
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
          'phrase "Ok App" and attempt to process it using local speech '
          'recognition on this device. Say it followed by an expense, e.g. '
          '"Ok App, spent twelve dollars on lunch at McDonald\'s today". '
          'Listening stops if you close the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _voiceController.startHandsFree();
    await prefs.setBool(_handsFreePrefsKey, true);
    await _maybeOfferBatteryOptimizationTip(prefs);
  }

  // Shown once on first enable — OEM battery managers are the top reason this silently stops working; openAppSettings() can't deep-link the exact sub-screen, so this opens general settings.
  Future<void> _maybeOfferBatteryOptimizationTip(
    SharedPreferences prefs,
  ) async {
    if (prefs.getBool(_batteryTipShownKey) ?? false) return;
    await prefs.setBool(_batteryTipShownKey, true);
    if (!mounted) return;

    final openSettings = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('One more thing'),
        content: const Text(
          'Some phones aggressively stop apps running in the background to '
          'save battery, which can silently turn hands-free listening off. '
          'If it seems to stop working on its own, exempting this app from '
          'battery optimization in your phone\'s settings usually fixes it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (openSettings == true) await openAppSettings();
  }

  void _goToGuide() => setState(() => _index = _guideIndex);

  void _selectTab(int index) => setState(() => _index = index);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceController.removeListener(_onVoiceStateChanged);
    _voiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handsFreeActive = _voiceController.isHandsFreeActive;
    _measureBottomBar();
    final keyboardPadding =
        (MediaQuery.of(context).viewInsets.bottom - _bottomBarHeight).clamp(
          0.0,
          double.infinity,
        );
    return Scaffold(
      // False so the bottom nav/FAB stay pinned instead of riding up with the keyboard; body Padding below still clears fields.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          // Hands-free listening is Android-only, so the toggle is hidden elsewhere (iOS keeps the tap-to-talk button); also hidden if the kill-switch disabled it.
          if (Platform.isAndroid && _voiceFeatureAllowed)
            IconButton(
              onPressed: _toggleHandsFree,
              icon: Icon(handsFreeActive ? Icons.mic : Icons.mic_off_outlined),
              color: handsFreeActive ? AppColors.primary : null,
              tooltip: handsFreeActive
                  ? 'Hands-free voice logging is on — tap to turn off'
                  : 'Turn on hands-free voice logging ("Ok App")',
            ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: keyboardPadding),
        child: IndexedStack(
          index: _index,
          children: [
            const GuideScreen(),
            const BudgetsScreen(),
            AddExpenseScreen(onSaved: _goToGuide, voiceController: _voiceController),
            const FoodRecommendationScreen(),
            const ProfileScreen(),
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
      // No explicit height on BottomAppBar — fixed pixel budgets produced worse overflows on-device; _NavBarItem scales to fit instead.
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
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'Settings',
                selected: _index == _settingsIndex,
                onTap: () => _selectTab(_settingsIndex),
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
          // Scales down instead of overflowing if BottomAppBar resolves a tighter height than wanted (see build() for why fixed heights don't work).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? selectedIcon : icon, color: color, size: 24),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
