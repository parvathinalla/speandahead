import 'package:flutter/foundation.dart';

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String partnerName;
  final String partnerEmail;
  final String initials;
  final String accessToken;
  final DateTime expiresAt;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.partnerName,
    required this.partnerEmail,
    required this.initials,
    required this.accessToken,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();
  AuthService._();

  AuthUser? _currentUser;
  bool _isLoading = false;

  AuthUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && !_currentUser!.isExpired;
  bool get isLoading => _isLoading;
  String? get token => _currentUser?.accessToken;

  // Available Demo Profiles
  static const List<Map<String, String>> demoProfiles = [
    {
      "id": "alex_smith",
      "name": "Alex Smith",
      "email": "alex.smith@example.com",
      "partner": "Sarah Smith",
      "partner_email": "sarah.smith@example.com",
      "initials": "AS",
      "role": "Primary Borrower",
    },
    {
      "id": "sarah_smith",
      "name": "Sarah Smith",
      "email": "sarah.smith@example.com",
      "partner": "Alex Smith",
      "partner_email": "alex.smith@example.com",
      "initials": "SS",
      "role": "Joint Account Partner",
    },
  ];

  Future<void> loginWithAuth0({String profileId = "alex_smith"}) async {
    _isLoading = true;
    notifyListeners();

    // Simulate Auth0 token exchange without client secrets
    await Future.delayed(const Duration(milliseconds: 300));

    final profile = demoProfiles.firstWhere(
      (p) => p["id"] == profileId,
      orElse: () => demoProfiles.first,
    );

    _currentUser = AuthUser(
      id: profile["id"]!,
      name: profile["name"]!,
      email: profile["email"]!,
      partnerName: profile["partner"]!,
      partnerEmail: profile["partner_email"]!,
      initials: profile["initials"]!,
      accessToken: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.demo_token_${profile["id"]}",
      expiresAt: DateTime.now().add(const Duration(hours: 8)),
    );

    _isLoading = false;
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  void expireTokenForTesting() {
    if (_currentUser != null) {
      _currentUser = AuthUser(
        id: _currentUser!.id,
        name: _currentUser!.name,
        email: _currentUser!.email,
        partnerName: _currentUser!.partnerName,
        partnerEmail: _currentUser!.partnerEmail,
        initials: _currentUser!.initials,
        accessToken: _currentUser!.accessToken,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      notifyListeners();
    }
  }
}
