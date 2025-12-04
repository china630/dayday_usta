import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/master_service.dart';
// import 'package:bolt_usta/screens/client/master_profile_screen.dart';

class MasterSearchScreen extends StatefulWidget {
  const MasterSearchScreen({super.key});

  @override
  State<MasterSearchScreen> createState() => _MasterSearchScreenState();
}

class _MasterSearchScreenState extends State<MasterSearchScreen> {
  final MasterService _masterService = MasterService();

  // Параметры фильтрации
  String? _selectedCategory; // Kateqoriya (Имя/ID)
  String? _selectedDistrict; // Rayon (Имя/ID)
  bool _onlyAvailable = false; // Status (Mövcud/Mövcud Deyil)

  // Список мастеров, который будет отображаться
  Future<List<MasterProfile>>? _mastersFuture;

  @override
  void initState() {
    super.initState();
    _searchMasters(); // Запускаем первоначальный поиск при инициализации
  }

  // Метод MasterService: searchMasters
  void _searchMasters() {
    setState(() {
      // ❗️ ИСПРАВЛЕНИЕ: Передаем аргументы как categoryId и districtId
      _mastersFuture = _masterService.searchMasters(
        categoryId: _selectedCategory, // NOTE: Предполагаем, что _selectedCategory хранит ID
        districtId: _selectedDistrict, // NOTE: Предполагаем, что _selectedDistrict хранит ID
        onlyFree: _onlyAvailable,
      );
    });
  }

  // Сброс фильтров
  void _resetFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedDistrict = null;
      _onlyAvailable = false;
    });
    _searchMasters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usta Axtar', style: TextStyle(fontWeight: FontWeight.bold)), // Искать Мастера
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetFilters,
            tooltip: 'Filtrləri Sıfırla (Сбросить фильтры)',
          ),
        ],
      ),
      body: Column(
        children: [
          // -----------------------------------------------------------
          // 1. Секция Фильтров (Rayon, Kateqoriya, Status)
          // -----------------------------------------------------------
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Категория и Район в одной строке
                Row(
                  children: [
                    Expanded(child: _buildDropdownFilter('Kateqoriya', AppConstants.serviceCategories, _selectedCategory, (v) => setState(() => _selectedCategory = v))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildDropdownFilter('Rayon', AppConstants.districts, _selectedDistrict, (v) => setState(() => _selectedDistrict = v))),
                  ],
                ),
                const SizedBox(height: 8),

                // Фильтр Статуса и Кнопка Поиска
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Mövcud (Свободен)'), // Статус: Свободен
                        value: _onlyAvailable,
                        dense: true,
                        onChanged: (bool? v) {
                          setState(() => _onlyAvailable = v ?? false);
                        },
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _searchMasters,
                      icon: const Icon(Icons.search),
                      label: const Text('Axtar'), // Поиск
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(),

          // -----------------------------------------------------------
          // 2. Секция "Ustalar" (Список Мастеров)
          // -----------------------------------------------------------
          Expanded(
            child: FutureBuilder<List<MasterProfile>>(
              future: _mastersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Xəta baş verdi: ${snapshot.error}')); // Ошибка
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Bu filtrlərlə usta tapılmadı.')); // Мастера не найдены
                }

                final masters = snapshot.data!;
                return ListView.builder(
                  itemCount: masters.length,
                  itemBuilder: (context, index) {
                    final master = masters[index];
                    return _buildMasterListItem(context, master);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Вспомогательный виджет для Dropdown-фильтра
  Widget _buildDropdownFilter(String label, List<String> items, String? currentValue, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      ),
      value: currentValue,
      hint: Text(label),
      items: items.map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  // Вспомогательный виджет для элемента списка Мастеров
  Widget _buildMasterListItem(BuildContext context, MasterProfile master) {
    // Используем заглушку для фотографии
    const placeholderImage = CircleAvatar(
      radius: 30,
      backgroundColor: Colors.grey,
      child: Icon(Icons.person, color: Colors.white),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: 2,
      child: ListTile(
        onTap: () {
          // При нажатии переходит на экран “Usta Profili”
          // Navigator.push(context, MaterialPageRoute(builder: (_) => MasterProfileScreen(masterId: master.uid, currentUserId: master.uid)));
          print('Переход на Usta Profili для: ${master.fullName}');
        },
        leading: placeholderImage, // Фото
        title: Text(master.fullName ?? 'Usta Adı', style: const TextStyle(fontWeight: FontWeight.w600)), // Ustanın Adı
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kateqoriya: ${master.categories.join(', ')}'), // Kateqoriya
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text('Reytinq: ${master.rating.toStringAsFixed(1)}'), // Reytinq
              ],
            ),
          ],
        ),
        trailing: master.verificationStatus == AppConstants.verificationVerified
            ? const Icon(Icons.verified, color: Colors.blue)
            : null,
      ),
    );
  }
}