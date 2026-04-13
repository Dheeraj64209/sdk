class TokenConfig {
  const TokenConfig({
    required this.token,
    this.displayName,
    this.answerUrl,
  });

  final String token;
  final String? displayName;
  final String? answerUrl;
}
