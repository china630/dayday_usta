import 'package:flutter/material.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/admin_service.dart';
import 'package:bolt_usta/core/app_colors.dart'; // ✅ Цвета

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

  Future<void> _verifyMaster() async {
    setState(() => _isLoading = true);
    try {
      await _adminService.adminVerifyMaster(widget.masterProfile.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Usta ${widget.masterProfile.fullName} təsdiqləndi!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError('Xəta: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectMaster() async {
    if (_rejectionReasonController.text.trim().isEmpty) {
      _showError('Zəhmət olmasa, imtina səbəbini qeyd edin.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _adminService.adminRejectMaster(widget.masterProfile.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usta imtina edildi.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError('Xəta: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final master = widget.masterProfile;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: Text(master.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Usta Məlumatı'),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Ad Soyad', master.fullName),
                  const Divider(),
                  _buildDetailRow('Telefon', master.phoneNumber),
                  const Divider(),
                  _buildDetailRow('Kateqoriyalar', master.categories.join(', ')),
                  const Divider(),
                  _buildDetailRow('Rayonlar', master.districts.join(', ')),
                ],
              ),
            ),

            const SizedBox(height: 25),
            _buildSectionTitle('Sənədlər'),
            _buildDocumentViewer('Selfie (Üz şəkili)', Icons.face),
            const SizedBox(height: 15),
            _buildDocumentViewer('Şəxsiyyət Vəsiqəsi', Icons.credit_card),

            const SizedBox(height: 25),
            _buildSectionTitle('Qərar'),

            TextField(
              controller: _rejectionReasonController,
              decoration: InputDecoration(
                hintText: 'İmtina səbəbi (yalnız imtina zamanı)...',
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(15),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 30),

            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: kPrimaryColor))
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _rejectMaster,
                      icon: const Icon(Icons.close, color: Colors.white),
                      label: const Text('İMTİNA ET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _verifyMaster,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('EYNİLƏŞDİR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 5),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kDarkColor)),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: kDarkColor)),
        ],
      ),
    );
  }

  Widget _buildDocumentViewer(String title, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: kDarkColor)),
          const SizedBox(height: 5),
          const Text("(Simulyasiya: Şəkil)", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}