import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'UserSession.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

class AppNotification {
  AppNotification({
    required this.title,
    required this.body,
    required this.time,
    required this.type,
    required this.read,
    this.data = const {},
  });

  final String title;
  final String body;
  final String time;
  final String type;
  bool read;
  final Map<String, dynamic> data;
}

class FirebaseNotificationService with WidgetsBindingObserver {
  FirebaseNotificationService._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final FirebaseNotificationService instance =
      FirebaseNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<AppNotification> _notificationController =
      StreamController<AppNotification>.broadcast();

  final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<AppNotification> _notifications = [];

  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _appInBackground = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _appInBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
    }
  }

  Stream<AppNotification> get notificationsStream =>
      _notificationController.stream;

  Stream<Map<String, dynamic>> get notificationTapStream =>
      _notificationTapController.stream;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  Future<void> initialize() async {
    try {
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      }

      await _requestPermission();

      if (!kIsWeb) {
        await _initializeLocalNotifications();
      }

      await _setupMessageListeners();
      _setupTokenRefreshListener();
      await _saveDeviceToken();
    } catch (e) {
      debugPrint("Notification init error: $e");
    }
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings();

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == null || response.payload!.isEmpty) return;

        try {
          final payload = jsonDecode(response.payload!);

          if (payload is Map) {
            _notificationTapController.add(
              Map<String, dynamic>.from(payload),
            );
          }
        } catch (e) {
          debugPrint("Notification tap payload error: $e");
        }
      },
    );

    //  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    //    'hamrah_notifications',
    //    'Hamrah Notifications',
    //    description: 'Notification channel for Hamrah app updates',
    //    importance: Importance.max,
    //    playSound: true,
    //  );

    //  final androidPlugin =
    //      _localNotifications.resolvePlatformSpecificImplementation
    //          AndroidFlutterLocalNotificationsPlugin>();

    //  await androidPlugin?.createNotificationChannel(channel);
  }

  Future<void> _setupMessageListeners() async {
    FirebaseMessaging.onMessage.listen((message) async {
      final notification = _mapMessage(message);
      _addNotification(notification);

      if (notification.data['type'] == 'incoming_call') {
        _notificationTapController.add(notification.data);
        return;
      }

      if (!kIsWeb) {
        await _showForegroundNotification(notification);
      } else {
        debugPrint(
          'Foreground Web Notification: ${notification.title} - ${notification.body}',
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final notification = _mapMessage(message);
      _addNotification(notification);
      _notificationTapController.add(notification.data);
    });
  }

  Future<void> saveTokenToBackend() => _saveDeviceToken();

  Future<void> _saveDeviceToken() async {
    try {
      String? token;

      if (kIsWeb) {
        token = await _messaging.getToken(
          vapidKey: 'YOUR_PUBLIC_VAPID_KEY_HERE',
        );
      } else {
        token = await _messaging.getToken();
      }

      if (token == null) return;

      debugPrint('FCM token: $token');

      if (UserSession.token.isEmpty) return;

      final response = await http.post(
        ApiConfig.uri('/users/save-token'),
        headers: ApiConfig.jsonHeaders(),
        body: jsonEncode({'token': token}),
      );

      debugPrint('Token save response: ${response.statusCode} ${response.body}');
    } catch (e) {
      debugPrint('Token save failed: $e');
    }
  }

  void _setupTokenRefreshListener() {
    _messaging.onTokenRefresh.listen((newToken) async {
      debugPrint('FCM token refreshed: $newToken');

      if (UserSession.token.isEmpty) return;

      try {
        await http.post(
          ApiConfig.uri('/users/save-token'),
          headers: ApiConfig.jsonHeaders(),
          body: jsonEncode({'token': newToken}),
        );
      } catch (e) {
        debugPrint('Token refresh save failed: $e');
      }
    });
  }

  AppNotification _mapMessage(RemoteMessage message) {
    final notification = message.notification;

    return AppNotification(
      title: notification?.title ?? 'Notification',
      body: notification?.body ?? 'You received a new notification.',
      time: _relativeTime(DateTime.now()),
      type: (message.data['type'] as String?) ?? 'system',
      read: false,
      data: message.data,
    );
  }

  Future<void> _showForegroundNotification(AppNotification notification) async {
    const androidDetails = AndroidNotificationDetails(
      'hamrah_notifications',
      'Hamrah Notifications',
      channelDescription: 'Notification channel for Hamrah app updates',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(notification.data),
    );
  }

  void _addNotification(AppNotification notification) {
    _notifications.insert(0, notification);
    _notificationController.add(notification);
  }

  String _relativeTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Fetches saved notification history from the backend (GET /notifications)
  /// — this includes AI ride recommendations and every other notification
  /// type that was persisted server-side, not just live FCM pushes received
  /// while the app was open.
  Future<void> loadHistoryFromBackend() async {
    try {
      if (UserSession.token.isEmpty) return;

      final response = await http.get(
        ApiConfig.uri('/notifications'),
        headers: ApiConfig.jsonHeaders(),
      );

      if (response.statusCode != 200) {
        debugPrint(
            'Failed to load notification history: ${response.statusCode} ${response.body}');
        return;
      }

      final List<dynamic> raw = jsonDecode(response.body);

      final historyNotifications = raw.map((item) {
        DateTime createdAt;
        try {
          createdAt = DateTime.parse(item['created_at'] as String).toLocal();
        } catch (_) {
          createdAt = DateTime.now();
        }

        final rawData = item['data'];
        final Map<String, dynamic> dataMap = rawData is Map
            ? Map<String, dynamic>.from(rawData)
            : <String, dynamic>{};

        return AppNotification(
          title: item['title']?.toString() ?? 'Notification',
          body: item['body']?.toString() ?? '',
          time: _relativeTime(createdAt),
          type: item['type']?.toString() ?? 'system',
          read: item['is_read'] == true,
          data: dataMap,
        );
      }).toList();

      // Backend already returns newest-first (ORDER BY created_at DESC),
      // so we replace the local list wholesale rather than merging.
      _notifications
        ..clear()
        ..addAll(historyNotifications);
    } catch (e) {
      debugPrint('Notification history fetch failed: $e');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationController.close();
    _notificationTapController.close();
  }
}