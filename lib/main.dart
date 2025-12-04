// lib/main.dart (ПОЛНОСТЬЮ ИСПРАВЛЕННЫЙ КОД)

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/services/user_profile_service.dart';
import 'package:bolt_usta/screens/auth/auth_screen.dart';
import 'package:bolt_usta/screens/auth/role_selection_screen.dart';

// ✅ НОВЫЕ ИМПОРТЫ
import 'package:bolt_usta/screens/client/client_main_shell.dart';
import 'package:bolt_usta/screens/master/master_dashboard_screen.dart';
import 'package:bolt_usta/screens/admin/admin_dashboard_screen.dart'; // Предполагаемый импорт
import 'package:bolt_usta/firebase_options.dart';
import 'package:bolt_usta/models/user_profile.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/managers/location_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print('Firebase initialization error: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => LocationManager()),
        Provider<UserProfileService>(create: (_) => UserProfileService()),
      ],
      child: const BoltUstaApp(),
    ),
  );
}

class BoltUstaApp extends StatelessWidget {
  const BoltUstaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bolt Usta',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue.shade700),
        useMaterial3: true,
      ),
      home: const Wrapper(),
    );
  }
}

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  Widget _getScreenByRole(BuildContext context, String role, UserProfile profile) {
    final userId = profile.uid;

    if (role == AppConstants.dbRoleCustomer) {
      return ClientMainShell(currentUserId: userId);
    }

    else if (role == AppConstants.dbRoleMaster) {
      final masterProfile = profile as MasterProfile;
      // ✅ ИСПРАВЛЕНИЕ 1: Передаем MasterProfile в конструктор
      return MasterDashboardScreen(masterId: userId, masterProfile: masterProfile);
    }

    else if (role == AppConstants.dbRoleAdmin) {
      // ✅ ИСПРАВЛЕНИЕ 2: Передаем currentUserId в конструктор AdminDashboardScreen
      return AdminDashboardScreen(currentUserId: userId);
    }

    // Fallback: Если роль не определена
    return RoleSelectionScreen(firebaseUser: Provider.of<AuthService>(context, listen: false).getCurrentUser()!);
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = snapshot.data;

        if (user == null) {
          return const AuthScreen();
        } else {
          return FutureBuilder<UserProfile?>(
            future: authService.getCurrentUserProfile(),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final profile = profileSnapshot.data;

              if (profile == null) {
                return RoleSelectionScreen(firebaseUser: user);
              } else {
                // ✅ ИСПРАВЛЕНИЕ 3: Передаем context в _getScreenByRole
                return _getScreenByRole(context, profile.role, profile);
              }
            },
          );
        }
      },
    );
  }
}