import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mygobuddy/utils/constants.dart';

class LocationProvider with ChangeNotifier {
  final FlutterBackgroundService _service = FlutterBackgroundService();
  String? _activeConversationId;
  DateTime? _sessionExpiresAt;
  Timer? _countdownTimer;

  String? get activeConversationId => _activeConversationId;
  DateTime? get sessionExpiresAt => _sessionExpiresAt;
  bool get isSharingLocation => _activeConversationId != null && _sessionExpiresAt != null && DateTime.now().isBefore(_sessionExpiresAt!);

  Duration get remainingTime {
    if (!isSharingLocation) return Duration.zero;
    return _sessionExpiresAt!.difference(DateTime.now());
  }

  LocationProvider() {
    _initialize();
  }

  void _initialize() {
    // Listen for updates from the background service
    _service.on('updateLiveLocationState').listen((data) {
      if (data == null) return;
      final conversationId = data['conversation_id'] as String?;
      final expiresAtStr = data['expires_at'] as String?;

      if (conversationId != null && expiresAtStr != null) {
        final expiresAt = DateTime.tryParse(expiresAtStr);
        if (expiresAt != null && expiresAt.isAfter(DateTime.now())) {
          _startSession(conversationId, expiresAt);
        } else {
          _stopSession();
        }
      } else {
        _stopSession();
      }
    });
  }

  void _startSession(String conversationId, DateTime expiresAt) {
    _activeConversationId = conversationId;
    _sessionExpiresAt = expiresAt;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isSharingLocation) {
        timer.cancel();
        _stopSession();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void _stopSession() {
    _activeConversationId = null;
    _sessionExpiresAt = null;
    _countdownTimer?.cancel();
    notifyListeners();
  }

  Future<void> startSharing(String conversationId, String receiverId) async {
    // Use UTC time for consistency across devices and timezones
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 60));
    _startSession(conversationId, expiresAt);

    // Tell the background service to start the live location task
    _service.invoke('startTask', {
      'task': 'startLiveLocation',
      'conversation_id': conversationId,
      'expires_at': expiresAt.toIso8601String(),
    });

    // Send the initial message to the chat
    await supabase.from('messages').insert({
      'sender_id': supabase.auth.currentUser!.id,
      'receiver_id': receiverId,
      'conversation_id': conversationId,
      'text': 'Started sharing live location.',
      'metadata': {
        'type': 'live_location_started',
        'expires_at': expiresAt.toIso8601String(),
      }
    });
  }

  Future<void> stopSharing() async {
    if (_activeConversationId == null) return;

    final conversationIdToStop = _activeConversationId!;
    final userId = supabase.auth.currentUser!.id;

    // Stop the session in the UI immediately for better responsiveness
    _stopSession();

    // Tell the background service to stop updating the location
    _service.invoke('startTask', {
      'task': 'stopLiveLocation',
      'conversation_id': conversationIdToStop,
    });

    // Directly clear the location from the database as a fallback/immediate action
    // This ensures data is cleared even if the background service has issues.
    try {
      await supabase.rpc('clear_live_location', params: {
        'p_conversation_id': conversationIdToStop,
        'p_user_id': userId,
      });
    } catch (e) {
      debugPrint('Error clearing live location from provider: $e');
    }
  }
}
