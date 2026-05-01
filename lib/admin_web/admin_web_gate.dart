import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dayday_usta/admin_web/admin_web_shell.dart';
import 'package:dayday_usta/core/app_constants.dart';
import 'package:dayday_usta/models/user_profile.dart';
import 'package:dayday_usta/screens/auth/auth_screen.dart';
import 'package:dayday_usta/services/auth_service.dart';

/// Вход и проверка `users/{uid}.role == admin` (дублирует смысл основного [Wrapper], без клиентского shell).
class AdminWebGate extends StatelessWidget {
  const AdminWebGate({super.key});

  bool _isAdminRole(String role) {
    return role == AppConstants.dbRoleAdmin || role == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const AuthScreen();
        }

        return FutureBuilder<UserProfile?>(
          future: authService.getCurrentUserProfile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              return const Scaffold(
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Profil tapılmadı. Əvvəlcə mobil tətbiqdə rol seçin və ya admin üçün users sənədini yaradın.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            if (!_isAdminRole(profile.role)) {
              return Scaffold(
                appBar: AppBar(title: const Text('Giriş məhdudlaşdırılıb')),
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'Bu panel yalnız admin rolü üçündür (cari rol: ${profile.role}).',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () async {
                              await authService.signOut();
                            },
                            child: const Text('Çıxış'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            return AdminWebShell(userId: profile.uid);
          },
        );
      },
    );
  }
}
