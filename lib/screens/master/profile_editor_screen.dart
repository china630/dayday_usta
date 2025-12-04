import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/master_service.dart';

class ProfileEditorScreen extends StatefulWidget {
  final MasterProfile initialProfile;

  const ProfileEditorScreen({required this.initialProfile, super.key});

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  final MasterService _masterService = MasterService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _achievementsController;
  late TextEditingController _priceListController;

  // Множественный выбор
  late Set<String> _selectedCategories;
  late Set<String> _selectedDistricts;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;

    _achievementsController = TextEditingController(text: profile.achievements);
    _priceListController = TextEditingController(text: profile.priceList);

    // Инициализируем выбранные элементы из текущего профиля
    _selectedCategories = Set.from(profile.categories);
    _selectedDistricts = Set.from(profile.districts);
  }

  @override
  void dispose() {
    _achievementsController.dispose();
    _priceListController.dispose();
    super.dispose();
  }

  // Логика кнопки "Yadda Saxla" (Сохранить)
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedCategories.isEmpty || _selectedDistricts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zəhmət olmasa, ən azı bir Kateqoriya və Rayon seçin.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Обновляем базовую информацию профиля (текстовые поля)
      // Мы не меняем name/surname здесь для простоты, но можно добавить
      final updatedProfileBase = widget.initialProfile; // Используем существующий объект как базу
      // В реальном приложении лучше использовать метод copyWith, но здесь мы просто обновляем поля через сервис
      // Создаем временный объект для передачи данных в updateMasterProfile

      // Нам нужно передать все обязательные поля в конструктор, даже если мы их не меняем
      final profileToUpdate = MasterProfile(
        uid: widget.initialProfile.uid,
        phoneNumber: widget.initialProfile.phoneNumber,
        createdAt: widget.initialProfile.createdAt,
        name: widget.initialProfile.name,
        surname: widget.initialProfile.surname,
        fcmToken: widget.initialProfile.fcmToken,
        // Обновляемые поля:
        achievements: _achievementsController.text.trim(),
        priceList: _priceListController.text.trim(),
        // Остальные поля остаются как были (сервис обновит только переданные)
        categories: _selectedCategories.toList(),
        districts: _selectedDistricts.toList(),
        status: widget.initialProfile.status,
        verificationStatus: widget.initialProfile.verificationStatus,
        rating: widget.initialProfile.rating,
        viewsCount: widget.initialProfile.viewsCount,
        callsCount: widget.initialProfile.callsCount,
        savesCount: widget.initialProfile.savesCount,
      );

      // Обновляем текстовые данные
      await _masterService.updateMasterProfile(profileToUpdate);

      // 2. ❗️ ОБНОВЛЯЕМ ФИЛЬТРЫ (Критический шаг для поиска)
      await _masterService.updateMasterSearchFilters(
          widget.initialProfile.uid,
          _selectedCategories.toList(),
          _selectedDistricts.toList()
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil uğurla yeniləndi!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Ошибка сохранения профиля: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xəta baş verdi, yenidən cəhd edin.')),
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
      appBar: AppBar(title: const Text('Profil Redaktoru')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Поле выбора "Rayonlar" (Районы)
              _buildMultiSelectField(
                title: 'Xidmət Göstərilən Rayonlar',
                items: AppConstants.districts, // Используем константы для выбора
                selectedItems: _selectedDistricts,
                onSelectionChanged: (selected) => setState(() => _selectedDistricts = selected.toSet()),
                icon: Icons.location_on,
              ),
              const SizedBox(height: 20),

              // 2. Поле выбора "Kateqoriyalar" (Категории)
              _buildMultiSelectField(
                title: 'Xidmət Kateqoriyaları',
                items: AppConstants.serviceCategories, // Используем константы для выбора
                selectedItems: _selectedCategories,
                onSelectionChanged: (selected) => setState(() => _selectedCategories = selected.toSet()),
                icon: Icons.category,
              ),
              const SizedBox(height: 20),

              // 3. Поле "Haqqımda"
              _buildTextArea(_achievementsController, 'Haqqımda (Özünüz haqqında)', 5),
              const SizedBox(height: 20),

              // 4. Поле "Qiymətlər"
              _buildTextArea(_priceListController, 'Qiymətlər (Xidmətlər və qiymətlər)', 8),
              const SizedBox(height: 40),

              // Кнопка сохранения
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveProfile,
                  icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.save, color: Colors.white),
                  label: _isLoading
                      ? const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: CircularProgressIndicator(color: Colors.white))
                      : const Text('Yadda Saxla', style: TextStyle(fontSize: 18, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Вспомогательный виджет для многострочных текстовых полей
  Widget _buildTextArea(TextEditingController controller, String label, int maxLines) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      maxLines: maxLines,
    );
  }

  // Вспомогательный виджет для множественного выбора (FilterChip)
  Widget _buildMultiSelectField({
    required String title,
    required List<String> items,
    required Set<String> selectedItems,
    required Function(List<String>) onSelectionChanged,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8.0,
          children: items.map((item) {
            final isSelected = selectedItems.contains(item);
            return FilterChip(
              label: Text(item),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    selectedItems.add(item);
                  } else {
                    selectedItems.remove(item);
                  }
                  onSelectionChanged(selectedItems.toList());
                });
              },
              selectedColor: Colors.blue.withOpacity(0.2),
              checkmarkColor: Colors.blue.shade900,
            );
          }).toList(),
        ),
      ],
    );
  }
}