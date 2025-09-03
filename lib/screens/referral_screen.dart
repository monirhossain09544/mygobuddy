import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  late Future<String?> _referralCodeFuture;
  late Future<List<Map<String, dynamic>>> _referralsFuture;

  @override
  void initState() {
    super.initState();
    _referralCodeFuture = _fetchReferralCode();
    _referralsFuture = _fetchReferrals();
  }

  Future<String?> _fetchReferralCode() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final data = await supabase
          .from('profiles')
          .select('referral_code')
          .eq('id', userId)
          .single();
      return data['referral_code'];
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to load referral code: $e',
            isError: true);
      }
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReferrals() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final data = await supabase
          .from('referrals')
          .select(
          '*, referred_user:profiles!referrals_referred_user_id_fkey(name, profile_picture)')
          .eq('referrer_id', userId)
          .order('created_at', ascending: false);
      return data;
    } catch (e) {
      // Don't show a snackbar here, as it might conflict with the code fetch error
      debugPrint('Failed to load referrals: $e');
      return [];
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _referralCodeFuture = _fetchReferralCode();
      _referralsFuture = _fetchReferrals();
    });
  }

  Future<void> _shareCode(String code) async {
    final localizations = AppLocalizations.of(context);
    final shareText =
    localizations.translate('referral_share_text').replaceAll('{code}', code);

    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      shareText,
      subject: localizations.translate('referral_screen_header_title'),
      sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
    );
  }

  void _copyCode(String code) {
    final localizations = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: code));
    context.showSnackBar(
        localizations.translate('referral_screen_code_copied_success'));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    const Color primaryColor = Color(0xFF19638D);
    const Color accentColor = Color(0xFFF15808);
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          surfaceTintColor: backgroundColor,
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300)),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: primaryTextColor,
                  size: 18,
                ),
              ),
            ),
          ),
          title: Text(
            localizations.translate('referral_screen_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: RefreshIndicator(
          onRefresh: _refreshData,
          color: primaryColor,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildHeaderCard(localizations, primaryColor),
              const SizedBox(height: 24),
              _buildReferralCodeSection(
                  localizations, primaryColor, accentColor),
              const SizedBox(height: 24),
              _buildSectionTitle(
                  localizations.translate('referral_screen_history_title')),
              const SizedBox(height: 12),
              _buildHistorySection(localizations),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF111827),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
      AppLocalizations localizations, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withOpacity(0.1), primaryColor.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.card_giftcard_outlined, color: primaryColor, size: 40),
          const SizedBox(height: 12),
          Text(
            localizations.translate('referral_screen_header_title'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.translate('referral_screen_header_subtitle'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: primaryColor.withOpacity(0.9),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCodeSection(AppLocalizations localizations,
      Color primaryColor, Color accentColor) {
    return FutureBuilder<String?>(
      future: _referralCodeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCodeCard();
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Center(
            child: Text(
              localizations.translate('referral_code_load_error'),
              style: GoogleFonts.poppins(color: Colors.red.shade700),
            ),
          );
        }
        final code = snapshot.data!;
        return _buildReferralCodeCard(
            code, localizations, primaryColor, accentColor);
      },
    );
  }

  Widget _buildLoadingCodeCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildReferralCodeCard(String code, AppLocalizations localizations,
      Color primaryColor, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            localizations.translate('referral_screen_your_code_title'),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          DottedBorder(
            color: primaryColor.withOpacity(0.5),
            strokeWidth: 2,
            dashPattern: const [8, 6],
            radius: const Radius.circular(12),
            borderType: BorderType.RRect,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    code,
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => _copyCode(code),
                    icon: Icon(Icons.copy_all_outlined, color: primaryColor.withOpacity(0.8)),
                    tooltip: localizations.translate('referral_screen_copy_button'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareCode(code),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: Text(
                  localizations.translate('referral_screen_share_button')),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(AppLocalizations localizations) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _referralsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: CircularProgressIndicator(color: Color(0xFF19638D)),
              ));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final referrals = snapshot.data!;
        if (referrals.isEmpty) {
          return _buildEmptyHistory(localizations);
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: referrals.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final referral = referrals[index];
            return _buildHistoryListItem(referral, localizations);
          },
        );
      },
    );
  }

  Widget _buildEmptyHistory(AppLocalizations localizations) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_add_outlined,
              size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            localizations.translate('referral_screen_no_referrals_title'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.translate('referral_screen_no_referrals_subtitle'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryListItem(
      Map<String, dynamic> referral, AppLocalizations localizations) {
    final status = referral['status'] as String;
    final isCompleted = status == 'completed';
    final createdAt = DateTime.parse(referral['created_at']);
    final referredUser = referral['referred_user'];

    final String name = referredUser?['name'] ??
        localizations.translate('referral_screen_referred_user_placeholder');
    final String? avatarUrl = referredUser?['profile_picture'];

    final Color statusColor =
    isCompleted ? const Color(0xFF16A34A) : const Color(0xFFD97706);
    final String statusText = isCompleted
        ? localizations.translate('referral_screen_status_completed')
        : localizations.translate('referral_screen_status_pending');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade200,
            backgroundImage:
            avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? const Icon(Icons.person_outline, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Joined ${timeago.format(createdAt)}',
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: GoogleFonts.poppins(
                color: statusColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
