import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';
import 'account_repository.dart';

const _channelId = 'wishkit_social';
const _channelName = 'wishkit 알림';

/// 휴대폰 알림 배너.
///
/// 지금(6단계 후): 앱이 켜져 있을 때 새 알림이 오면 배너를 띄운다. (알림함 새로고침과 연동)
/// 5단계(푸시)에서: 앱이 꺼져 있어도 오도록, [register] 에서 기기 토큰을 받아
///                  [AccountRepository.saveFcmToken] 으로 저장하는 부분을 다시 붙인다.
///                  (저장 칸 PrivateProfile.fcmTokens 는 AWS 에 이미 준비돼 있음)
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// 배너를 눌렀을 때 (main.dart 에서 알림 화면으로 이동하도록 연결)
  VoidCallback? onBannerTap;
  bool _ready = false;

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: darwinInit),
        onDidReceiveNotificationResponse: (_) => onBannerTap?.call(),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: '팔로우, 살까말까',
          importance: Importance.high,
        ),
      );
      _ready = true;
    } catch (e) {
      // 배너는 부가 기능. 실패해도 앱은 계속 동작한다.
      debugPrint('알림 배너 준비 실패 (${e.runtimeType})');
    }
  }

  /// 로그인 직후 호출. 지금은 배너 표시 권한만 요청한다.
  /// (이름·인자는 5단계 푸시에서 그대로 쓰려고 유지)
  Future<void> register(String uid, AccountRepository repo) async {
    if (kIsWeb) return;
    await init();
    if (!_ready) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
  }

  /// 로그아웃·탈퇴 때 호출. 지금은 할 일이 없다. (5단계에서 기기 토큰 삭제)
  Future<void> unregister() async {}

  Future<void> showInboxBanner(AppNotification n) async {
    if (!_ready) return;
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '팔로우, 살까말까',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _plugin.show(
      n.id.hashCode,
      _titleFor(n.type),
      n.message,
      const NotificationDetails(android: android, iOS: ios),
    );
  }

  String _titleFor(AppNotificationType type) {
    return switch (type) {
      AppNotificationType.follow => '새 팔로우',
      AppNotificationType.basket => '살까말까',
      AppNotificationType.review => '친구 리뷰',
      AppNotificationType.list => '리스트 공개',
      AppNotificationType.comment => '살까말까 댓글',
    };
  }
}
