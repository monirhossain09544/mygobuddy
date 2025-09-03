import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:shimmer/shimmer.dart';

class BuddyProgressScreen extends StatefulWidget {
  const BuddyProgressScreen({super.key});

  @override
  State<BuddyProgressScreen> createState() => _BuddyProgressScreenState();
}

class _BuddyProgressScreenState extends State<BuddyProgressScreen> {
  late Future<Map<String, dynamic>> _progressFuture;

  @override
  void initState() {
    super.initState();
    _progressFuture = _fetchProgress();
  }

  Future<Map<String, dynamic>> _fetchProgress() async {
    try {
      final progressResult = await supabase.rpc(
        'get_buddy_promotion_progress',
        params: {'p_buddy_id': supabase.auth.currentUser!.id},
      );

      // Fetch current buddy tier
      final buddyResult = await supabase
          .from('buddies')
          .select('tier')
          .eq('id', supabase.auth.currentUser!.id)
          .single();

      Map<String, dynamic> progressData;
      if (progressResult is List && progressResult.isNotEmpty) {
        progressData = progressResult.first as Map<String, dynamic>;
      } else if (progressResult is Map<String, dynamic>) {
        progressData = progressResult;
      } else {
        throw Exception('Unexpected response format from database');
      }

      // Add current tier to progress data
      progressData['current_tier'] = buddyResult['tier'] ?? 'standard';

      return progressData;
    } catch (error) {
      print('[v0] Tier Progress Error: $error');
      print('[v0] User ID: ${supabase.auth.currentUser!.id}');
      print('[v0] Error Type: ${error.runtimeType}');
      if (error.toString().contains('PostgrestException')) {
        print('[v0] Database Error Details: ${error.toString()}');
      }
      rethrow;
    }
  }

