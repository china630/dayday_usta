import 'package:flutter/material.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/admin_service.dart';

class AdminVerificationScreen extends StatefulWidget {
  final MasterProfile masterProfile;

  const AdminVerificationScreen({required this.masterProfile, super.key});

  @override
  State<AdminVerificationScreen> createState() => _AdminVerificationScreenState();
}

class _AdminVerificationScreenState extends State<AdminVerificationScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _rejectionReasonController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _rejectionReasonController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // ЛОГИКА ВЕРИФИКАЦИИ/ОТКЛОНЕНИЯ
  // --------------------------------------------------------------------------

  // Действие: Eyniləşdir (Верифицировать)
  Future<void> _verifyMaster() async {
    setState(() => _isLoading = true);
    try {
      // ❗️ Вызов метода AdminService: adminVerifyMaster
      await _adminService.adminVerifyMaster(widget.masterProfile.uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Usta ${widget.masterProfile.fullName} Eyniləşdirildi.')), // Мастер верифицирован.
        );
        Navigator.pop(context, true); // Возвращаемся на Dashboard
      }
    } catch (e) {
      _showError('Təsdiqləmə zamanı xəta: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Действие: İmtina Et (Отклонить)
  Future<void> _rejectMaster() async {
    final reason = _rejectionReasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zəhmət olmasa, imtina səbəbini qeyd edin.')), // Пожалуйста, укажите причину отказа.
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // ❗️ Вызов метода AdminService: adminRejectMaster
      await _adminService.adminRejectMaster(widget.masterProfile.uid);

      // В реальном проекте здесь может быть отправка уведомления Мастеру с причиной
      print('İmtina səbəbi: $reason');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Usta ${widget.masterProfile.fullName} imtina edildi.')), // Мастер отклонен.
        );
        Navigator.pop(context, true); // Возвращаемся на Dashboard
      }
    } catch (e) {
      _showError('İmtina zamanı xəta: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final master = widget.masterProfile;

    return Scaffold(
      appBar: AppBar(title: Text('Usta Eyniləşdirmə: ${master.fullName}')), // Верификация Мастера
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -----------------------------------------------------------
            // 1. Детали Мастера
            // -----------------------------------------------------------
            _buildSectionTitle('Usta Məlumatı'), // Информация о Мастере
            _buildDetailRow('Ad Soyad', master.fullName ?? 'N/A'),
            _buildDetailRow('Telefon', master.phoneNumber),
            _buildDetailRow('Kateqoriyalar', master.categories.join(', ')),
            const SizedBox(height: 30),

            // -----------------------------------------------------------
            // 2. Секция Скан-Копий Документов
            // -----------------------------------------------------------
            _buildSectionTitle('Yüklənmiş Sənədlər'), // Загруженные Документы

            // Placeholder для Selfie
            _buildDocumentViewer('Selfie (Üz şəkili)', 'Selfie Sənədi URL'),
            const SizedBox(height: 15),

            // Placeholder для Фото Документа
            _buildDocumentViewer('Sənədin Şəkili', 'Şəxsiyyət Sənədi URL'),
            const SizedBox(height: 30),

            // -----------------------------------------------------------
            // 3. Причина Отклонения (Требуется для "İmtina Et")
            // -----------------------------------------------------------
            _buildSectionTitle('İmtina Səbəbi'), // Причина Отклонения
            TextField(
              controller: _rejectionReasonController,
              decoration: const InputDecoration(
                hintText: 'Məsələn: Sənəd bulanıqdır, ya da şəkil köhnədir.', // Например: Документ размыт или фото старое.
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 40),

            // -----------------------------------------------------------
            // 4. Кнопки Действий
            // -----------------------------------------------------------
            Row(
              children: [
                // Кнопка Отклонить
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _rejectMaster,
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: const Text('İmtina Et', style: TextStyle(color: Colors.white)), // Отклонить
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Кнопка Верифицировать
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _verifyMaster,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Eyniləşdir', style: TextStyle(color: Colors.white)), // Верифицировать
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
            if (_isLoading)
              const Center(child: Padding(
                padding: EdgeInsets.only(top: 20.0),
                child: CircularProgressIndicator(),
              )),
          ],
        ),
      ),
    );
  }

  // Вспомогательный виджет для заголовков
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 15),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  // Вспомогательный виджет для отображения деталей
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // Вспомогательный виджет для просмотра документа
  Widget _buildDocumentViewer(String title, String imageUrlPlaceholder) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.image, size: 40, color: Colors.grey),
              const SizedBox(height: 5),
              Text('URL: $imageUrlPlaceholder (Simulyasiya)', style: const TextStyle(color: Colors.grey)),
              const Text('(Şəkili Bura Yüklə)', style: TextStyle(color: Colors.grey)), // Загрузить фото сюда
            ],
          ),
          // В реальном проекте здесь будет Image.network(imageUrl)
        ),
      ],
    );
  }
}