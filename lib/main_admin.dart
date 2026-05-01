import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'package:dayday_usta/admin_web/admin_web_app.dart';
import 'package:dayday_usta/firebase_options.dart';
import 'package:dayday_usta/services/auth_service.dart';

/// Точка входа **только** для Flutter Web admin (`flutter run -d chrome --target=lib/main_admin.dart`).
/// Без FCM и локальных уведомлений — см. docs/ADMIN_WEB_MVP.md
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
      ],
      child: const AdminWebApp(),
    ),
  );
}
