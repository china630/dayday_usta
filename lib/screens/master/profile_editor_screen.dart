import 'package:flutter/material.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/master_service.dart';
import 'package:bolt_usta/services/metadata_service.dart';
import 'package:bolt_usta/core/app_colors.dart';

class ProfileEditorScreen extends StatefulWidget {
  final MasterProfile initialProfile;

  const ProfileEditorScreen({required this.initialProfile, super.key});

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  final MasterService _masterService = MasterService();
  final MetadataService _metadataService = MetadataService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _achievementsController;
  late TextEditingController _priceListController;

  late Set<String> _selectedCategories;
  late Set<String> _selectedDistricts;

  List<String> _availableCategories = [];
  List<String> _availableDistricts = [];

  bool _isSaving = false;
  bool _isDataLoading = true;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;

    _achievementsController = TextEditingController(text: profile.achievements);
    _priceListController = TextEditingController(text: profile.priceList);

    _selectedCategories = Set.from(profile.categories);
    _selectedDistricts = Set.from(profile.districts);

    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final results = await Future.wait([
        _metadataService.getCategories(),
        _metadataService.getDistricts(),
      ]);

      if (mounted) {
        setState(() {
          _availableCategories = results[0];
          _availableDistricts = results[1];
          _isDataLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading metadata: $e");
      if (mounted) setState(() => _isDataLoading = false);
    }
  }

  @override
  void dispose() {
    _achievementsController.dispose();
    _priceListController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategories.isEmpty || _selectedDistricts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zəhmət olmasa, ən azı bir Kateqoriya və Rayon seçin.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // ✅ ИСПРАВЛЕНО: Добавлен обязательный параметр 'role'
      final profileToUpdate = MasterProfile(
        uid: widget.initialProfile.uid,
        phoneNumber: widget.initialProfile.phoneNumber,
        role: widget.initialProfile.role, // <--- ВОТ ЗДЕСЬ ИСПРАВЛЕНИЕ
        createdAt: widget.initialProfile.createdAt,
        name: widget.initialProfile.name,
        surname: widget.initialProfile.surname,
        fcmToken: widget.initialProfile.fcmToken,

        achievements: _achievementsController.text.trim(),
        priceList: _priceListController.text.trim(),
        categories: _selectedCategories.toList(),
        districts: _selectedDistricts.toList(),
        status: widget.initialProfile.status,
        verificationStatus: widget.initialProfile.verificationStatus,
        rating: widget.initialProfile.rating,
        viewsCount: widget.initialProfile.viewsCount,
        callsCount: widget.initialProfile.callsCount,
        savesCount: widget.initialProfile.savesCount,
      );

      await _masterService.updateMasterProfile(profileToUpdate);

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xəta baş verdi, yenidən cəhd edin.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDataLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Redaktoru'),
        backgroundColor: kBackgroundColor,
        foregroundColor: kDarkColor,
        elevation: 0,
      ),
      backgroundColor: kBackgroundColor,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMultiSelectField(
                title: 'Xidmət Göstərilən Rayonlar',
                items: _availableDistricts,
                selectedItems: _selectedDistricts,
                onSelectionChanged: (selected) => setState(() => _selectedDistricts = selected.toSet()),
                icon: Icons.location_on,
              ),
              const SizedBox(height: 24),

              _buildMultiSelectField(
                title: 'Xidmət Kateqoriyaları',
                items: _availableCategories,
                selectedItems: _selectedCategories,
                onSelectionChanged: (selected) => setState(() => _selectedCategories = selected.toSet()),
                icon: Icons.category,
              ),
              const SizedBox(height: 24),

              _buildTextArea(_achievementsController, 'Haqqımda (Özünüz haqqında)', 5),
              const SizedBox(height: 20),

              _buildTextArea(_priceListController, 'Qiymətlər (Xidmətlər və qiymətlər)', 8),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveProfile,
                  icon: _isSaving ? const SizedBox.shrink() : const Icon(Icons.save, color: Colors.white),
                  label: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Yadda Saxla', style: TextStyle(fontSize: 18, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextArea(TextEditingController controller, String label, int maxLines) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        fillColor: Colors.white,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        alignLabelWithHint: true,
      ),
      maxLines: maxLines,
    );
  }

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
            Icon(icon, color: kPrimaryColor),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kDarkColor)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: items.isEmpty
              ? const Text("Siyahı boşdur", style: TextStyle(color: Colors.grey))
              : Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: items.map((item) {
              final isSelected = selectedItems.contains(item);
              return FilterChip(
                label: Text(item, style: TextStyle(color: isSelected ? Colors.white : kDarkColor, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
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
                selectedColor: kPrimaryColor,
                backgroundColor: Colors.grey[100],
                checkmarkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? kPrimaryColor : Colors.transparent)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}