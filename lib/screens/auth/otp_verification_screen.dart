import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:dayday_usta/services/auth_service.dart';
import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/core/app_constants.dart'; // ✅ Добавлен импорт констант
import 'package:dayday_usta/screens/auth/role_selection_screen.dart';
import 'package:dayday_usta/screens/client/client_main_shell.dart';
import 'package:dayday_usta/screens/master/master_dashboard_screen.dart';
import 'package:dayday_usta/screens/admin/admin_dashboard_screen.dart'; // ✅ Импорт Админки
import 'package:dayday_usta/services/user_profile_service.dart';
import 'package:dayday_usta/models/master_profile.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;

  const OtpVerificationScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;

  Timer? _timer;
  int _start = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _start = 60;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_start == 0) {
        setState(() {
          _canResend = true;
          timer.cancel();
        });
      } else {
        setState(() {
          _start--;
        });
      }
    });
  }

  void _resendCode() {
    if (!_canResend) return;
    _startTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Kod yenidən göndərildi!")),
    );
  }

  Future<void> _verifyOtp() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: code,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        await _checkUserProfileAndRedirect();
      }

    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      String message = "Xəta baş verdi";
      if (e.code == 'invalid-verification-code') {
        message = "Kod yalnışdır";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
      _codeController.clear();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Xəta: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // ✅ ИСПРАВЛЕННЫЙ МЕТОД РОУТИНГА
  Future<void> _checkUserProfileAndRedirect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userProfileService = Provider.of<UserProfileService>(context, listen: false);
    final profile = await userProfileService.getUserProfile(user.uid);

    if (!mounted) return;

    if (profile == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => RoleSelectionScreen(firebaseUser: user)),
            (route) => false,
      );
    }
    // ✅ АДМИН (Добавлено условие)
    else if (profile.role == AppConstants.dbRoleAdmin || profile.role == 'admin') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AdminDashboardScreen(currentUserId: user.uid)),
            (route) => false,
      );
    }
    // КЛИЕНТ
    else if (profile.role == AppConstants.dbRoleCustomer) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => ClientMainShell(currentUserId: user.uid)),
            (route) => false,
      );
    }
    // МАСТЕР
    else if (profile.role == AppConstants.dbRoleMaster) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MasterDashboardScreen(
            masterId: user.uid,
            masterProfile: profile as MasterProfile
        )),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kDarkColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                "SMS Təsdiqi",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kDarkColor),
              ),
              const SizedBox(height: 10),
              Text(
                "Kodu ${widget.phoneNumber} nömrəsinə göndərdik.",
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),

              const SizedBox(height: 40),

              Stack(
                children: [
                  Opacity(
                    opacity: 0,
                    child: TextFormField(
                      controller: _codeController,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onChanged: (val) {
                        setState(() {});
                        if (val.length == 6) {
                          _verifyOtp();
                        }
                      },
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _focusNode.requestFocus(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        return _buildDigitBox(index);
                      }),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              Center(
                child: Column(
                  children: [
                    if (!_canResend)
                      Text(
                        "Kodu yenidən göndər: 00:${_start.toString().padLeft(2, '0')}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),

                    if (_canResend)
                      TextButton(
                        onPressed: _resendCode,
                        child: const Text(
                          "Kodu yenidən göndər",
                          style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_codeController.text.length == 6 && !_isLoading)
                      ? _verifyOtp
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("TƏSDİQLƏ", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDigitBox(int index) {
    final text = _codeController.text;
    final isFilled = index < text.length;
    final char = isFilled ? text[index] : "";
    final isFocused = index == text.length;

    return Container(
      width: 45,
      height: 55,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: (isFocused || isFilled) ? kPrimaryColor : Colors.grey.shade300,
          width: (isFocused || isFilled) ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: isFocused
            ? [BoxShadow(color: kPrimaryColor.withOpacity(0.2), blurRadius: 8, spreadRadius: 1)]
            : [],
      ),
      child: Center(
        child: Text(
          char,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kDarkColor),
        ),
      ),
    );
  }
}