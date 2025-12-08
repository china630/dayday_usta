import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/core/app_colors.dart'; // ✅ Добавлены ваши цвета
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/main.dart';

class RoleSelectionScreen extends StatefulWidget {
  final User firebaseUser;
  const RoleSelectionScreen({required this.firebaseUser, super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  String? _selectedRole;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    super.dispose();
  }

  Future<void> _completeRegistration() async {
    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();

    if (_selectedRole == null || name.isEmpty || surname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zəhmət olmasa, rol, ad və soyadınızı daxil edin.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ ИСПРАВЛЕНИЕ: Вызов новых методов вместо createNewProfile

      if (_selectedRole == AppConstants.dbRoleCustomer) {
        // Регистрация КЛИЕНТА
        await _authService.registerClient(
          uid: widget.firebaseUser.uid,
          phoneNumber: widget.firebaseUser.phoneNumber ?? '',
          name: name,
          surname: surname,
        );
      } else if (_selectedRole == AppConstants.dbRoleMaster) {
        // Регистрация МАСТЕРА
        await _authService.registerMaster(
          uid: widget.firebaseUser.uid,
          phoneNumber: widget.firebaseUser.phoneNumber ?? '',
          name: name,
          surname: surname,
          categories: [], // Пустые списки, заполнит в профиле
          districts: [],
        );
      } else {
        throw Exception("Unknown role selected");
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const Wrapper()),
              (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      print('Registration failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Qeydiyyat zamanı xəta: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Kimsiniz?', style: TextStyle(fontWeight: FontWeight.bold, color: kDarkColor)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Xoş gəlmisiniz! Zəhmət olmasa, rolunuzu seçin və məlumatları tamamlayın.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),

            // Выбор Роли (Кнопки)
            Row(
              children: [
                _buildRoleButton(AppConstants.dbRoleCustomer, AppConstants.uiRoleCustomer, Icons.person),
                const SizedBox(width: 15),
                _buildRoleButton(AppConstants.dbRoleMaster, AppConstants.uiRoleMaster, Icons.build),
              ],
            ),
            const SizedBox(height: 30),

            // Поле ввода для Имени
            const Text("Adınız", style: TextStyle(fontWeight: FontWeight.bold, color: kDarkColor)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Məsələn: Əli',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              keyboardType: TextInputType.name,
            ),
            const SizedBox(height: 20),

            // Поле ввода для Фамилии
            const Text("Soyadınız", style: TextStyle(fontWeight: FontWeight.bold, color: kDarkColor)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _surnameController,
              decoration: InputDecoration(
                hintText: 'Məsələn: Əliyev',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              keyboardType: TextInputType.name,
            ),
            const SizedBox(height: 40),

            // Кнопка завершения
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _completeRegistration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('DAXİL OL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleButton(String role, String title, IconData icon) {
    final isSelected = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? kPrimaryColor : Colors.grey.shade300,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 30, color: isSelected ? kPrimaryColor : Colors.grey),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? kPrimaryColor : kDarkColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}