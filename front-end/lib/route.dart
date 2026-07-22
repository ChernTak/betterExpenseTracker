import 'package:flutter/material.dart';
import 'core/navigation/main_shell.dart';
import 'features/admin/presentation/screens/admin_users_screen.dart';
import 'features/expense/presentation/screens/expense_list_screen.dart';
import 'features/auth/presentation/screens/login_screen.dart';

class AppRoutes {
  static const String login = '/login';
  static const String main = '/main';
  static const String expenses = '/expenses';
  // FR1.7 — the System Administrator's landing screen (see route.dart usage
  // in login_screen.dart, which branches here instead of `main` based on the
  // role returned by /api/auth/login).
  static const String admin = '/admin';

  static final Map<String, WidgetBuilder> routes = {
    login: (context) => const LoginScreen(),
    main: (context) => const MainShell(),
    expenses: (context) => const ExpenseListScreen(),
    admin: (context) => const AdminUsersScreen(),
  };
}
