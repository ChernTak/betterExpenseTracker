class Validators {
  // Matches the backend's isValidPassword rule (FR1.1)
  static String? validatePassword(String? value) {
    if (value == null || value.length < 8) return 'Min 8 characters';
    if (!value.contains(RegExp(r'[A-Z]'))) return 'Must contain an uppercase letter';
    if (!value.contains(RegExp(r'[a-z]'))) return 'Must contain a lowercase letter';
    if (!value.contains(RegExp(r'[0-9]'))) return 'Must contain a number';
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || !value.contains('@')) return 'Invalid email';
    return null;
  }

  static String? validateRequired(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required';
    return null;
  }

  static String? validateAmount(String? value) {
    if (value == null || value.isEmpty) return 'Amount required';
    final n = double.tryParse(value);
    if (n == null || n <= 0) return 'Must be a positive number';
    return null;
  }
}
