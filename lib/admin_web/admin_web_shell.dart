import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dayday_usta/admin_web/screens/admin_web_dashboard_screen.dart';
import 'package:dayday_usta/admin_web/screens/admin_web_orders_screen.dart';
import 'package:dayday_usta/admin_web/screens/admin_web_settings_screen.dart';
import 'package:dayday_usta/admin_web/screens/admin_web_verifications_screen.dart';
import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/screens/auth/auth_screen.dart';
import 'package:dayday_usta/services/auth_service.dart';

class AdminWebShell extends StatefulWidget {
  final String userId;

  const AdminWebShell({required this.userId, super.key});

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  int _index = 0;

  Future<void> _signOut() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    await auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      AdminWebDashboardScreen(userId: widget.userId),
      const AdminWebVerificationsScreen(),
      const AdminWebOrdersScreen(),
      const AdminWebSettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin paneli (web)'),
        actions: [
          IconButton(
            tooltip: 'Çıxış',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: Colors.white,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: const IconThemeData(color: kPrimaryColor),
            selectedLabelTextStyle: const TextStyle(
              color: kPrimaryColor,
              fontWeight: FontWeight.w600,
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Ana səhifə'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.verified_user_outlined),
                selectedIcon: Icon(Icons.verified_user),
                label: Text('Təsdiqlər'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.list_alt_outlined),
                selectedIcon: Icon(Icons.list_alt),
                label: Text('Sifarişlər'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Parametrlər'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: pages,
            ),
          ),
        ],
      ),
    );
  }
}
