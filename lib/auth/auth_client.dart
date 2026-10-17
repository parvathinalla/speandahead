import 'auth_profile.dart';

abstract class AuthClient {
  Future<AuthProfile?> restore();
  Future<AuthProfile?> login({required bool signUp});
  Future<String?> accessToken();
  Future<void> logout();
}
