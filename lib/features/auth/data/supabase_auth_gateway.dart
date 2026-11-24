import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/api_client.dart';
import '../domain/auth_gateway.dart';

class SupabaseAuthGateway implements AuthGateway {
  final GoTrueClient auth;
  SupabaseAuthGateway(this.auth);

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 18));
    } on TimeoutException {
      throw ApiFailure(
        'La conexión está tardando. Comprueba Internet y vuelve a intentar.',
        retryable: true,
      );
    } on AuthException catch (e) {
      final message = switch (e.code) {
        'invalid_credentials' => 'El correo o la contraseña no son correctos.',
        'email_not_confirmed' => 'Confirma tu correo antes de ingresar.',
        'user_already_exists' =>
          'Ya existe una cuenta con ese correo. Inicia sesión o recupera el acceso.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' =>
          'Se alcanzó el límite temporal. Espera antes de volver a intentar.',
        _ => 'No se pudo completar el acceso. Revisa tus datos y la conexión.',
      };
      throw ApiFailure(message, retryable: e is AuthRetryableFetchException);
    }
  }

  @override
  Future<void> signIn(String email, String password) => _request(() async {
    await auth.signInWithPassword(email: email.trim(), password: password);
  });

  @override
  Future<RegistrationResult> register({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) => _request(() async {
    final result = await auth.signUp(
      email: email.trim(),
      password: password,
      data: metadata,
      emailRedirectTo: 'encargalo://auth',
    );
    return RegistrationResult(confirmationRequired: result.session == null);
  });
}
