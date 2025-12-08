import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bolt_usta/core/app_colors.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/master_service.dart';
import 'package:bolt_usta/services/metadata_service.dart';
import 'package:bolt_usta/screens/client/master_profile_screen.dart';

class MasterSearchScreen extends StatefulWidget {
  const MasterSearchScreen({super.key});

  @override
  State<MasterSearchScreen> createState() => _MasterSearchScreenState();
}

class _MasterSearchScreenState extends State<MasterSearchScreen> {
  final MasterService _masterService = MasterService();
  final MetadataService _metadataService = MetadataService();

  List<MasterProfile> _masters = [];
  bool _isLoading = true;

  List<String> _categories = [];
  List<String> _districts = [];
  bool _isMetadataLoading = true;

  String? _selectedCategory;
  String? _selectedDistrict;
  bool _onlyFree = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      final results = await Future.wait([
        _metadataService.getCategories(),
        _metadataService.getDistricts(),
      ]);

      if (mounted) {
        setState(() {
          _categories = results[0];
          _districts = results[1];
          _isMetadataLoading = false;
        });
      }

      _loadMasters();
    } catch (e) {
      debugPrint("Init error: $e");
      if (mounted) setState(() => _isMetadataLoading = false);
    }
  }

  Future<void> _loadMasters() async {
    setState(() => _isLoading = true);

    try {
      final results = await _masterService.searchMasters(
        categoryId: _selectedCategory,
        districtId: _selectedDistrict,
        onlyFree: _onlyFree,
      );

      if (mounted) {
        setState(() {
          _masters = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        // ✅ ОБНОВЛЕНО: Мятный фон, белый текст
        title: const Text("Usta Kataloqu", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: kBackgroundColor,
      body: Column(
        children: [
          // Блок фильтров
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            ),
            child: _isMetadataLoading
                ? const LinearProgressIndicator(color: kPrimaryColor)
                : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                          "Xidmət",
                          _selectedCategory,
                          _categories,
                              (val) {
                            setState(() => _selectedCategory = val);
                            _loadMasters();
                          }
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDropdown(
                          "Rayon",
                          _selectedDistrict,
                          _districts,
                              (val) {
                            setState(() => _selectedDistrict = val);
                            _loadMasters();
                          }
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text("Yalnız boş ustalar", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  value: _onlyFree,
                  activeColor: kPrimaryColor,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (val) {
                    setState(() => _onlyFree = val);
                    _loadMasters();
                  },
                )
              ],
            ),
          ),

          // Список мастеров
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _masters.isEmpty
                ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 10),
                const Text("Bu kriteriyalara uyğun usta tapılmadı", style: TextStyle(color: Colors.grey)),
              ],
            ))
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _masters.length,
              itemBuilder: (context, index) {
                final master = _masters[index];
                return _buildMasterCard(master, currentUserId);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String hint, String? value, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          items: [
            const DropdownMenuItem(value: null, child: Text("Hamısı", style: TextStyle(fontWeight: FontWeight.bold))),
            ...items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildMasterCard(MasterProfile master, String currentUserId) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MasterProfileScreen(
                masterId: master.uid,
                currentUserId: currentUserId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: kBackgroundColor,
                child: const Icon(Icons.person, size: 30, color: Colors.grey),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(master.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kDarkColor)),
                    const SizedBox(height: 4),
                    Text(master.categories.join(", "), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        Text(" ${master.rating.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 12),
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: master.status == 'free' ? kPrimaryColor : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          master.status == 'free' ? "Boşdur" : "Məşğuldur",
                          style: TextStyle(
                              color: master.status == 'free' ? kPrimaryColor : Colors.grey,
                              fontWeight: FontWeight.w600,
                              fontSize: 12
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}