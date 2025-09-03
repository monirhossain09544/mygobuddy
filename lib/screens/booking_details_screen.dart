import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/models/booking.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:mygobuddy/screens/booking_cancellation_screen.dart';
import 'package:mygobuddy/services/booking_service.dart';
import 'package:mygobuddy/widgets/refund_status_widget.dart';
import 'package:mygobuddy/screens/refund_tracking_screen.dart';
import 'package:mygobuddy/screens/chat_screen.dart';
import 'package:mygobuddy/screens/trip_completion_popup.dart';
import 'review_screen.dart'; // Import the new ReviewScreen instead of using popup

class BookingDetailsScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailsScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  Future<Map<String, dynamic>>? _detailsFuture;
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      setState(() {
        _detailsFuture = _fetchBookingDetails();
      });
      _isInitialized = true;
    }
  }

  Future<Map<String, dynamic>> _fetchBookingDetails() async {
    final localizations = AppLocalizations.of(context);
    try {
      final response = await supabase
          .from('bookings')
          .select('*, profiles:buddy_id(*)')
          .eq('id', widget.bookingId)
          .single();
      final booking = Booking.fromMap(response);

      // Also fetch the translated service name for display
      String translatedService = booking.service; // Fallback to original name
      try {
        final serviceResponse = await supabase
            .from('services')
            .select('name_key')
            .eq('name', booking.service)
            .single();
        final nameKey = serviceResponse['name_key'];
        if (nameKey != null) {
          translatedService =
              localizations.translate(nameKey, fallback: booking.service);
        }
      } catch (e) {
        // If service not in services table or other error, use original name
      }

      final reviewAndTipStatus = await _checkReviewAndTipStatus();

      return {
        'booking': booking,
        'translatedService': translatedService,
        'refundStatus': response['refund_status'],
        'refundAmount': response['refund_amount']?.toDouble(),
        'refundInitiatedAt': response['refund_initiated_at'] != null
            ? DateTime.parse(response['refund_initiated_at'])
            : null,
        'refundCompletedAt': response['refund_completed_at'] != null
            ? DateTime.parse(response['refund_completed_at'])
            : null,
        'refundErrorMessage': response['refund_error_message'],
        'hasReview': reviewAndTipStatus['hasReview'],
        'hasTip': reviewAndTipStatus['hasTip'],
        'existingReview': reviewAndTipStatus['existingReview'],
        'existingTip': reviewAndTipStatus['existingTip'],
      };
    } catch (e) {
      throw Exception(localizations.translate('booking_details_error_loading',
          args: {'error': e.toString()}));
    }
  }

  Future<Map<String, dynamic>> _checkReviewAndTipStatus() async {
    bool hasReview = false;
    bool hasTip = false;
    Map<String, dynamic>? existingReview;
    Map<String, dynamic>? existingTip;

    try {
      final reviewResponse = await supabase
          .from('reviews')
          .select('*')
          .eq('booking_id', widget.bookingId)
          .maybeSingle();
      hasReview = reviewResponse != null;
      existingReview = reviewResponse;

      final tipResponse = await supabase
          .from('tips')
          .select('*')
          .eq('booking_id', widget.bookingId)
          .maybeSingle();
      hasTip = tipResponse != null;
      existingTip = tipResponse;
    } catch (e) {
      // If error checking review/tip status, assume false
    }

    return {
      'hasReview': hasReview,
      'hasTip': hasTip,
      'existingReview': existingReview,
      'existingTip': existingTip,
    };
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryTextColor = Color(0xFF111827);
    const Color backgroundColor = Color(0xFFF9FAFB);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          localizations.translate('booking_details_title'),
          style: GoogleFonts.workSans(
            color: primaryTextColor,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: primaryTextColor, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _detailsFuture == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return Center(
                child:
                Text(localizations.translate('booking_details_not_found')));
          }

          final booking = snapshot.data!['booking'] as Booking;
          final translatedService = snapshot.data!['translatedService'] as String;
          return _buildDetailsView(context, booking, translatedService);
        },
      ),
    );
  }

  Widget _buildDetailsView(
      BuildContext context, Booking booking, String translatedService) {
    const Color primaryColor = Color(0xFF19638D); // Changed from green-700 to home screen blue
    const Color accentColor = Color(0xFF19638D); // Changed from lime-500 to home screen blue
    const Color primaryTextColor = Color(0xFF374151); // gray-700
    const Color cardBackground = Color(0xFFe0f2fe); // Changed from green-50 to light blue
    final localizations = AppLocalizations.of(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroCard(context, booking, translatedService, localizations),
                const SizedBox(height: 20),
                _buildBuddyProfileCard(context, booking, localizations),
                const SizedBox(height: 20),
                _buildBookingDetailsCard(context, booking, translatedService, localizations),
                const SizedBox(height: 8),
                if (booking.amount != null)
                  _buildPaymentCard(context, booking, localizations),
                const SizedBox(height: 8),
                if (booking.status == 'cancelled')
                  FutureBuilder<Map<String, dynamic>>(
                    future: _detailsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final data = snapshot.data!;
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => RefundTrackingScreen(
                                  bookingId: widget.bookingId,
                                  refundAmount: booking.amount?.toStringAsFixed(2) ?? '0.00',
                                ),
                              ),
                            );
                          },
                          child: RefundStatusWidget(
                            refundStatus: data['refundStatus'],
                            refundAmount: data['refundAmount'],
                            refundInitiatedAt: data['refundInitiatedAt'],
                            refundCompletedAt: data['refundCompletedAt'],
                            errorMessage: data['refundErrorMessage'],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                const SizedBox(height: 24), // Space for floating action buttons
              ],
            ),
          ),
        ),
        _buildFloatingActionButtons(context, primaryColor, accentColor, localizations, booking),
      ],
    );
  }

  Widget _buildHeroCard(BuildContext context, Booking booking, String translatedService, AppLocalizations localizations) {
    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;
    String statusText;

    switch (booking.status) {
      case 'confirmed':
        statusColor = const Color(0xFF19638D);
        statusBgColor = const Color(0xFFe0f2fe);
        statusIcon = Icons.check_circle_outline;
        statusText = 'Confirmed';
        break;
      case 'pending':
        statusColor = const Color(0xFFf59e0b);
        statusBgColor = const Color(0xFFFEF3C7);
        statusIcon = Icons.schedule;
        statusText = 'Pending';
        break;
      case 'expired':
        statusColor = const Color(0xFFf59e0b);
        statusBgColor = const Color(0xFFFEF3C7);
        statusIcon = Icons.access_time;
        statusText = 'Expired';
        break;
      case 'cancelled':
        statusColor = const Color(0xFFdc2626);
        statusBgColor = const Color(0xFFfef2f2);
        statusIcon = Icons.cancel_outlined;
        statusText = 'Cancelled';
        break;
      case 'completed':
        statusColor = const Color(0xFF19638D);
        statusBgColor = const Color(0xFFe0f2fe);
        statusIcon = Icons.check_circle;
        statusText = 'Completed';
        break;
      default:
        statusColor = const Color(0xFF6b7280);
        statusBgColor = const Color(0xFFf9fafb);
        statusIcon = Icons.info_outline;
        statusText = booking.status;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF19638D),
            const Color(0xFF1565c0),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF19638D).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  translatedService,
                  style: GoogleFonts.workSans(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: GoogleFonts.openSans(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.white.withOpacity(0.8), size: 18),
              const SizedBox(width: 8),
              Text(
                DateFormat('EEEE, MMM dd, yyyy').format(booking.date),
                style: GoogleFonts.openSans(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, color: Colors.white.withOpacity(0.8), size: 18),
              const SizedBox(width: 8),
              Text(
                '${booking.time.format(context)} • ${booking.duration} minutes',
                style: GoogleFonts.openSans(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBuddyProfileCard(BuildContext context, Booking booking, AppLocalizations localizations) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFFe0f2fe),
              backgroundImage: booking.buddyAvatarUrl != null && booking.buddyAvatarUrl!.isNotEmpty
                  ? NetworkImage(booking.buddyAvatarUrl!)
                  : null,
              child: booking.buddyAvatarUrl == null || booking.buddyAvatarUrl!.isEmpty
                  ? Icon(Icons.person, size: 32, color: const Color(0xFF19638D))
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.buddyName,
                  style: GoogleFonts.workSans(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localizations.translate('booking_details_your_buddy'),
                  style: GoogleFonts.openSans(
                    fontSize: 14,
                    color: const Color(0xFF6b7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFe0f2fe),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.star,
              color: const Color(0xFF19638D),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingDetailsCard(BuildContext context, Booking booking, String translatedService, AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Booking Details',
            style: GoogleFonts.workSans(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Service and Date Row
        Row(
          children: [
            Expanded(
              child: _ModernVisualCard(
                icon: Icons.work_outline_rounded,
                iconColor: const Color(0xFF19638D),
                iconBgColor: const Color(0xFFe0f2fe),
                label: localizations.translate('booking_details_service'),
                value: translatedService,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, const Color(0xFFe0f2fe)],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModernVisualCard(
                icon: Icons.calendar_today_outlined,
                iconColor: const Color(0xFF19638D),
                iconBgColor: const Color(0xFFe0f2fe),
                label: localizations.translate('booking_details_date'),
                value: DateFormat('MMM dd\nyyyy').format(booking.date),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, const Color(0xFFe0f2fe)],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Time and Duration Row
        Row(
          children: [
            Expanded(
              child: _ModernVisualCard(
                icon: Icons.access_time_rounded,
                iconColor: const Color(0xFF19638D),
                iconBgColor: const Color(0xFFe0f2fe),
                label: localizations.translate('booking_details_time'),
                value: booking.time.format(context),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, const Color(0xFFe0f2fe)],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModernVisualCard(
                icon: Icons.timelapse_rounded,
                iconColor: const Color(0xFF19638D),
                iconBgColor: const Color(0xFFe0f2fe),
                label: localizations.translate('booking_details_duration'),
                value: '${booking.duration}\nminutes',
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, const Color(0xFFe0f2fe)],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentCard(BuildContext context, Booking booking, AppLocalizations localizations) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFe0f2fe),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.monetization_on_outlined,
              color: const Color(0xFF19638D),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.translate('booking_details_amount_paid'),
                  style: GoogleFonts.openSans(
                    fontSize: 14,
                    color: const Color(0xFF6b7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${booking.amount!.toStringAsFixed(2)}',
                  style: GoogleFonts.workSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF19638D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButtons(
      BuildContext context, Color primaryColor, Color accentColor, AppLocalizations localizations, Booking booking) {

    if (booking.status == 'cancelled') {
      return const SizedBox.shrink();
    }

    if (booking.status == 'expired') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFf59e0b).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  color: const Color(0xFFf59e0b),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This booking request has expired as the buddy did not respond in time.',
                    style: GoogleFonts.openSans(
                      color: const Color(0xFFf59e0b),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (booking.status == 'completed') {
      return FutureBuilder<Map<String, dynamic>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFe0f2fe),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: primaryColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: primaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This booking has been completed.',
                          style: GoogleFonts.openSans(
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final hasReview = data['hasReview'] as bool;
          final hasTip = data['hasTip'] as bool;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Completion status message
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFf0fdf4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: primaryColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: primaryColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This booking has been completed.',
                            style: GoogleFonts.openSans(
                              color: primaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Review and tip buttons (only show if not already done AND user is the client)
                  if ((!hasReview || !hasTip) && _isCurrentUserClient(data['booking'] as Booking)) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (!hasReview) ...[
                          Expanded(
                            child: Container(
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: () => _showReviewAndTipScreen(data['booking'] as Booking),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: primaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                icon: Icon(Icons.star_outline, size: 18),
                                label: Text(
                                  'Leave Review',
                                  style: GoogleFonts.workSans(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!hasTip) const SizedBox(width: 12),
                        ],
                        if (!hasTip) ...[
                          Expanded(
                            child: Container(
                              height: 56,
                              child: OutlinedButton.icon(
                                onPressed: () => _showReviewAndTipScreen(data['booking'] as Booking),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  side: BorderSide(color: primaryColor, width: 2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                icon: Icon(Icons.monetization_on_outlined, size: 18),
                                label: Text(
                                  'Add Tip',
                                  style: GoogleFonts.workSans(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ] else if ((hasReview || hasTip) && _isCurrentUserClient(data['booking'] as Booking)) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () => _showExistingReview(data['existingReview']),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: primaryColor,
                                backgroundColor: primaryColor.withOpacity(0.1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              icon: Icon(Icons.star, size: 18),
                              label: Text(
                                'View/Edit Review',
                                style: GoogleFonts.workSans(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 56,
                            child: OutlinedButton.icon(
                              onPressed: () => _showReviewAndTipScreen(data['booking'] as Booking),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                                side: BorderSide(color: primaryColor, width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: Icon(Icons.monetization_on_outlined, size: 18),
                              label: Text(
                                'Add Tip',
                                style: GoogleFonts.workSans(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Show message if both review and tip are already done
                  if (hasReview && hasTip && _isCurrentUserClient(data['booking'] as Booking)) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFf0f9ff),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF0ea5e9).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite,
                            color: const Color(0xFF0ea5e9),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Thank you for your review and tip!',
                              style: GoogleFonts.openSans(
                                color: const Color(0xFF0ea5e9),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 56,
                child: OutlinedButton(
                  onPressed: () async {
                    final bookingData = await _detailsFuture;
                    if (bookingData != null) {
                      final booking = bookingData['booking'] as Booking;
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (context) => BookingCancellationScreen(
                            bookingId: widget.bookingId,
                            serviceName: bookingData['translatedService'] as String,
                            buddyName: booking.buddyName,
                            amount: booking.amount?.toStringAsFixed(2) ?? '0.00',
                          ),
                        ),
                      );

                      if (result == true) {
                        setState(() {
                          _detailsFuture = _fetchBookingDetails();
                        });
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFdc2626),
                    side: BorderSide(color: const Color(0xFFdc2626), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    localizations.translate('booking_details_button_cancel'),
                    style: GoogleFonts.workSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      final currentUserId = supabase.auth.currentUser?.id;
                      if (currentUserId == null) return;

                      final conversationId = await _getOrCreateConversation(
                          currentUserId,
                          booking.buddyId
                      );

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            conversationId: conversationId,
                            otherUserName: booking.buddyName,
                            otherUserAvatar: booking.buddyAvatarUrl,
                            otherUserId: booking.buddyId,
                          ),
                        ),
                      );
                    } catch (e) {
                      context.showSnackBar('Error opening chat: ${e.toString()}');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          localizations.translate('booking_details_button_contact'),
                          style: GoogleFonts.workSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isCurrentUserClient(Booking booking) {
    final currentUserId = supabase.auth.currentUser?.id;
    return currentUserId != null && currentUserId == booking.clientId;
  }

  void _showReviewAndTipScreen(Booking booking) async {
    if (!_isCurrentUserClient(booking)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only clients can leave reviews and tips'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ReviewScreen(
          bookingId: widget.bookingId,
          buddyName: booking.buddyName,
          buddyImage: booking.buddyAvatarUrl ?? '',
          serviceName: booking.service,
        ),
      ),
    );

    // Refresh the booking details if review/tip was submitted
    if (result == true) {
      setState(() {
        _detailsFuture = _fetchBookingDetails();
      });
    }
  }

  void _showExistingReview(Map<String, dynamic> review) async {
    final booking = await _fetchBookingDetails().then((data) => data['booking'] as Booking);

    if (!_isCurrentUserClient(booking)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only clients can view and edit reviews'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ReviewScreen(
          bookingId: widget.bookingId,
          buddyName: booking.buddyName,
          buddyImage: booking.buddyAvatarUrl ?? '',
          serviceName: booking.service,
          existingReview: review, // Pass existing review data
        ),
      ),
    );

    // Refresh the booking details if review was updated
    if (result == true) {
      setState(() {
        _detailsFuture = _fetchBookingDetails();
      });
    }
  }

  Future<String> _getOrCreateConversation(String userId1, String userId2) async {
    try {
      final existingConversation = await supabase
          .from('conversations')
          .select('id')
          .or('and(participant_one_id.eq.$userId1,participant_two_id.eq.$userId2),and(participant_one_id.eq.$userId2,participant_two_id.eq.$userId1)')
          .maybeSingle();

      if (existingConversation != null) {
        return existingConversation['id'];
      }

      final newConversation = await supabase
          .from('conversations')
          .insert({
        'participant_one_id': userId1,
        'participant_two_id': userId2,
        'created_at': DateTime.now().toIso8601String(),
      })
          .select('id')
          .single();

      return newConversation['id'];
    } catch (e) {
      throw Exception('Failed to create conversation: $e');
    }
  }
}

class _ModernVisualCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String label;
  final String value;
  final Gradient gradient;

  const _ModernVisualCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.label,
    required this.value,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: iconColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: iconColor.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.openSans(
              color: const Color(0xFF6b7280),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.workSans(
                color: const Color(0xFF374151),
                fontWeight: FontWeight.bold,
                fontSize: 14,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
