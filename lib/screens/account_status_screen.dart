import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/screens/onboarding_screen.dart';
import 'package:mygobuddy/screens/contact_support_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';

class AccountStatusScreen extends StatelessWidget {
  final String status;

  const AccountStatusScreen({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    const Color primaryColor = Color(0xFF19638D);
    const Color accentColor = Color(0xFFF15808);
    const Color backgroundColor = Color(0xFFF8F8F8);

    String title;
    String message;
    IconData icon;
    Color iconColor;

    switch (status) {
      case 'suspended':
        title = localizations.translate('account_suspended_title');
        message = localizations.translate('account_suspended_message');
        icon = Icons.pause_circle_outline;
        iconColor = Colors.orange;
        break;
      case 'deactivated':
        title = localizations.translate('account_deactivated_title');
        message = localizations.translate('account_deactivated_message');
        icon = Icons.block;
        iconColor = Colors.red;
        break;
      default:
        title = localizations.translate('account_restricted_title');
        message = localizations.translate('account_restricted_message');
        icon = Icons.warning_outlined;
        iconColor = Colors.amber;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    size: 60,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: primaryColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      // Sign out the user and redirect to onboarding
                      await supabase.auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                              (route) => false,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      localizations.translate('account_status_sign_out'),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ContactSupportScreen(
                          initialCategory: 'account_issues',
                          initialSubject: status == 'suspended'
                              ? localizations.translate('support_account_suspended_subject')
                              : localizations.translate('support_account_deactivated_subject'),
                        ),
                      ),
                    );
                  },
                  child: Text(
                    localizations.translate('account_status_contact_support'),
                    style: GoogleFonts.poppins(
                      color: primaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
