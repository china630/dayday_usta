import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/models/review.dart';
import 'package:bolt_usta/services/master_service.dart';
import 'package:bolt_usta/services/review_service.dart';
// import 'package:bolt_usta/screens/client/review_form_screen.dart'; // Экран Отзывов

class MasterProfileScreen extends StatefulWidget {
  final String masterId;
  final String currentUserId; // ID текущего Клиента для закладок и звонков

  const MasterProfileScreen({
    required this.masterId,
    required this.currentUserId,
    super.key
  });

  @override
  State<MasterProfileScreen> createState() => _MasterProfileScreenState();
}

class _MasterProfileScreenState extends State<MasterProfileScreen> {
  final MasterService _masterService = MasterService();
  final ReviewService _reviewService = ReviewService();

  // Переменные состояния для закладок
  bool _isSaved = false;
  MasterProfile? _masterProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMasterProfile();
    // ❗️ При запуске экрана: обновляется поле views_count+1 в коллекции Мастера.
    // Это должно быть реализовано через Cloud Function, которая вызывается
    // после получения данных профиля, чтобы избежать избыточных вызовов.
    // Здесь мы имитируем вызов метода, который запустит триггер на бэкенде.
    _masterService.incrementViewsCount(widget.masterId);
  }

  Future<void> _loadMasterProfile() async {
    try {
      // Здесь должен быть метод getMasterProfile, который возвращает MasterProfile
      // Но для простоты используем заглушку или прямое получение данных:
      final snapshot = await _masterService.getProfileData(widget.masterId); // Предположим, что MasterService имеет этот метод

      if (snapshot != null) {
        setState(() {
          _masterProfile = snapshot;
          // Логика проверки, находится ли мастер в закладках клиента (здесь пропущена, должна быть в MasterService)
          _isSaved = snapshot.savesCount % 2 == 0; // Имитация: четное число = сохранено
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки профиля: $e');
      setState(() => _isLoading = false);
    }
  }

  // Действие: Звонок (Zəng Et)
  void _callMaster() {
    // ❗️ Обновление поля calls_count+1 в коллекции Мастера.
    _masterService.incrementCallsCount(widget.masterId);

    // В реальном проекте: launchUrl(Uri.parse('tel:${_masterProfile!.phoneNumber}'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Usta zəng edilir... (calls_count +1)')),
    );
  }

  // Действие: Сохранить/Закладка (Yadda Saxla)
  Future<void> _toggleSave() async {
    // ❗️ Добавляет/удаляет ID мастера в массив saved_masters клиента и обновляет saves_count Мастера.

    // В реальном проекте: await _masterService.toggleSaveMaster(widget.currentUserId, widget.masterId);
    setState(() {
      _isSaved = !_isSaved;
    });

    final action = _isSaved ? 'Əlavə edildi' : 'Silindi';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Usta uğurla $action (saves_count yenilənir)')), // Мастер успешно добавлен/удален
    );
  }

  // Действие: Оставить Отзыв (Rəy Bildir)
  void _openReviewScreen() {
    // Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewFormScreen(masterId: widget.masterId)));
    print('Открывает экран Rəy Bildir');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_masterProfile == null) {
      return const Scaffold(appBar: AppBar(title: Text('Usta Profili')), body: Center(child: Text('Usta tapılmadı.')));
    }

    final master = _masterProfile!;

    return Scaffold(
      appBar: AppBar(title: Text(master.fullName ?? 'Usta Profili')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -----------------------------------------------------------
            // 1. ИМЯ, ФОТО, СТАТУС ВЕРИФИКАЦИИ
            // -----------------------------------------------------------
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage('https://via.placeholder.com/150'), // Крупное фото
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          master.fullName ?? 'Ad Soyadı',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), // Ad Soyadı
                        ),
                        const SizedBox(height: 5),
                        // Значок "Eyniləşdirilib" (Верифицирован)
                        if (master.verificationStatus == AppConstants.verificationVerified)
                          Row(
                            children: [
                              const Icon(Icons.verified_user, color: Colors.blue, size: 20),
                              const SizedBox(width: 5),
                              Text('Eyniləşdirilib', style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        const SizedBox(height: 10),
                        // Рейтинг
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 20),
                            const SizedBox(width: 5),
                            Text('${master.rating.toStringAsFixed(1)} (Total Reviews)', style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(),

            // -----------------------------------------------------------
            // 2. КНОПКИ ДЕЙСТВИЙ (Звонок, Сохранить, Отзыв)
            // -----------------------------------------------------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Кнопка Звонок (Zəng Et)
                  _buildActionButton(Icons.phone, 'Zəng Et', _callMaster),
                  // Кнопка Сохранить/Закладка (Yadda Saxla)
                  _buildActionButton(_isSaved ? Icons.bookmark : Icons.bookmark_border, 'Yadda Saxla', _toggleSave),
                  // Кнопка Отзыв (Rəy Bildir)
                  _buildActionButton(Icons.rate_review, 'Rəy Bildir', _openReviewScreen),
                ],
              ),
            ),

            const Divider(),

            // -----------------------------------------------------------
            // 3. СЕКЦИЯ QIYMƏTLƏR (Прайс-лист)
            // -----------------------------------------------------------
            _buildSectionTitle('Qiymətlər (Prais-list)'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                master.priceList.isNotEmpty ? master.priceList : 'Usta qiymət siyahısını təqdim etməyib.',
                style: const TextStyle(fontSize: 15),
              ),
            ),

            const SizedBox(height: 20),

            // -----------------------------------------------------------
            // 4. СЕКЦИЯ RƏYLƏR (Отзывы)
            // -----------------------------------------------------------
            _buildSectionTitle('Rəylər (Отзывы)'),
            _buildReviewsSection(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Вспомогательный виджет для кнопок действий
  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(icon, size: 30, color: Colors.blue),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.blue)),
      ],
    );
  }

  // Вспомогательный виджет для заголовков секций
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
      child: Text(
        title,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
      ),
    );
  }

  // Секция для отображения отзывов
  Widget _buildReviewsSection() {
    return StreamBuilder<List<Review>>(
      stream: _reviewService.getMasterReviewsStream(widget.masterId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Отзывы не загружены: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: Text('Hələ heç bir rəy yoxdur.'), // Пока нет отзывов
          );
        }

        // Показываем первые 3 отзыва
        final reviews = snapshot.data!.take(3).toList();

        return Column(
          children: reviews.map((review) {
            return ListTile(
              title: Row(
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 5),
                  Text('${review.rating}/5'),
                ],
              ),
              subtitle: Text(review.reviewText, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(
                '${review.date.day}.${review.date.month}.${review.date.year}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ❗️ Добавляем заглушку для MasterService, чтобы код компилировался
// В реальном проекте этот метод должен быть в MasterService
extension MasterProfileExtension on MasterService {
  Future<MasterProfile?> getProfileData(String masterId) async {
    // Имитация получения данных
    await Future.delayed(const Duration(milliseconds: 500));
    return MasterProfile(
      uid: masterId,
      phoneNumber: '99450xxxxxx',
      createdAt: DateTime.now(),
      fullName: 'Əhməd Məmmədov',
      verificationStatus: AppConstants.verificationVerified,
      rating: 4.7,
      priceList: 'Kombi təmiri: 30 AZN, Soyuducu diaqnostikası: 15 AZN.',
      categories: ['Kombi', 'Soyuducu'],
      savesCount: 5, // Пример
    );
  }
}