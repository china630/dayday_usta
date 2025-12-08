import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/services/user_profile_service.dart';
import 'package:bolt_usta/screens/auth/auth_screen.dart';
import 'package:bolt_usta/screens/auth/role_selection_screen.dart';
import 'package:bolt_usta/screens/client/client_main_shell.dart';
import 'package:bolt_usta/screens/master/master_dashboard_screen.dart';
import 'package:bolt_usta/screens/admin/admin_dashboard_screen.dart';
import 'package:bolt_usta/firebase_options.dart';
import 'package:bolt_usta/models/user_profile.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/managers/location_manager.dart';

// ✅ Импорт цветов
import 'package:bolt_usta/core/app_colors.dart';

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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBackgroundColor,
        primaryColor: kPrimaryColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimaryColor,
          primary: kPrimaryColor,
          onPrimary: Colors.white,
          secondary: kDarkColor,
          background: kBackgroundColor,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimaryColor, width: 2),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: kPrimaryColor,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
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
    } else if (role == AppConstants.dbRoleMaster) {
      // ✅ Теперь это сработает, так как profile реально является MasterProfile
      final masterProfile = profile as MasterProfile;
      return MasterDashboardScreen(masterId: userId, masterProfile: masterProfile);
    } else if (role == AppConstants.dbRoleAdmin) {
      return AdminDashboardScreen(currentUserId: userId);
    }

    return RoleSelectionScreen(
        firebaseUser: Provider.of<AuthService>(context, listen: false).getCurrentUser()!
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;

        if (user == null) {
          return const AuthScreen();
        } else {
          return FutureBuilder<UserProfile?>(
            future: authService.getCurrentUserProfile(),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final profile = profileSnapshot.data;
              if (profile == null) {
                return RoleSelectionScreen(firebaseUser: user);
              } else {
                return _getScreenByRole(context, profile.role, profile);
              }
            },
          );
        }
      },
    );
  }
}