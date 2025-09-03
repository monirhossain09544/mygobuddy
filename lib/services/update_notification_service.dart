import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mygobuddy/services/version_service.dart';
import 'package:mygobuddy/widgets/update_dialog.dart';

class UpdateNotificationService {
  static final UpdateNotificationService _instance = UpdateNotificationService._internal();
  factory UpdateNotificationService() => _instance;
  UpdateNotificationService._internal();

  final VersionService _versionService = VersionService();

  /// Check for updates and show dialog if available
  Future<void> checkAndShowUpdateDialog(BuildContext context, {bool forceCheck = false}) async {
    try {
      // Check if user has app updates enabled
      final isAppUpdatesEnabled = await _versionService.isAppUpdatesEnabled();
      if (!isAppUpdatesEnabled && !forceCheck) {
        if (kDebugMode) print('[UpdateService] App updates disabled by user, skipping check');
        return;
      }

      // Check for updates
      final updateResult = await _versionService.checkForUpdates(forceCheck: forceCheck);
      if (updateResult == null || !updateResult.hasUpdate) {
        if (kDebugMode) print('[UpdateService] No updates available');
        return;
      }

      // Check if user previously skipped this version
      final isVersionSkipped = await _versionService.isVersionSkipped(updateResult.latestVersion);
      if (isVersionSkipped && !forceCheck) {
        if (kDebugMode) print('[UpdateService] Version ${updateResult.latestVersion} was skipped by user');
        return;
      }

      // Show update dialog
      if (context.mounted) {
        if (kDebugMode) print('[UpdateService] Showing update dialog for version ${updateResult.latestVersion}');
        await UpdateDialog.showUpdateDialog(context, updateResult);
      }
    } catch (e) {
      if (kDebugMode) print('[UpdateService] Error in update notification service: $e');
    }
  }

  /// Force check for updates (ignores user preferences and skipped versions)
  Future<void> forceCheckForUpdates(BuildContext context) async {
    await checkAndShowUpdateDialog(context, forceCheck: true);
  }

  /// Check if updates are available without showing dialog
  Future<bool> hasUpdatesAvailable() async {
    try {
      final updateResult = await _versionService.checkForUpdates();
      return updateResult?.hasUpdate ?? false;
    } catch (e) {
      if (kDebugMode) print('[UpdateService] Error checking for updates: $e');
      return false;
    }
  }
}
