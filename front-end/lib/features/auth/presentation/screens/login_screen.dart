import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/labeled_field.dart';
import '../../../../route.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/fcm_service.dart';

/// Combined Login / Sign Up screen — a pill toggle switches which form is
/// shown instead of navigating to a separate route, matching the mockup.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _mobileController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);
    try {
      final result = await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );

      // FR1.7 — an admin account has no expenses/budgets of its own, so it
      // skips the expense-tracking shell entirely and lands on user management.
      final role = (result['user'] as Map<String, dynamic>?)?['role'] as String?;
      if (role == 'admin') {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.admin);
        return;
      }

      // FR3.5 — register this device for budget-alert push notifications.
      // Best-effort: a denied permission or missing setup shouldn't block login.
      unawaited(FcmService().registerToken());

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isLoading = true);
    try {
      await _authService.continueAsGuest();
      unawaited(FcmService().registerToken());

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    setState(() => _isLoading = true);
    try {
      await _authService.register(
        email: _emailController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        mobileNumber: _mobileController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful. Please log in.')),
      );
      setState(() => _isLogin = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLogin) {
      await _handleLogin();
    } else {
      await _handleRegister();
    }
  }

  Future<void> _handleForgotPassword() async {
    final emailController = TextEditingController(text: _emailController.text.trim());

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, emailController.text.trim()),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Send Link'),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty || !mounted) return;

    try {
      final message = await _authService.requestPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text(
                  _isLogin ? 'Welcome Back' : 'Create Account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin
                      ? 'Enter your credentials to access your guide.'
                      : 'Sign up to start tracking your spending.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 28),
                _AuthModeToggle(
                  isLogin: _isLogin,
                  onChanged: (value) => setState(() => _isLogin = value),
                ),
                const SizedBox(height: 28),
                if (_isLogin) ..._buildLoginFields() else ..._buildRegisterFields(),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_isLogin ? 'Access Dashboard' : 'Create Account'),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _isLoading ? null : _handleGuestLogin,
                  child: const Text('Continue as Guest', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    children: [
                      const TextSpan(text: 'By accessing Sovereign Guide, you agree to our '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                        recognizer: TapGestureRecognizer()..onTap = () {},
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                        recognizer: TapGestureRecognizer()..onTap = () {},
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLoginFields() {
    return [
      LabeledField(
        label: 'Email Address',
        child: TextFormField(
          controller: _emailController,
          decoration: const InputDecoration(hintText: 'name@example.com'),
          keyboardType: TextInputType.emailAddress,
          validator: Validators.validateEmail,
        ),
      ),
      const SizedBox(height: 20),
      LabeledField(
        label: 'Password',
        trailing: TextButton(
          onPressed: _handleForgotPassword,
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
          child: const Text('FORGOT?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        child: TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            hintText: '••••••••',
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          obscureText: _obscurePassword,
          validator: (value) => Validators.validateRequired(value, fieldName: 'Password'),
        ),
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: _rememberMe,
              onChanged: (value) => setState(() => _rememberMe = value ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            child: const Text('Remember me', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildRegisterFields() {
    return [
      LabeledField(
        label: 'Username',
        child: TextFormField(
          controller: _usernameController,
          decoration: const InputDecoration(hintText: 'Your username'),
          validator: (value) => Validators.validateRequired(value, fieldName: 'Username'),
        ),
      ),
      const SizedBox(height: 20),
      LabeledField(
        label: 'Email Address',
        child: TextFormField(
          controller: _emailController,
          decoration: const InputDecoration(hintText: 'name@example.com'),
          keyboardType: TextInputType.emailAddress,
          validator: Validators.validateEmail,
        ),
      ),
      const SizedBox(height: 20),
      LabeledField(
        label: 'Mobile Number (optional)',
        child: TextFormField(
          controller: _mobileController,
          decoration: const InputDecoration(hintText: '+60 12-345 6789'),
          keyboardType: TextInputType.phone,
        ),
      ),
      const SizedBox(height: 20),
      LabeledField(
        label: 'Password',
        child: TextFormField(
          controller: _passwordController,
          decoration: const InputDecoration(hintText: '••••••••'),
          obscureText: true,
          validator: Validators.validatePassword,
        ),
      ),
      const SizedBox(height: 20),
      LabeledField(
        label: 'Confirm Password',
        child: TextFormField(
          controller: _confirmPasswordController,
          decoration: const InputDecoration(hintText: '••••••••'),
          obscureText: true,
          validator: (value) {
            if (value != _passwordController.text) return 'Passwords do not match';
            return null;
          },
        ),
      ),
    ];
  }
}

class _AuthModeToggle extends StatelessWidget {
  final bool isLogin;
  final ValueChanged<bool> onChanged;

  const _AuthModeToggle({required this.isLogin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          Expanded(child: _segment(context, 'Login', selected: isLogin, onTap: () => onChanged(true))),
          Expanded(child: _segment(context, 'Sign Up', selected: !isLogin, onTap: () => onChanged(false))),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
