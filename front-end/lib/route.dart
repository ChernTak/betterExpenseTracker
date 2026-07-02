import 'package:flutter/material.dart';
import 'core/navigation/main_shell.dart';
import 'features/expense/presentation/screens/expense_list_screen.dart';
import 'features/auth/presentation/screens/login_screen.dart';

class AppRoutes {
  static const String login = '/login';
  static const String main = '/main';
  static const String expenses = '/expenses';

  static final Map<String, WidgetBuilder> routes = {
    login: (context) => const LoginScreen(),
    main: (context) => const MainShell(),
    expenses: (context) => const ExpenseListScreen(),
  };
}
