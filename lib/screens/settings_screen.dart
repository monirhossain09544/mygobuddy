import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/screens/delete_account_screen.dart';
import 'package:mygobuddy/screens/language_screen.dart';
import 'package:mygobuddy/screens/notifications_settings_screen.dart';
import 'package:mygobuddy/screens/password_manager_screen.dart';
import 'package:mygobuddy/utils/localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (localizations == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color cardColor = Colors.white;

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
            icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            localizations.translate('settings_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          children: [
            _buildSectionTitle(localizations.translate('settings_general')),
            const SizedBox(height: 12),
            _buildSettingsCard(
              cardColor: cardColor,
              children: [
                _buildSettingsItem(
                  icon: Icons.notifications_outlined,
                  title: localizations.translate('settings_notifications'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationsSettingsScreen()),
                    );
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.language_outlined,
                  title: localizations.translate('settings_language'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LanguageScreen()),
                    );
                  },
                ),
                _buildToggleItem(
                  icon: Icons.dark_mode_outlined,
                  title: localizations.translate('settings_dark_mode'),
                  value: _darkModeEnabled,
                  onChanged: (value) {
                    setState(() {
                      _darkModeEnabled = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle(localizations.translate('settings_account')),
            const SizedBox(height: 12),
            _buildSettingsCard(
              cardColor: cardColor,
              children: [
                _buildSettingsItem(
                  icon: Icons.lock_outline,
                  title: localizations.translate('settings_change_password'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PasswordManagerScreen()),
                    );
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.delete_outline,
                  title: localizations.translate('settings_delete_account'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DeleteAccountScreen()),
                    );
                  },
                  isDestructive: true,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle(localizations.translate('settings_about')),
            const SizedBox(height: 12),
            _buildSettingsCard(
              cardColor: cardColor,
              children: [
                _buildSettingsItem(
                  icon: Icons.privacy_tip_outlined,
                  title: localizations.translate('settings_privacy_policy'),
                  onTap: () {},
                ),
                _buildSettingsItem(
                  icon: Icons.description_outlined,
                  title: localizations.translate('settings_terms_of_service'),
                  onTap: () {},
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

  Widget _buildSettingsCard({required Color cardColor, required List<Widget> children}) {
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

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.red.shade600 : const Color(0xFF374151);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: color, size: 24),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      trailing: isDestructive ? null : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
    );
  }

  Widget _buildToggleItem({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: Colors.grey.shade700, size: 24),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF374151),
        ),
      ),
      trailing: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF19638D),
      ),
    );
  }
}
