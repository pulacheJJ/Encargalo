import 'package:firebase_core/firebase_core.dart';

abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const firebaseKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseProject = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseSender = String.fromEnvironment('FIREBASE_SENDER_ID');
  static bool get configured =>
      Uri.tryParse(supabaseUrl)?.scheme == 'https' && supabaseKey.isNotEmpty;
  static bool get pushConfigured => [
    firebaseKey,
    firebaseAppId,
    firebaseProject,
    firebaseSender,
  ].every((s) => s.isNotEmpty);
  static FirebaseOptions get firebaseOptions => FirebaseOptions(
    apiKey: firebaseKey,
    appId: firebaseAppId,
    messagingSenderId: firebaseSender,
    projectId: firebaseProject,
  );
}
