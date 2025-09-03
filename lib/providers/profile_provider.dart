import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:postgrest/postgrest.dart';

class ProfileProvider with ChangeNotifier {
  final SupabaseClient supabase = Supabase.instance.client;

  Map<String, dynamic>? _profileData;
  bool _isLoading = false;
  bool _hasError = false;
  double? _latitude;
  double? _longitude;
  String? _country;

  Map<String, dynamic>? get profileData => _profileData;
  Map<String, dynamic>? get profile => _profileData;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  bool get isBuddy => _profileData?['is_buddy'] == true;
  double? get latitude => _latitude;
  double? get longitude => _longitude;
  String? get country => _country;

  ProfileProvider();

  Future<void> _geocodeAddress(String? address) async {
    if (address == null || address.isEmpty) {
      _latitude = null;
      _longitude = null;
      _country = null;
      return;
    }
    try {
      List<Location> locations = await locationFromAddress(address)
          .timeout(const Duration(seconds: 10));
      if (locations.isNotEmpty) {
        _latitude = locations.first.latitude;
        _longitude = locations.first.longitude;
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(_latitude!, _longitude!)
              .timeout(const Duration(seconds: 10));
          if (placemarks.isNotEmpty) {
            _country = placemarks.first.country;
          }
        } catch (e) {
          print('[v0] Could not extract country from coordinates: $e');
        }
      }
    } catch (e) {
      print('Could not geocode address "$address": $e');
      _latitude = null;
      _longitude = null;
      _country = null;
    }
  }

  Future<void> fetchProfile({bool force = false}) async {
    if (supabase.auth.currentUser == null) {
      clearProfile();
      return;
    }

    if (_profileData != null && !force) {
      return;
    }
    _isLoading = true;
    _hasError = false;
    if (_profileData == null) {
      notifyListeners();
    }
    try {
      final userId = supabase.auth.currentUser!.id;
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));

      if (data != null) {
        _profileData = data;
        _geocodeAddress(data['location'] as String?).catchError((e) {
          print('[v0] Background geocoding failed: $e');
        });
      } else {
        _profileData = null;
      }
    } catch (e) {
      _hasError = true;
      print('Error fetching profile: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      print("[v0] Starting profile update for user: $userId");
      print("[v0] Original updates: $updates");
      print("[v0] Current profile data: $_profileData");
      print("[v0] Is buddy: $isBuddy");

      final finalUpdates = {
        'id': userId,
        'updated_at': DateTime.now().toIso8601String(),
        ...updates,
      };

      double? newLat;
      double? newLng;
      String? newCountry;

      if (updates.containsKey('location')) {
        final address = updates['location'] as String?;
        print("[v0] Processing location update: $address");
        if (address != null && address.isNotEmpty) {
          try {
            List<Location> locations = await locationFromAddress(address)
                .timeout(const Duration(seconds: 10));
            if (locations.isNotEmpty) {
              newLat = locations.first.latitude;
              newLng = locations.first.longitude;
              finalUpdates['latitude'] = newLat;
              finalUpdates['longitude'] = newLng;
              print("[v0] Geocoded coordinates: lat=$newLat, lng=$newLng");

              try {
                print("[v0] Attempting reverse geocoding for coordinates: lat=$newLat, lng=$newLng");
                List<Placemark> placemarks = await placemarkFromCoordinates(newLat, newLng)
                    .timeout(const Duration(seconds: 10));
                print("[v0] Reverse geocoding returned ${placemarks.length} placemarks");

                if (placemarks.isNotEmpty) {
                  final placemark = placemarks.first;
                  print("[v0] First placemark details:");
                  print("[v0] - country: ${placemark.country}");
                  print("[v0] - administrativeArea: ${placemark.administrativeArea}");
                  print("[v0] - locality: ${placemark.locality}");
                  print("[v0] - name: ${placemark.name}");

                  newCountry = placemark.country;
                  if (newCountry != null && newCountry.isNotEmpty) {
                    finalUpdates['country'] = newCountry;
                    print("[v0] Successfully extracted country: $newCountry");
                  } else {
                    print("[v0] Country field is null or empty in placemark");
                    finalUpdates['country'] = null;
                  }
                } else {
                  print("[v0] No placemarks returned from reverse geocoding");
                  finalUpdates['country'] = null;
                }
              } catch (e) {
                print('[v0] Could not extract country from coordinates: $e');
                print('[v0] Error type: ${e.runtimeType}');
                finalUpdates['country'] = null;
              }
            }
          } catch (e) {
            print('[v0] Could not geocode address during profile update: $e');
            finalUpdates['latitude'] = null;
            finalUpdates['longitude'] = null;
            finalUpdates['country'] = null;
          }
        } else {
          finalUpdates['latitude'] = null;
          finalUpdates['longitude'] = null;
          finalUpdates['country'] = null;
        }
      }

      print("[v0] Final updates to send: $finalUpdates");

      bool rpcSuccess = false;

      // First attempt: Try the RPC function
      try {
        final buddyUpdates = {
          'location': finalUpdates['location'],
          'latitude': finalUpdates['latitude'],
          'longitude': finalUpdates['longitude'],
          'country': finalUpdates['country'],
          'name': finalUpdates['name'],
          'profile_picture': finalUpdates['profile_picture'],
        }..removeWhere((key, value) => value == null);

        print("[v0] Attempting RPC function call...");
        await supabase.rpc('update_profile_with_country', params: {
          'p_user_id': userId,
          'p_name': finalUpdates['name'],
          'p_phone': finalUpdates['phone_number'], // Fixed: was 'phone', now 'phone_number'
          'p_location': finalUpdates['location'],
          'p_latitude': finalUpdates['latitude'],
          'p_longitude': finalUpdates['longitude'],
          'p_country': finalUpdates['country'], // Added country parameter
          'p_languages': finalUpdates['languages_spoken'], // Fixed: was 'languages', now 'languages_spoken'
          'p_profile_picture': finalUpdates['profile_picture'],
        });

        print("[v0] RPC call completed successfully");
        rpcSuccess = true;

      } catch (rpcError) {
        print("[v0] RPC function failed: $rpcError");

        // Second attempt: Direct database operations as fallback
        try {
          print("[v0] Attempting direct database update fallback...");

          // Prepare profile updates (excluding role and other sensitive fields)
          final profileUpdates = Map<String, dynamic>.from(finalUpdates);
          profileUpdates.remove('id'); // Don't update the ID
          profileUpdates.remove('role'); // Never update role
          profileUpdates.remove('userType'); // Don't update userType
          profileUpdates.remove('is_buddy'); // Don't update is_buddy

          print("[v0] Direct profile updates: $profileUpdates");

          // Update profiles table directly
          await supabase
              .from('profiles')
              .update(profileUpdates)
              .eq('id', userId);

          print("[v0] Direct profile update completed");

          // If user is a buddy, update buddies table
          if (isBuddy) {
            final buddyUpdates = {
              'name': finalUpdates['name'],
              'location': finalUpdates['location'],
              'latitude': finalUpdates['latitude'],
              'longitude': finalUpdates['longitude'],
              'country': finalUpdates['country'], // Added country parameter
              'profile_picture': finalUpdates['profile_picture'],
            }..removeWhere((key, value) => value == null);

            if (buddyUpdates.isNotEmpty) {
              print("[v0] Updating buddy table: $buddyUpdates");
              await supabase
                  .from('buddies')
                  .update(buddyUpdates)
                  .eq('id', userId);
              print("[v0] Direct buddy update completed");
            }
          }

          print("[v0] Direct database operations completed successfully");

        } catch (directError) {
          print("[v0] Direct database operations also failed: $directError");
          rethrow;
        }
      }

      // Update local profile data
      if (_profileData != null) {
        _profileData!.addAll(finalUpdates);
        if (updates.containsKey('location')) {
          _latitude = newLat;
          _longitude = newLng;
          _country = newCountry;
        }
        print("[v0] Local profile data updated");
        notifyListeners();
      }

      print("[v0] Profile update completed successfully using ${rpcSuccess ? 'RPC function' : 'direct operations'}");

    } catch (e) {
      print("[v0] Error in updateProfile: $e");
      print("[v0] Error type: ${e.runtimeType}");
      if (e is PostgrestException) {
        print("[v0] PostgrestException details:");
        print("[v0] - message: ${e.message}");
        print("[v0] - code: ${e.code}");
        print("[v0] - details: ${e.details}");
        print("[v0] - hint: ${e.hint}");
      }
      rethrow;
    }
  }

  Future<void> updateProfileImage(String imagePath) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final bytes = await File(imagePath).readAsBytes();
      final fileExt = imagePath.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = '$userId/$fileName';
      await supabase.storage.from('profile-pictures').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(contentType: 'image/$fileExt'),
      );
      final imageUrl =
      supabase.storage.from('profile-pictures').getPublicUrl(filePath);
      await updateProfile({'profile_picture': imageUrl});
    } catch (e) {
      rethrow;
    }
  }

  void clearProfile() {
    _profileData = null;
    _isLoading = false;
    _hasError = false;
    _latitude = null;
    _longitude = null;
    _country = null;
    notifyListeners();
  }
}
