import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/services/auth_service.dart';
// !!! ИСПРАВЛЕНИЕ: Импортируем сам класс Wrapper, который находится в main.dart
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

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Создание нового профиля в Firestore
      await _authService.createNewProfile(
        uid: widget.firebaseUser.uid,
        phoneNumber: widget.firebaseUser.phoneNumber!,
        role: _selectedRole!,
        name: name,
        surname: surname,
      );

      // 2. ✅ ИСПРАВЛЕНИЕ: После успешной регистрации возвращаемся к корню (Wrapper),
      // который выполнит автоматический роутинг по роли.
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          // MaterialPageRoute(builder: (context) => MainScreenRouting()), // ❌ Старый, нерабочий код
          MaterialPageRoute(builder: (context) => const Wrapper()), // ✅ Новый рабочий код
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rol Seçimi', style: TextStyle(fontWeight: FontWeight.bold)), // Выбор Роли
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Xoş gəlmisiniz! Zəhmət olmasa, rolunuzu seçin və ilkin məlumatları daxil edin.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),

            // Выбор Роли
            Row(
              children: [
                _buildRoleButton(AppConstants.dbRoleCustomer, AppConstants.uiRoleCustomer), // Müştəri
                _buildRoleButton(AppConstants.dbRoleMaster, AppConstants.uiRoleMaster), // Usta
              ],
            ),
            const SizedBox(height: 20),

            // Поле ввода для Имени
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Ad (Имя)', // Имя
                hintText: 'Məsələn: Əli',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.name,
            ),
            const SizedBox(height: 15),

            // Поле ввода для Фамилии
            TextFormField(
              controller: _surnameController,
              decoration: const InputDecoration(
                labelText: 'Soyad (Фамилия)', // Фамилия
                hintText: 'Məsələn: Əliyev',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.name,
            ),
            const SizedBox(height: 30),

            // Кнопка завершения регистрации
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _completeRegistration,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Qeydiyyatı Tamamla', style: TextStyle(fontSize: 16)), // Завершить Регистрацию
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleButton(String role, String title) {
    final isSelected = _selectedRole == role;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              _selectedRole = role;
            });
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: isSelected ? Colors.blue.shade50 : Colors.white,
            side: BorderSide(color: isSelected ? Colors.blue : Colors.grey),
            padding: const EdgeInsets.symmetric(vertical: 20),
          ),
          child: Text(title, style: TextStyle(
            color: isSelected ? Colors.blue : Colors.black,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          )),
        ),
      ),
    );
  }
}