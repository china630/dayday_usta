// lib/screens/client/client_main_shell.dart

import 'package:flutter/material.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/screens/map_screen.dart'; // Карта/Bolt
import 'package:bolt_usta/screens/client/master_search_screen.dart'; // Справочник Мастеров

class ClientMainShell extends StatefulWidget {
  final String currentUserId;

  const ClientMainShell({super.key, required this.currentUserId});

  @override
  State<ClientMainShell> createState() => _ClientMainShellState();
}

class _ClientMainShellState extends State<ClientMainShell> {
  int _selectedIndex = 0;
  final AuthService _authService = AuthService();

  // Список экранов для BottomNavigationBar
  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      // 0: Срочный Вызов (Карта) - Без AppBar, как вы просили.
      MapScreen(currentUserId: widget.currentUserId),
      // 1: Справочник Мастеров (Каталог)
      const MasterSearchScreen(),
      // 2: Заглушка для Профиля
      Center(child: Text('Профиль Пользователя ID: ${widget.currentUserId}')),
    ];
  }

  void _onItemTapped(int index) {
    // Если нажат пункт "Профиль/Выход" (index 2), показываем диалог выхода
    if (index == 2) {
      _showLogoutDialog(context);
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Выход'),
          content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Выйти', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop();
                await _authService.signOut();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Главный контейнер (Shell) без своего AppBar
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Bolt/Xəritə',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Usta Axtarışı',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil/Çıxış',
          ),
        ],
        currentIndex: _selectedIndex,
        // Стиль для активной кнопки
        selectedItemColor: Colors.blue.shade700,
        onTap: _onItemTapped,
      ),
    );
  }
}