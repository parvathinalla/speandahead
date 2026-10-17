class AuthProfile {
  final String subject;
  final String displayName;
  final String? email;
  final String? photoUrl;

  const AuthProfile({
    required this.subject,
    required this.displayName,
    this.email,
    this.photoUrl,
  });
}
