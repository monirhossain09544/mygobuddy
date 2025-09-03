import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// This function must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // You can add background processing logic here if needed.
  print("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    await _requestPermission();
    await _initPushNotifications();
    await _initLocalNotifications();
  }

  Future<void> _requestPermission() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (kDebugMode) {
      print('User granted permission: ${settings.authorizationStatus}');
    }
  }

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await _localNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _initPushNotifications() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('Got a message whilst in the foreground!');
      }
      if (message.notification != null) {
        _showLocalNotification(message);
      }
    });

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  Future<Map<String, bool>> _getUserNotificationPreferences() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .rpc('get_or_create_notification_preferences', params: {
          'p_user_id': user.id,
        });

        if (response != null && response.isNotEmpty) {
          final prefs = response[0];
          return {
            'sound': prefs['sound'] ?? true,
            'vibrate': prefs['vibrate'] ?? false,
          };
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error loading notification preferences from database: $e');
    }

    // Fallback to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return {
      'sound': prefs.getBool('sound') ?? true,
      'vibrate': prefs.getBool('vibrate') ?? false,
    };
  }

  void _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    // Get user preferences
    final userPrefs = await _getUserNotificationPreferences();
    final shouldPlaySound = userPrefs['sound'] ?? true;
    final shouldVibrate = userPrefs['vibrate'] ?? false;

    String channelId = 'default_channel';
    String channelName = 'General Notifications';
    String channelDescription = 'General app notifications';
    Importance importance = Importance.max;
    Priority priority = Priority.high;

    final notificationType = message.data['type'] ?? 'general';

    if (notificationType == 'trip_completion_confirmation') {
      channelId = 'trip_completion_channel';
      channelName = 'Trip Completion';
      channelDescription = 'Notifications about trip completion requests and confirmations';
      importance = Importance.max;
      priority = Priority.high;
    } else if (notificationType == 'trip_completion_update') {
      channelId = 'trip_completion_channel';
      channelName = 'Trip Completion';
      channelDescription = 'Notifications about trip completion requests and confirmations';
      importance = Importance.max;
      priority = Priority.high;
    } else if (notificationType == 'trip_completed') {
      channelId = 'trip_completed_channel';
      channelName = 'Trip Completed';
      channelDescription = 'Notifications when trips are successfully completed';
      importance = Importance.max;
      priority = Priority.high;
    } else if (notificationType == 'new_service') {
      channelId = 'new_service_channel';
      channelName = 'New Services';
      channelDescription = 'Notifications about new services available';
    } else if (notificationType == 'promotion') {
      channelId = 'promotions_channel';
      channelName = 'Promotions';
      channelDescription = 'Promotional notifications and offers';
    }

    Int64List? vibrationPattern;
    if (shouldVibrate) {
      if (notificationType.startsWith('trip_completion') || notificationType == 'trip_completed') {
        // More urgent vibration pattern for trip completion notifications
        vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 500]);
      } else {
        // Standard vibration pattern
        vibrationPattern = Int64List.fromList([0, 1000, 500, 1000]);
      }
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      playSound: shouldPlaySound,
      sound: shouldPlaySound ? const RawResourceAndroidNotificationSound('notification') : null,
      enableVibration: shouldVibrate,
      vibrationPattern: vibrationPattern,
      actions: _getNotificationActions(notificationType, message.data),
    );

    final iOSDetails = DarwinNotificationDetails(
      presentSound: shouldPlaySound,
      sound: shouldPlaySound ? 'default' : null,
      categoryIdentifier: _getIOSCategory(notificationType),
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    _localNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      notificationDetails,
      payload: _createNotificationPayload(notificationType, message.data),
    );
  }

  List<AndroidNotificationAction>? _getNotificationActions(String notificationType, Map<String, dynamic> data) {
    if (notificationType == 'trip_completion_confirmation') {
      final requestingUser = data['requesting_user'];
      // Only show confirm action if the current user is not the one who requested
      if (requestingUser != null) {
        return [
          const AndroidNotificationAction(
            'confirm_completion',
            'Confirm',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'view_trip',
            'View Trip',
            showsUserInterface: true,
          ),
        ];
      }
    } else if (notificationType == 'trip_completed') {
      return [
        const AndroidNotificationAction(
          'rate_trip',
          'Rate Trip',
          showsUserInterface: true,
        ),
      ];
    }
    return null;
  }

  String? _getIOSCategory(String notificationType) {
    switch (notificationType) {
      case 'trip_completion_confirmation':
        return 'TRIP_COMPLETION_CONFIRMATION';
      case 'trip_completion_update':
        return 'TRIP_COMPLETION_UPDATE';
      case 'trip_completed':
        return 'TRIP_COMPLETED';
      case 'new_service':
        return 'NEW_SERVICE';
      default:
        return 'GENERAL';
    }
  }

  String _createNotificationPayload(String notificationType, Map<String, dynamic> data) {
    final payload = {
      'type': notificationType,
      'data': data,
    };
    return payload.toString();
  }

  Future<void> handleNotificationTap(String? payload) async {
    if (payload == null) return;

    try {
      // Parse the payload and handle different notification types
      if (payload.contains('trip_completion_confirmation')) {
        // Navigate to trip screen or show completion dialog
        print('Handling trip completion confirmation notification tap');
      } else if (payload.contains('trip_completed')) {
        // Navigate to trip completion/rating screen
        print('Handling trip completed notification tap');
      }
      // Add more handling as needed
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

  Future<void> saveFCMToken() async {
    try {
      final fcmToken = await _firebaseMessaging.getToken();
      if (fcmToken == null) {
        if (kDebugMode) print('Failed to get FCM token.');
        return;
      }
      if (kDebugMode) print('FCM Token: $fcmToken');

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId != null) {
        final response = await supabase
            .from('profiles')
            .select('fcm_token')
            .eq('id', userId)
            .single();

        if (response['fcm_token'] != fcmToken) {
          await supabase
              .from('profiles')
              .update({'fcm_token': fcmToken})
              .eq('id', userId);
          if (kDebugMode) print('FCM token saved to Supabase.');
        } else {
          if (kDebugMode) print('FCM token is already up-to-date.');
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error saving FCM token: $e');
    }
  }
}
