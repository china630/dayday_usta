import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/services/auth_service.dart';
import 'package:dayday_usta/models/user_profile.dart';
import 'package:dayday_usta/screens/auth/auth_screen.dart';
import 'package:dayday_usta/screens/debug/debug_log_screen.dart';

import '../../widgets/balance_card.dart';
import '../payment/payment_instruction_screen.dart';
import '../payment/transaction_history_screen.dart';

class ClientProfileScreen extends StatefulWidget {
  final String currentUserId;

  const ClientProfileScreen({Key? key, required this.currentUserId}) : super(key: key);

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final AuthService _authService = AuthService();

  String _selectedLanguage = 'AZ';
  int _debugTapCount = 0;

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
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
    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.currentUserId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(child: CircularProgressIndicator(color: kPrimaryColor)),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Scaffold(
              appBar: AppBar(title: const Text("Xəta")),
              body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("İstifadəçi tapılmadı"),
                      TextButton(onPressed: _signOut, child: const Text("Çıxış"))
                    ],
                  )
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          data['uid'] = widget.currentUserId;
          final userProfile = UserProfile.fromFirestore(data);

          return Scaffold(
            backgroundColor: kBackgroundColor,
            body: Column(
              children: [
                // --- ШАПКА (Остается фиксированной) ---
                Container(
                  // 🛠️ ИЗМЕНЕНИЕ: Уменьшили отступы (было top: 50, bottom: 20)
                  padding: const EdgeInsets.only(top: 35, bottom: 15),
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: kPrimaryColor,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
                  ),
                  child: Column(
                    children: [
                      // 🛠️ ИЗМЕНЕНИЕ: Удалили Text("Profil") и SizedBox под ним

                      // Аватар с секретной кнопкой
                      GestureDetector(
                        onTap: () {
                          _debugTapCount++;
                          if (_debugTapCount >= 5) {
                            _debugTapCount = 0;
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogScreen()));
                          }
                        },
                        child: Container(
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
                      ),
                      const SizedBox(height: 15),

                      Text(
                        userProfile.fullName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        userProfile.phoneNumber,
                        style: const TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                // --- ТЕЛО (Белая карточка с прокруткой) ---
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                      ],
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [

                        // 💰 БАЛАНС
                        BalanceCard(
                          balance: userProfile.balance,
                          frozenBalance: userProfile.frozenBalance,
                          onTopUpPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PaymentInstructionScreen(
                                  userPhoneNumber: userProfile.phoneNumber,
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 20),

                        // 📜 ИСТОРИЯ
                        _buildProfileOption(
                          icon: Icons.receipt_long,
                          text: "Ödəniş Tarixçəsi",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TransactionHistoryScreen(
                                  userId: widget.currentUserId,
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 15),
                        const Divider(),
                        const SizedBox(height: 15),

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

                        const SizedBox(height: 30),

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
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
    );
  }

  Widget _buildProfileOption({required IconData icon, required String text, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 0),
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: kPrimaryColor),
        ),
        title: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: kDarkColor)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
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