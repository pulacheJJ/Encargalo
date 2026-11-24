class RegistrationResult {
  final bool confirmationRequired;
  const RegistrationResult({required this.confirmationRequired});
}

abstract interface class AuthGateway {
  Future<void> signIn(String email, String password);
  Future<RegistrationResult> register({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  });
}
