import 'package:flutter/material.dart';
import 'package:dayday_usta/services/master_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class MasterVerificationScreen extends StatefulWidget {
  final String masterId;

  const MasterVerificationScreen({required this.masterId, super.key});

  @override
  State<MasterVerificationScreen> createState() => _MasterVerificationScreenState();
}

class _MasterVerificationScreenState extends State<MasterVerificationScreen> {
  final MasterService _masterService = MasterService();
  final ImagePicker _picker = ImagePicker();

  // Файлы для загрузки
  File? _selfieFile; // Selfie (Фото лица)
  File? _docFile;    // Sənədin Şəkili (Фото документа)

  bool _isLoading = false;

  // --------------------------------------------------------------------------
  // ЛОГИКА ВЫБОРА ФОТО
  // --------------------------------------------------------------------------

  Future<void> _pickImage(bool isSelfie) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera, // Мастер фоткает на камеру телефона
      imageQuality: 50, // Снижаем качество для быстрой загрузки
    );

    if (pickedFile != null) {
      setState(() {
        if (isSelfie) {
          _selfieFile = File(pickedFile.path);
        } else {
          _docFile = File(pickedFile.path);
        }
      });
    }
  }

  // --------------------------------------------------------------------------
  // ЛОГИКА ОТПРАВКИ НА ВЕРИФИКАЦИЮ
  // --------------------------------------------------------------------------

  Future<void> _submitForVerification() async {
    if (_selfieFile == null || _docFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zəhmət olmasa, hər iki şəkili yükləyin.')), // Пожалуйста, загрузите оба фото
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // ❗️ Отправка на верификацию через MasterService
      await _masterService.submitVerificationDocs(
        masterId: widget.masterId,
        selfieFile: _selfieFile!,
        docFile: _docFile!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sənədlər uğurla göndərildi. Gözləyin.')), // Документы успешно отправлены. Ожидайте.
        );
        Navigator.pop(context); // Возвращаемся на Dashboard
      }
    } catch (e) {
      print('Ошибка при отправке верификации: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xəta baş verdi, yenidən cəhd edin.')),
      );
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
      appBar: AppBar(title: const Text('Eyniləşdirmə')), // Верификация
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Şəxsiyyətinizi təsdiqləmək üçün aşağıdakı sənədləri yükləyin:', // Загрузите документы для подтверждения личности:
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 30),

            // -----------------------------------------------------------
            // 1. Поле "Selfie" (Фото лица)
            // -----------------------------------------------------------
            _buildImagePickerCard(
              title: 'Selfie (Üz şəkili)',
              file: _selfieFile,
              onTap: () => _pickImage(true),
              icon: Icons.camera_front,
              description: 'Zəhmət olmasa, üzünüzün aydın selfisini çəkin.', // Сделайте четкое селфи.
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------
            // 2. Поле "Sənədin Şəkili" (Фото документа)
            // -----------------------------------------------------------
            _buildImagePickerCard(
              title: 'Sənədin Şəkili (Foto dokument)',
              file: _docFile,
              onTap: () => _pickImage(false),
              icon: Icons.badge,
              description: 'Şəxsiyyət vəsiqəsi, pasport və ya sürücülük vəsiqəsi.', // Удостоверение личности, паспорт или права.
            ),
            const SizedBox(height: 40),

            // -----------------------------------------------------------
            // 3. Кнопка "Göndər" (Отправить)
            // -----------------------------------------------------------
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitForVerification,
                icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.send, color: Colors.white),
                label: _isLoading
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: CircularProgressIndicator(color: Colors.white))
                    : const Text('Göndər', style: TextStyle(fontSize: 18, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Вспомогательный виджет для карточки выбора фото
  Widget _buildImagePickerCard({
    required String title,
    required File? file,
    required VoidCallback onTap,
    required IconData icon,
    required String description,
  }) {
    return Card(
      elevation: 3,
      child: ListTile(
        leading: Icon(icon, size: 30, color: Colors.grey.shade700),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
        trailing: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: file != null ? Colors.green.shade50 : Colors.blue.shade50,
              border: Border.all(color: file != null ? Colors.green : Colors.blue),
              borderRadius: BorderRadius.circular(8),
            ),
            child: file != null
                ? const Icon(Icons.check, color: Colors.green, size: 24)
                : const Icon(Icons.camera_alt, color: Colors.blue, size: 24),
          ),
        ),
      ),
    );
  }
}