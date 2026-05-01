import 'package:flutter/material.dart';
import 'package:dayday_usta/core/app_colors.dart'; // ✅ Цвета
import 'package:dayday_usta/screens/map_screen.dart';
import 'package:dayday_usta/screens/client/master_search_screen.dart';
import 'package:dayday_usta/screens/client/client_order_history_screen.dart';
import 'package:dayday_usta/screens/client/client_profile_screen.dart';

class ClientMainShell extends StatefulWidget {
  final String currentUserId;

  const ClientMainShell({super.key, required this.currentUserId});

  @override
  State<ClientMainShell> createState() => _ClientMainShellState();
}

class _ClientMainShellState extends State<ClientMainShell> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      MapScreen(currentUserId: widget.currentUserId),
      const MasterSearchScreen(),
      ClientOrderHistoryScreen(customerId: widget.currentUserId),
      ClientProfileScreen(currentUserId: widget.currentUserId),
    ];
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          backgroundColor: Colors.white,
          selectedItemColor: kPrimaryColor, // ✅ Мятный для активной
          unselectedItemColor: Colors.grey[400],
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          elevation: 0, // Тень мы задали контейнером выше
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.location_on_outlined),
              activeIcon: Icon(Icons.location_on),
              label: 'Axtar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              activeIcon: Icon(Icons.grid_view_rounded),
              label: 'Kataloq',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Sifarişlər',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}