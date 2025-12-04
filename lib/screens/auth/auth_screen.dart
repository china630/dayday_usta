import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:bolt_usta/services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _verificationId;
  bool _codeSent = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 1. ОТПРАВКА КОДА
  // --------------------------------------------------------------------------
  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    // ✅ ИСПРАВЛЕНИЕ: Гарантируем, что номер начинается с '+'
    String phoneNumber = _phoneController.text.trim();
    if (!phoneNumber.startsWith('+')) {
      phoneNumber = '+$phoneNumber';
    }

    try {
      await authService.verifyPhoneNumber(
        phoneNumber, // Передаем номер с '+'
            (PhoneAuthCredential credential) async {
          await _signIn(credential);
        },
            (FirebaseAuthException e) {
          setState(() {
            _errorMessage = 'Xəta: ${e.message}';
            _isLoading = false;
          });
          print('Verification Failed: ${e.message}');
        },
            (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Təsdiqləmə kodu göndərildi.')),
          );
        },
            (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Gözlənilməyən xəta: ${e.toString()}';
        _isLoading = false;
      });
      print('Unexpected error during phone verification: $e');
    }
  }

  // --------------------------------------------------------------------------
  // 2. ВЕРИФИКАЦИЯ КОДА (ПОДТВЕРЖДЕНИЕ)
  // --------------------------------------------------------------------------
  Future<void> _verifyCode() async {
    if (_verificationId == null || _codeController.text.isEmpty) return;

    setState(() => _isLoading = true);

    final authService = Provider.of<AuthService>(context, listen: false);
    final code = _codeController.text.trim();

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _signIn(credential);

    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = 'Səhv kod: ${e.code}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Gözlənilməyən xəta: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // --------------------------------------------------------------------------
  // 3. ОБЩИЙ МЕТОД ВХОДА
  // --------------------------------------------------------------------------
  Future<void> _signIn(PhoneAuthCredential credential) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      await authService.signInWithCredential(credential);
      // После входа, MainScreenRouting сам позаботится о навигации
    } catch (e) {
      setState(() {
        _errorMessage = 'Daxil olarkən xəta: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // --------------------------------------------------------------------------
  // 4. UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daxil Ol', style: TextStyle(fontWeight: FontWeight.bold)), // Войти
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Сообщение
              Text(
                _codeSent ? 'Telefonunuza göndərilən 6 rəqəmli kodu daxil edin.' : 'Telefon nömrənizi daxil edin.',
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 20),

              // Поле для номера телефона
              if (!_codeSent) ...[
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon Nömrəsi (Məs: +99450XXXXXXX)', // Номер Телефона
                    border: OutlineInputBorder(),
                    // Убираем prefixText, так как он может сбивать с толку
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Düzgün telefon nömrəsi daxil edin.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
              ],

              // Поле для кода (отображается после отправки)
              if (_codeSent) ...[
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Təsdiqləmə Kodu (Код)', // Код Верификации
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty || value.length != 6) {
                      return '6 rəqəmli kodu daxil edin.'; // Введите 6-значный код
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
              ],

              // Кнопка Действия
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : (_codeSent ? _verifyCode : _sendCode),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                  _codeSent ? 'Daxil Ol' : 'Kod Göndər', // Войти / Отправить Код
                  style: const TextStyle(fontSize: 18),
                ),
              ),

              // Сообщение об ошибке
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}