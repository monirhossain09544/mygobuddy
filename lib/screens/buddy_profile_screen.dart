import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // For the switch style
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/providers/home_provider.dart';
import 'package:mygobuddy/providers/language_provider.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/providers/trip_provider.dart';
import 'package:mygobuddy/screens/buddy_bookings_screen.dart';
import 'package:mygobuddy/screens/edit_profile_screen.dart';
import 'package:mygobuddy/screens/referral_screen.dart'; // Added this import
import 'package:mygobuddy/screens/sign_in_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';
import 'package:mygobuddy/screens/faq_screen.dart';
import 'package:mygobuddy/screens/settings_screen.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/buddy_progress_screen.dart';
import 'package:mygobuddy/screens/buddy_dashboard_screen.dart';
import 'package:mygobuddy/screens/buddy_service_management_screen.dart'; // Added this import

class BuddyProfileScreen extends StatefulWidget {
  const BuddyProfileScreen({super.key});
  @override
  State<BuddyProfileScreen> createState() => _BuddyProfileScreenState();
}

class _BuddyProfileScreenState extends State<BuddyProfileScreen> {
  Map<String, dynamic>? _buddyData;
  bool _isLoadingBuddyData = true;
  @override
  void initState() {
    super.initState();
    // Fetch profile data when screen loads, if not already present
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profileProvider = context.read<ProfileProvider>();
      // Use a listener to react to profile changes, e.g., after login
      if (!profileProvider.isLoading && profileProvider.profileData != null) {
        if (profileProvider.isBuddy) {
          _fetchBuddyData();
        }
      } else {
        // If profile is null, fetch it. The listener will handle the rest.
        profileProvider.fetchProfile();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also fetch here to handle cases where the provider updates
    final profileProvider = context.watch<ProfileProvider>();
    if (!profileProvider.isLoading &&
        profileProvider.profileData != null &&
        profileProvider.isBuddy) {
      // Avoid refetching if data is already loaded
      if (_buddyData == null && _isLoadingBuddyData) {
        _fetchBuddyData();
      }
    }
  }

  Future<void> _fetchBuddyData() async {
    if (!mounted) return;
    // Prevent multiple concurrent fetches
    if (!_isLoadingBuddyData) return;
    setState(() {
      _isLoadingBuddyData = true;
    });
    try {
      final buddyId = supabase.auth.currentUser!.id;
      final data = await supabase
          .from('buddies')
          .select('tier')
          .eq('id', buddyId)
          .single();
      if (mounted) {
        setState(() {
          _buddyData = data;
          _isLoadingBuddyData = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching buddy-specific data: $e');
      if (mounted) {
        setState(() {
          _isLoadingBuddyData = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    final localizations = AppLocalizations.of(context);
    // Show confirmation dialog
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        const Color primaryColor = Color(0xFF19638D);
        const Color backgroundColor = Color(0xFFF9FAFB);

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  backgroundColor.withOpacity(0.3),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Modern icon with circular background and gradient
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.red.shade400,
                        Colors.red.shade600,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),

                // Modern title with better typography
                Text(
                  localizations.translate('buddy_profile_logout_title'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 16),

                // Modern content container with background
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: backgroundColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    localizations.translate('buddy_profile_logout_confirm'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Modern button layout with proper styling
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          localizations.translate('buddy_profile_logout_cancel'),
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade500,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 3,
                          shadowColor: Colors.red.withOpacity(0.4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.logout_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              localizations.translate('buddy_profile_logout_button'),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldLogout == true && mounted) {
      try {
        // Get provider references before async operations
        final profileProvider =
        Provider.of<ProfileProvider>(context, listen: false);
        final homeProvider = Provider.of<HomeProvider>(context, listen: false);
        final tripProvider = Provider.of<TripProvider>(context, listen: false);
        // First, sign out from Supabase
        await supabase.auth.signOut();
        // IMPORTANT: Navigate *before* clearing the state.
        // This removes the current screen from the widget tree, preventing it
        // from rebuilding into an error state.
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (context) => const SignInScreen(isBuddy: true)),
                (Route<dynamic> route) => false,
          );
        }
        // After navigation, clear the providers' data.
        profileProvider.clearProfile();
        homeProvider.clearData();
        tripProvider.clearTripState();
      } catch (e) {
        if (mounted) {
          context.showSnackBar(
            localizations.translate('buddy_profile_logout_error',
                args: {'error': e.toString()}),
            isError: true,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color secondaryTextColor = Color(0xFF6B7280);
    const Color accentColor = Color(0xFF19638D);
    const Color cardColor = Colors.white;
    final localizations = AppLocalizations.of(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isSpanish = languageProvider.appLocale?.languageCode == 'es';
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
          automaticallyImplyLeading: false, // Remove back arrow for bottom navigation screen
          title: Text(
            localizations.translate('buddy_profile_title'),
            style: GoogleFonts.workSans(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: Consumer<ProfileProvider>(
          builder: (context, profileProvider, child) {
            if (profileProvider.isLoading &&
                profileProvider.profileData == null) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF19638D),
                ),
              );
            }
            if (profileProvider.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      localizations.translate('buddy_profile_error_load'),
                      style: GoogleFonts.workSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          profileProvider.fetchProfile(force: true),
                      child: Text(
                        localizations.translate('buddy_profile_retry_button'),
                        style: GoogleFonts.workSans(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              );
            }
            final profileData = profileProvider.profileData;
            final name = profileData?['name'] ?? 'User';
            final avatarUrl = profileData?['profile_picture'];
            final email =
                supabase.auth.currentUser?.email ?? 'no-email@example.com';
            return RefreshIndicator(
              onRefresh: () async {
                await profileProvider.fetchProfile(force: true);
                if (profileProvider.isBuddy) {
                  await _fetchBuddyData();
                }
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 10.0),
                children: [
                  _buildProfileHeader(
                    name: name,
                    email: email,
                    avatarUrl: avatarUrl,
                    primaryTextColor: primaryTextColor,
                    secondaryTextColor: secondaryTextColor,
                    localizations: localizations,
                  ),
                  const SizedBox(height: 32),
                  _buildMenuCard(
                    cardColor: cardColor,
                    children: [
                      _buildMenuItem(
                        icon: Icons.dashboard_outlined,
                        title: localizations.translate(
                            'profile_menu_dashboard',
                            fallback: 'Dashboard'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const BuddyDashboardScreen()),
                          );
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.business_center_outlined,
                        title: localizations.translate(
                            'profile_menu_manage_services',
                            fallback: 'Manage Services'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const BuddyServiceManagementScreen()),
                          );
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.person_outline,
                        title: localizations
                            .translate('buddy_profile_menu_profile'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const EditProfileScreen()),
                          );
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.rocket_launch_outlined,
                        title: localizations
                            .translate('buddy_profile_menu_tier_progress'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const BuddyProgressScreen()),
                          );
                        },
                      ),
                      _buildMenuItem(
                          icon: Icons.people_alt_outlined,
                          title:
                          localizations.translate('referral_screen_title'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                  const ReferralScreen()),
                            );
                          }),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildMenuCard(
                    cardColor: cardColor,
                    children: [
                      _buildMenuItem(
                          icon: Icons.help_outline,
                          title:
                          localizations.translate('buddy_profile_menu_help'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const FaqScreen()),
                            );
                          }),
                      _buildMenuItem(
                          icon: Icons.settings_outlined,
                          title: localizations
                              .translate('buddy_profile_menu_settings'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const SettingsScreen()),
                            );
                          }),
                      _buildLanguageToggle(
                        icon: Icons.translate_outlined,
                        title: localizations
                            .translate('buddy_profile_menu_language'),
                        isSpanish: isSpanish,
                        languageProvider: languageProvider,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildLogoutButton(accentColor, localizations),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileHeader({
    required String name,
    required String email,
    String? avatarUrl,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required AppLocalizations localizations,
  }) {
    final isPro = _buddyData?['tier'] == 'pro';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFF9FAFB),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF3B82F6),
                  const Color(0xFF1E40AF),
                ],
              ),
            ),
            child: CircleAvatar(
              radius: 35,
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? NetworkImage(avatarUrl)
                  : null,
              backgroundColor: Colors.grey[200],
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Icon(
                Icons.person_outline,
                color: Colors.grey[600],
                size: 40,
              )
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.workSans(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: GoogleFonts.openSans(
                    fontSize: 14,
                    color: secondaryTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                if (_isLoadingBuddyData)
                  Container(
                    height: 28,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  )
                else if (_buddyData != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isPro
                            ? [
                          const Color(0xFF3B82F6).withOpacity(0.2),
                          const Color(0xFF1E40AF).withOpacity(0.1),
                        ]
                            : [
                          Colors.grey.shade100,
                          Colors.grey.shade50,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isPro
                            ? const Color(0xFF1E40AF).withOpacity(0.3)
                            : Colors.grey.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPro ? Icons.star : Icons.shield_outlined,
                          color: isPro
                              ? const Color(0xFF1E3A8A)
                              : Colors.grey.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPro
                              ? localizations.translate('buddy_tier_pro',
                              fallback: 'Pro Buddy')
                              : localizations.translate('buddy_tier_standard',
                              fallback: 'Standard Buddy'),
                          style: GoogleFonts.workSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isPro
                                ? const Color(0xFF1E3A8A)
                                : Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
      {required Color cardColor, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cardColor,
            cardColor.withOpacity(0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF3B82F6),
                  const Color(0xFF1E40AF),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
            icon,
            color: const Color(0xFF1E40AF),
            size: 20
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.workSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF374151),
        ),
      ),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
            Icons.arrow_forward_ios,
            size: 12,
            color: Colors.grey
        ),
      ),
    );
  }

  Widget _buildLanguageToggle({
    required IconData icon,
    required String title,
    required bool isSpanish,
    required LanguageProvider languageProvider,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
            icon,
            color: const Color(0xFF1E40AF),
            size: 20
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.workSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF374151),
        ),
      ),
      trailing: CupertinoSwitch(
        value: isSpanish,
        onChanged: (value) {
          final newLocale = value ? const Locale('es') : const Locale('en');
          languageProvider.changeLanguage(newLocale);
        },
        activeColor: const Color(0xFF3B82F6),
      ),
    );
  }

  Widget _buildLogoutButton(
      Color accentColor, AppLocalizations localizations) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor,
            accentColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _handleLogout,
        icon: const Icon(Icons.logout, size: 20),
        label: Text(
          localizations.translate('buddy_profile_logout_button'),
          style: GoogleFonts.workSans(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
    );
  }
}
