import 'package:flutter/material.dart';
import 'core/constants/app_colors.dart';
import 'route.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Lets NotificationHandler show a SnackBar for incoming budget alerts
  // (FR3.5) without needing a BuildContext from inside the widget tree.
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          bodyMedium: TextStyle(color: AppColors.textPrimary),
        ).apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
        ),
        // Floating (not the default `fixed`) so SnackBars overlay content
        // instead of resizing the Scaffold's bottom area — otherwise the
        // BottomAppBar and the FAB docked in its notch get pushed up and
        // back down every time a SnackBar shows/hides.
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      initialRoute: AppRoutes.login,
      routes: AppRoutes.routes,
    );
  }
}
