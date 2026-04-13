class CredentialConfig {
  const CredentialConfig({
    required this.username,
    required this.password,
    this.displayName,
    this.answerUrl,
  });

  final String username;
  final String password;
  final String? displayName;
  final String? answerUrl;
}
