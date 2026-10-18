import 'auth_client.dart';
import 'auth_client_native.dart'
    if (dart.library.html) 'auth_client_web.dart' as implementation;

AuthClient createAuthClient() => implementation.createAuthClient();
