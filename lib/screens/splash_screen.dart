import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/providers/language_provider.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/screens/account_status_screen.dart';
import 'package:mygobuddy/screens/language_onboarding_screen.dart';
import 'package:mygobuddy/screens/onboarding_screen.dart';
import 'package:mygobuddy/screens/pending_verification_screen.dart';
import 'package:mygobuddy/screens/permissions_screen.dart';
import 'package:mygobuddy/screens/verification_screen.dart';
import 'package:mygobuddy/utils/app_icons.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirect();
    });
  }

  /// Checks and requests core permissions needed for basic app functionality.
  Future<void> _requestCorePermissions() async {
    try {
      await [
        Permission.notification,
        Permission.camera,
        Permission.microphone,
      ].request().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint("Permission request timed out, continuing...");
          return <Permission, PermissionStatus>{};
        },
      );
    } catch (e) {
      debugPrint("Error requesting permissions: $e");
    }
  }

  /// A robust way to check for a truthy value from the database,
  /// which might be a boolean or a string representation of a boolean.
  bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  Future<void> _redirect() async {
    try {
      // Show splash for a moment for branding.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      // Step 1: Request non-critical permissions in the background.
      await _requestCorePermissions();

      // Step 2: Check for the critical 'locationAlways' permission.
      final locationAlwaysGranted = await Permission.locationAlways.isGranted;
      if (!locationAlwaysGranted) {
        // If not granted, navigate to the dedicated screen that explains its importance.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const PermissionsScreen()),
        );
        return;
      }

      // Step 3: Check auth state.
      final session = supabase.auth.currentSession;
      final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
      if (session != null) {
        // User is logged in. Fetch profile and check verification status.
        try {
          await profileProvider.fetchProfile(force: true).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint("Profile fetch timed out, continuing with cached data...");
            },
          );
        } catch (e) {
          debugPrint("Error fetching profile: $e, continuing...");
        }

        if (!mounted) return;

        final profile = profileProvider.profileData;
        if (profile != null) {
          final accountStatus = profile['account_status'] ?? 'active';
          if (accountStatus == 'suspended' || accountStatus == 'deactivated') {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => AccountStatusScreen(status: accountStatus)),
                  (route) => false,
            );
            return;
          }

          final isBuddy = _isTruthy(profile['is_buddy']);
          if (isBuddy) {
            // For buddies, we must check their verification status.
            try {
              final buddyData = await supabase
                  .from('buddies')
                  .select('verified, verification_documents, account_status')
                  .eq('id', session.user.id)
                  .single()
                  .timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  debugPrint("Buddy data fetch timed out, redirecting to verification...");
                  throw TimeoutException("Buddy data fetch timeout");
                },
              );

              final buddyAccountStatus = buddyData['account_status'] ?? 'active';
              if (buddyAccountStatus == 'suspended' || buddyAccountStatus == 'deactivated') {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => AccountStatusScreen(status: buddyAccountStatus)),
                      (route) => false,
                );
                return;
              }

              final bool isVerified = _isTruthy(buddyData['verified']);
              final documentsSubmitted =
                  buddyData['verification_documents'] != null &&
                      (buddyData['verification_documents'] as Map).isNotEmpty;

              if (isVerified) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                      (route) => false,
                );
              } else if (documentsSubmitted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => const PendingVerificationScreen()),
                      (route) => false,
                );
              } else {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const VerificationScreen()),
                      (route) => false,
                );
              }
            } catch (e) {
              debugPrint(
                  "Error fetching buddy verification status: $e. Redirecting to verification.");
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const VerificationScreen()),
                    (route) => false,
              );
            }
          } else {
            // Regular client user.
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainScreen()),
                  (route) => false,
            );
          }
        } else {
          // Profile doesn't exist for a logged-in user (incomplete signup).
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                (route) => false,
          );
        }
      } else {
        // Step 4: Check if a language has been selected.
        final languageProvider = context.read<LanguageProvider>();
        try {
          await languageProvider.loadLocale().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint("Language loading timed out, using default...");
            },
          );
        } catch (e) {
          debugPrint("Error loading language: $e, using default...");
        }

        if (!mounted) return;

        if (languageProvider.appLocale == null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (context) => const LanguageOnboardingScreen()),
          );
        } else {
          // All prerequisites are met for a new user, go to the standard onboarding/login flow.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const OnboardingScreen()),
          );
        }
      }
    } catch (e) {
      debugPrint("Critical error in splash screen: $e");
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFF15808),
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF15808),
        body: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.15),
                ),
              ),
              SizedBox(
                width: 150,
                height: 150,
                child: SvgPicture.string(
                  AppIcons.splashLogo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
