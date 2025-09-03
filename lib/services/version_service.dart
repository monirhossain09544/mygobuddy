import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VersionCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String platform;

  VersionCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.platform,
  });

  factory VersionCheckResult.fromJson(Map<String, dynamic> json) {
    return VersionCheckResult(
      hasUpdate: json['hasUpdate'] ?? false,
      currentVersion: json['currentVersion'] ?? '',
      latestVersion: json['latestVersion'] ?? '',
      releaseNotes: json['releaseNotes'] ?? '',
      platform: json['platform'] ?? '',
    );
  }
}

class VersionService {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _lastCheckKey = 'last_version_check';
  static const String _skipVersionKey = 'skip_version_';

  /// Check for app updates
  Future<VersionCheckResult?> checkForUpdates({bool forceCheck = false}) async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Determine platform
      final platform = Platform.isIOS ? 'ios' : 'android';

      // Check if we should skip this check (rate limiting)
      if (!forceCheck && await _shouldSkipCheck()) {
        if (kDebugMode) print('[VersionService] Skipping version check due to rate limiting');
        return null;
      }

      // Call backend version checker
      final response = await _supabase.functions.invoke(
        'check-app-version',
        body: {
          'currentVersion': currentVersion,
          'platform': platform,
        },
      );

      if (response.data != null && response.data['success'] == true) {
        // Update last check timestamp
        await _updateLastCheckTime();

        final result = VersionCheckResult.fromJson(response.data);

        if (kDebugMode) {
          print('[VersionService] Version check result: ${result.hasUpdate ? 'Update available' : 'Up to date'}');
          print('[VersionService] Current: ${result.currentVersion}, Latest: ${result.latestVersion}');
        }

        return result;
      } else {
        if (kDebugMode) print('[VersionService] Version check failed: ${response.data}');
        return null;
      }
    } catch (e) {
      if (kDebugMode) print('[VersionService] Error checking for updates: $e');
      return null;
    }
  }

  /// Check if user has app updates notifications enabled
  Future<bool> isAppUpdatesEnabled() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final response = await _supabase
          .from('user_notification_preferences')
          .select('app_updates')
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null) {
        return response['app_updates'] ?? false;
      }

      // Fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('app_updates') ?? false;
    } catch (e) {
      if (kDebugMode) print('[VersionService] Error checking app updates preference: $e');
      return false;
    }
  }

  /// Mark a version as skipped by user
  Future<void> skipVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_skipVersionKey$version', true);
      if (kDebugMode) print('[VersionService] Version $version marked as skipped');
    } catch (e) {
      if (kDebugMode) print('[VersionService] Error skipping version: $e');
    }
  }

  /// Check if a version was previously skipped
  Future<bool> isVersionSkipped(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_skipVersionKey$version') ?? false;
    } catch (e) {
      if (kDebugMode) print('[VersionService] Error checking skipped version: $e');
      return false;
    }
  }

  /// Get current app version
  Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      if (kDebugMode) print('[VersionService] Error getting current version: $e');
      return '1.0.0';
    }
  }

  /// Get app build number
  Future<String> getBuildNumber() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.buildNumber;
    } catch (e) {
      if (kDebugMode) print('[VersionService] Error getting build number: $e');
      return '1';
    }
  }

  /// Check if we should skip version check (rate limiting - once per day)
  Future<bool> _shouldSkipCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      const dayInMs = 24 * 60 * 60 * 1000; // 24 hours

      return (now - lastCheck) < dayInMs;
    } catch (e) {
      return false;
    }
  }

  /// Update last check timestamp
  Future<void> _updateLastCheckTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) print('[VersionService] Error updating last check time: $e');
    }
  }

  /// Clear all version-related preferences (for testing)
  Future<void> clearVersionPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) =>
      key.startsWith(_skipVersionKey) || key == _lastCheckKey);

      for (final key in keys) {
        await prefs.remove(key);
      }

      if (kDebugMode) print('[VersionService] Version preferences cleared');
    } catch (e) {
      if (kDebugMode) print('[VersionService] Error clearing version preferences: $e');
    }
  }
}
