import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_colors.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/services/user_profile_service.dart';
import 'package:bolt_usta/models/user_profile.dart';
import 'package:bolt_usta/screens/auth/auth_screen.dart';

class ClientProfileScreen extends StatefulWidget {
  final String currentUserId;

  const ClientProfileScreen({Key? key, required this.currentUserId}) : super(key: key);

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final AuthService _authService = AuthService();
  final UserProfileService _userProfileService = UserProfileService();

  UserProfile? _profile;
  bool _isLoading = true;
  String _selectedLanguage = 'AZ'; // Выбор языка (визуальный)

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _userProfileService.getUserProfile(widget.currentUserId);
    if (mounted) {
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    }
  }

  // ✅ ИСПРАВЛЕННАЯ ЛОГИКА ВЫХОДА
  Future<void> _signOut() async {
    try {
      // 1. Выходим из Firebase
      await _authService.signOut();

      // 2. Принудительно переходим на экран авторизации, удаляя историю
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Səhv: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: kPrimaryColor)),
      );
    }

    return Scaffold(
      backgroundColor: kBackgroundColor, // Светло-серый фон для тела
      body: Column(
        children: [
          // 1. МЯТНАЯ ШАПКА
          Container(
            padding: const EdgeInsets.only(top: 50, bottom: 20),
            width: double.infinity,
            decoration: const BoxDecoration(
              color: kPrimaryColor,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: Column(
              children: [
                const Text(
                  "Profil",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 20),

                // Аватар
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  child: const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 60, color: kPrimaryColor),
                  ),
                ),
                const SizedBox(height: 15),

                // Имя
                Text(
                  _profile?.fullName ?? "İstifadəçi",
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  _profile?.phoneNumber ?? "",
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ],
            ),
          ),

          // 2. КОНТЕНТ (Белая карточка)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Выбор языка
                  const Text("Dil seçimi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kDarkColor)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      _buildLangButton("AZ"),
                      const SizedBox(width: 10),
                      _buildLangButton("RU"),
                      const SizedBox(width: 10),
                      _buildLangButton("EN"),
                    ],
                  ),

                  const Spacer(),

                  // Кнопка выхода
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text("Hesabdan çıx", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLangButton(String lang) {
    final isSelected = _selectedLanguage == lang;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedLanguage = lang),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor.withOpacity(0.1) : Colors.white,
            border: Border.all(color: isSelected ? kPrimaryColor : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Center(
            child: Text(
              lang,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? kPrimaryColor : Colors.grey[600],
              ),
            ),
          ),
        ),
      ),
    );
  }
}