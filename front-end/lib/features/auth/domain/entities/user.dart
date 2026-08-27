class User {
  final String userId;
  final String email;
  final String username;
  final String role;
  final bool isGuest;
  final bool locationConsent;
  final bool backgroundLocationConsent;
  final DateTime createdAt;

  const User({
    required this.userId,
    required this.email,
    required this.username,
    required this.role,
    required this.isGuest,
    required this.locationConsent,
    required this.backgroundLocationConsent,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    userId: json['userId'] as String,
    email: json['email'] as String,
    username: json['username'] as String,
    role: json['role'] as String,
    isGuest: json['isGuest'] as bool? ?? false,
    locationConsent: json['locationConsent'] as bool? ?? false,
    backgroundLocationConsent: json['backgroundLocationConsent'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
