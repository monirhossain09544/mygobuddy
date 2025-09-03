import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  Map<String, bool> _settings = {
    'general_notification': true,
    'sound': true,
    'vibrate': false,
    'app_updates': true,
    'bill_reminder': true,
    'new_service': false,
    'new_tips': true,
  };

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .rpc('get_or_create_notification_preferences', params: {
          'p_user_id': user.id,
        });

        if (response != null && response.isNotEmpty) {
          final prefs = response[0];
          setState(() {
            _settings = {
              'general_notification': prefs['general_notification'] ?? true,
              'sound': prefs['sound'] ?? true,
              'vibrate': prefs['vibrate'] ?? false,
              'app_updates': prefs['app_updates'] ?? true,
              'bill_reminder': prefs['bill_reminder'] ?? true,
              'new_service': prefs['new_service'] ?? false,
              'new_tips': prefs['new_tips'] ?? true,
            };
          });
        }
      } else {
        await _loadFromSharedPreferences();
      }
    } catch (e) {
      print('Error loading notification settings: $e');
      await _loadFromSharedPreferences();
      setState(() {
        _errorMessage = 'Failed to load settings from server, using local settings';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _settings = {
        'general_notification': prefs.getBool('general_notification') ?? true,
        'sound': prefs.getBool('sound') ?? true,
        'vibrate': prefs.getBool('vibrate') ?? false,
        'app_updates': prefs.getBool('app_updates') ?? true,
        'bill_reminder': prefs.getBool('bill_reminder') ?? true,
        'new_service': prefs.getBool('new_service') ?? false,
        'new_tips': prefs.getBool('new_tips') ?? true,
      };
    });
  }

  Future<void> _saveNotificationSettings() async {
    try {
      setState(() {
        _isSaving = true;
        _errorMessage = null; // Clear any previous error messages
      });

      final prefs = await SharedPreferences.getInstance();
      for (final entry in _settings.entries) {
        await prefs.setBool(entry.key, entry.value);
      }

      final user = Supabase.instance.client.auth.currentUser;
      bool databaseSaveSuccessful = false;

      if (user != null) {
        try {
          final response = await Supabase.instance.client
              .from('user_notification_preferences')
              .upsert({
            'user_id': user.id,
            'general_notification': _settings['general_notification'],
            'sound': _settings['sound'],
            'vibrate': _settings['vibrate'],
            'app_updates': _settings['app_updates'],
            'bill_reminder': _settings['bill_reminder'],
            'new_service': _settings['new_service'],
            'new_tips': _settings['new_tips'],
          }, onConflict: 'user_id');

          databaseSaveSuccessful = true;
          print('[v0] Database save successful: $response');

        } catch (dbError) {
          print('[v0] Database save error: $dbError');
          databaseSaveSuccessful = false;
        }
      }

      if (mounted) {
        if (user == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Settings saved locally (not logged in)'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (databaseSaveSuccessful) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Notification settings saved successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          setState(() {
            _errorMessage = 'Failed to save settings to server, saved locally';
          });

          Future.delayed(Duration(seconds: 5), () {
            if (mounted) {
              setState(() {
                _errorMessage = null;
              });
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Settings saved locally only'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

    } catch (e) {
      print('[v0] General error saving notification settings: $e');
      setState(() {
        _errorMessage = 'Error saving settings: ${e.toString()}';
      });

      Future.delayed(Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _updateSetting(String key, bool value) {
    setState(() {
      _settings[key] = value;
    });
    _saveNotificationSettings();
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color cardColor = Colors.white;
    final localizations = AppLocalizations.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          surfaceTintColor: backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            localizations.translate('notifications_settings_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            if (_isSaving)
              Container(
                margin: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryTextColor),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _isLoading
            ? Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF19638D)),
          ),
        )
            : ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          children: [
            if (_errorMessage != null)
              Container(
                margin: EdgeInsets.only(bottom: 16),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _buildSectionTitle(localizations.translate('notifications_settings_section_common')),
            const SizedBox(height: 12),
            _buildSettingsCard(
              cardColor: cardColor,
              children: [
                _buildToggleItem(
                  title: localizations.translate('notifications_settings_general_title'),
                  subtitle: localizations.translate('notifications_settings_general_subtitle'),
                  valueKey: 'general_notification',
                ),
                _buildToggleItem(
                  title: localizations.translate('notifications_settings_sound_title'),
                  subtitle: localizations.translate('notifications_settings_sound_subtitle'),
                  valueKey: 'sound',
                ),
                _buildToggleItem(
                  title: localizations.translate('notifications_settings_vibrate_title'),
                  subtitle: localizations.translate('notifications_settings_vibrate_subtitle'),
                  valueKey: 'vibrate',
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle(localizations.translate('notifications_settings_section_system')),
            const SizedBox(height: 12),
            _buildSettingsCard(
              cardColor: cardColor,
              children: [
                _buildToggleItem(
                  title: localizations.translate('notifications_settings_app_updates_title'),
                  subtitle: localizations.translate('notifications_settings_app_updates_subtitle'),
                  valueKey: 'app_updates',
                ),
                _buildToggleItem(
                  title: localizations.translate('notifications_settings_bill_reminder_title'),
                  subtitle: localizations.translate('notifications_settings_bill_reminder_subtitle'),
                  valueKey: 'bill_reminder',
                ),
                _buildToggleItem(
                  title: localizations.translate('notifications_settings_new_service_title'),
                  subtitle: localizations.translate('notifications_settings_new_service_subtitle'),
                  valueKey: 'new_service',
                ),
                _buildToggleItem(
                  title: localizations.translate('notifications_settings_new_tips_title'),
                  subtitle: localizations.translate('notifications_settings_new_tips_subtitle'),
                  valueKey: 'new_tips',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
      ),
    );
  }

  Widget _buildSettingsCard(
      {required Color cardColor, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.07),
            spreadRadius: 1,
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    required String subtitle,
    required String valueKey,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF111827),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: Colors.grey.shade600,
        ),
      ),
      trailing: CupertinoSwitch(
        value: _settings[valueKey] ?? false,
        onChanged: _isSaving ? null : (value) {
          _updateSetting(valueKey, value);
        },
        activeColor: const Color(0xFF19638D),
      ),
    );
  }
}
