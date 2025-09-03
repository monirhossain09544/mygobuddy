import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:mygobuddy/utils/constants.dart';

class SafetyLocationProvider extends ChangeNotifier {
  String? _shareToken;
  DateTime? _expiresAt;
  LocationData? _currentLocation;
  StreamSubscription<List<Map<String, dynamic>>>? _locationSubscription;

  String? get shareToken => _shareToken;
  DateTime? get expiresAt => _expiresAt;
  LocationData? get currentLocation => _currentLocation;

  void updateTokenAndExpiry(String? token, DateTime? expiry) {
    _shareToken = token;
    _expiresAt = expiry;
    notifyListeners();
  }

  void updateLocation(LocationData? location) {
    _currentLocation = location;
    notifyListeners();
  }

  void startListeningToLocation(String userId) {
    _locationSubscription?.cancel();
    _locationSubscription = supabase
        .from('live_locations')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .listen((data) {
      if (data.isNotEmpty) {
        // FIX: Add robust type checking to prevent parsing errors.
        final locData = data.first['location'];
        if (locData is Map<String, dynamic> && locData.containsKey('coordinates')) {
          final coords = locData['coordinates'];
          if (coords is List && coords.length >= 2) {
            final lng = coords[0];
            final lat = coords[1];
            if (lng is num && lat is num) {
              updateLocation(LocationData.fromMap({
                'latitude': lat.toDouble(),
                'longitude': lng.toDouble(),
              }));
            }
          }
        }
      }
    });
  }

  void stopListening() {
    _locationSubscription?.cancel();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
