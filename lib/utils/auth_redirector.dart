import 'package:flutter/material.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/screens/account_status_screen.dart';
import 'package:mygobuddy/screens/onboarding_screen.dart';
import 'package:mygobuddy/screens/pending_verification_screen.dart';
import 'package:mygobuddy/screens/verification_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A centralized class to handle user redirection after any authentication event.
/// This ensures consistent and secure routing based on user role and verification status.
class AuthRedirector {
  /// A robust way to check for a truthy value from the database,
  /// which might be a boolean or a string representation of a boolean.
  static bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  /// Centralized logic to redirect a user after authentication.
  /// Fetches the user's profile and routes them based on their role and verification status.
  static Future<void> redirectUser(BuildContext context) async {
    // Ensure the widget is still in the tree before performing async operations.
    if (!context.mounted) return;

    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      // Safeguard: If no session, send to the beginning of the auth flow.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            (route) => false,
      );
      return;
    }

    // Force a profile refresh to get the latest data after login/signup.
    await profileProvider.fetchProfile(force: true);
    if (!context.mounted) return;

    final profile = profileProvider.profileData;

    if (profile == null) {
      // This can happen if profile creation failed after signup.
      // Send them back to a safe starting point.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            (route) => false,
      );
      return;
    }

    final accountStatus = profile['account_status'] ?? 'active';
    if (accountStatus == 'suspended' || accountStatus == 'deactivated') {
      // Navigate to account status screen to inform user
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AccountStatusScreen(status: accountStatus)),
            (route) => false,
      );
      return;
    }

    final isBuddy = _isTruthy(profile['is_buddy']);

    if (!isBuddy) {
      // This is a regular client user, they can proceed to the main app.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
      );
      return;
    }

    // --- At this point, we know the user is a Buddy with active account status. ---
    // Now, we must check their verification status from the 'buddies' table.
    try {
      final buddyData = await Supabase.instance.client
          .from('buddies')
          .select('verified, verification_documents, account_status')
          .eq('id', session.user.id)
          .single();

      final buddyAccountStatus = buddyData['account_status'] ?? 'active';
      if (buddyAccountStatus == 'suspended' || buddyAccountStatus == 'deactivated') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => AccountStatusScreen(status: buddyAccountStatus)),
              (route) => false,
        );
        return;
      }

      final bool isVerified = _isTruthy(buddyData['verified']);
      final documentsSubmitted = buddyData['verification_documents'] != null &&
          (buddyData['verification_documents'] as Map).isNotEmpty;

      if (isVerified) {
        // Case 1: Buddy is fully verified. Welcome to the app.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
              (route) => false,
        );
      } else if (documentsSubmitted) {
        // Case 2: Documents submitted, but pending admin approval.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PendingVerificationScreen()),
              (route) => false,
        );
      } else {
        // Case 3: Buddy needs to submit documents for verification.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const VerificationScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      // This error can happen if a 'profiles' record exists with is_buddy=true,
      // but the corresponding 'buddies' record is missing.
      // It's a data inconsistency, so we safely route them to the start of verification.
      debugPrint("Redirector Error: Failed to get buddy status: $e. Defaulting to verification screen.");
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const VerificationScreen()),
              (route) => false,
        );
      }
    }
  }
}