  void _refreshProgress() {
    setState(() {
      _progressFuture = _fetchProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color primaryColor = Color(0xFF19638D);

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
            icon: const Icon(Icons.arrow_back, color: primaryTextColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            localizations.translate('tier_progress_screen_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _progressFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingShimmer();
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return _buildErrorState(localizations);
            }

            final data = snapshot.data!;
            final currentBookings = data['current_bookings'] as int;
            final targetBookings = data['target_bookings'] as int;
            final currentRating = (data['current_rating'] as num).toDouble();
            final targetRating = (data['target_rating'] as num).toDouble();
            final currentDays = data['current_days_active'] as int;
            final targetDays = data['target_days_active'] as int;
            final currentReferrals = data['current_referrals'] as int;
            final targetReferrals = data['target_referrals'] as int;
            final currentTier = data['current_tier'] as String? ?? 'standard';

            final bool canUpgrade = currentBookings >= targetBookings &&
                currentRating >= targetRating &&
                currentDays >= targetDays &&
                currentReferrals >= targetReferrals;

            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildHeaderCard(localizations, primaryColor, currentTier),
                const SizedBox(height: 24),
                Text(
                  localizations.translate('tier_progress_requirements_title'),
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 16),
                _buildProgressCard(
                  icon: Icons.work_history_outlined,
                  iconColor: Colors.blue.shade700,
                  title: localizations.translate('tier_progress_bookings_label'),
                  currentValue: currentBookings.toDouble(),
                  targetValue: targetBookings.toDouble(),
                  progressText: '$currentBookings ${localizations.translate('tier_progress_of')} $targetBookings',
                ),
                const SizedBox(height: 12),
                _buildProgressCard(
                  icon: Icons.star_half_outlined,
                  iconColor: Colors.amber.shade800,
                  title: localizations.translate('tier_progress_rating_label'),
                  currentValue: currentRating,
                  targetValue: targetRating,
                  progressText: '${currentRating.toStringAsFixed(1)} / ${targetRating.toStringAsFixed(1)}',
                ),
                const SizedBox(height: 12),
                _buildProgressCard(
                  icon: Icons.calendar_today_outlined,
                  iconColor: Colors.green.shade700,
                  title: localizations.translate('tier_progress_seniority_label'),
                  currentValue: currentDays.toDouble(),
                  targetValue: targetDays.toDouble(),
                  progressText: '$currentDays ${localizations.translate('tier_progress_of')} $targetDays ${localizations.translate('tier_progress_days')}',
                ),
                const SizedBox(height: 12),
                _buildProgressCard(
                  icon: Icons.group_add_outlined,
                  iconColor: Colors.purple.shade600,
                  title: localizations.translate('tier_progress_referrals_label'),
                  currentValue: currentReferrals.toDouble(),
                  targetValue: targetReferrals.toDouble(),
                  progressText: '$currentReferrals ${localizations.translate('tier_progress_of')} $targetReferrals',
                ),
                const SizedBox(height: 24),
                _buildUpgradeSection(
                  localizations,
                  primaryColor,
                  canUpgrade,
                  currentTier,
                  currentBookings, targetBookings,
                  currentRating, targetRating,
                  currentDays, targetDays,
                  currentReferrals, targetReferrals,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderCard(AppLocalizations localizations, Color primaryColor, String currentTier) {
    final bool isPro = currentTier == 'pro';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPro
              ? [const Color(0xFFFFD700), const Color(0xFFFFA500)] // Gold gradient for pro
              : [primaryColor, const Color(0xFF2980B9)], // Blue gradient for standard
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
              isPro ? Icons.star : Icons.rocket_launch_outlined,
              color: Colors.white,
              size: 40
          ),
          const SizedBox(height: 12),
          Text(
            isPro
                ? 'Congratulations, Pro Buddy!'
                : localizations.translate('tier_progress_header_title'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPro
                ? 'You\'re now a Pro Buddy with 20% higher rates and exclusive benefits!'
                : localizations.translate('tier_progress_header_subtitle'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required double currentValue,
    required double targetValue,
    required String progressText,
  }) {
    // Handle division by zero if target is 0
    final double progress = (targetValue > 0) ? (currentValue / targetValue).clamp(0.0, 1.0) : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151),
                ),
              ),
              const Spacer(),
              Text(
                progressText,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 24,
            width: 200,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          _buildShimmerCard(),
          const SizedBox(height: 12),
          _buildShimmerCard(),
          const SizedBox(height: 12),
          _buildShimmerCard(),
          const SizedBox(height: 12),
          // Shimmer for the new referral card
          _buildShimmerCard(),
        ],
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations localizations) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.grey, size: 48),
            const SizedBox(height: 16),
            Text(
              localizations.translate('tier_progress_loading_error'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshProgress,
              icon: const Icon(Icons.refresh),
              label: Text(localizations.translate('tier_progress_retry_button')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeSection(
      AppLocalizations localizations,
      Color primaryColor,
      bool canUpgrade,
      String currentTier,
      int currentBookings, int targetBookings,
      double currentRating, double targetRating,
      int currentDays, int targetDays,
      int currentReferrals, int targetReferrals,
      ) {
    final bool isPro = currentTier == 'pro';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          if (isPro) ...[
            Icon(Icons.verified, color: Colors.green, size: 32),
            const SizedBox(height: 12),
            Text(
              'Pro Buddy Status',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ve successfully upgraded to Pro! Enjoy higher rates and exclusive benefits.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ] else if (canUpgrade) ...[
            Icon(Icons.rocket_launch, color: primaryColor, size: 32),
            const SizedBox(height: 12),
            Text(
              'Ready for Pro Upgrade!',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Congratulations! You\'ve met all requirements.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _handleUpgrade(localizations),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Upgrade to Pro',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ] else ...[
            Icon(Icons.hourglass_empty, color: Colors.orange, size: 32),
            const SizedBox(height: 12),
            Text(
              'Requirements Not Met',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete the following to unlock Pro upgrade:',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            ..._buildMissingRequirements(
              currentBookings, targetBookings,
              currentRating, targetRating,
              currentDays, targetDays,
              currentReferrals, targetReferrals,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildMissingRequirements(
      int currentBookings, int targetBookings,
      double currentRating, double targetRating,
      int currentDays, int targetDays,
      int currentReferrals, int targetReferrals,
      ) {
    List<Widget> missing = [];

    if (currentBookings < targetBookings) {
      missing.add(_buildMissingItem(
        '• ${targetBookings - currentBookings} more completed bookings',
        Colors.blue.shade700,
      ));
    }

    if (currentRating < targetRating) {
      missing.add(_buildMissingItem(
        '• ${(targetRating - currentRating).toStringAsFixed(1)} higher rating',
        Colors.amber.shade800,
      ));
    }

    if (currentDays < targetDays) {
      missing.add(_buildMissingItem(
        '• ${targetDays - currentDays} more days on platform',
        Colors.green.shade700,
      ));
    }

    if (currentReferrals < targetReferrals) {
      missing.add(_buildMissingItem(
        '• ${targetReferrals - currentReferrals} more successful referrals',
        Colors.purple.shade600,
      ));
    }

    return missing;
  }

  Widget _buildMissingItem(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpgrade(AppLocalizations localizations) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Call the tier upgrade function
      final result = await supabase.rpc(
        'handle_buddy_tier_upgrade',
        params: {'p_buddy_id': supabase.auth.currentUser!.id},
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show success dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              'Upgrade Successful!',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: Text(
              result.toString(),
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      // Close loading dialog if still open
      if (mounted) Navigator.of(context).pop();

      // Show error dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              'Upgrade Failed',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Unable to process upgrade: ${error.toString()}',
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }
    }
  }
}
