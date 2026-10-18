import 'auth_profile.dart';

abstract class AuthClient {
  Future<AuthProfile?> restore();
  Future<AuthProfile?> login();
  Future<String?> accessToken();
  Future<void> logout();
}
