import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/screens/buddy_service_management_screen.dart';
import 'package:mygobuddy/utils/constants.dart';

class NotificationDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> notification;

  const NotificationDetailsScreen({
    super.key,
    required this.notification,
  });

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);

    final String title = notification['title'] ?? 'Notification';
    final String message = notification['message'] ?? '';
    final String type = notification['type'] ?? 'general';
    String? couponCode = notification['coupon_code'];
    final DateTime createdAt = DateTime.parse(notification['created_at']);
    final String formattedDate = DateFormat('MMMM dd, yyyy • hh:mm a').format(createdAt);

    if (couponCode == null || couponCode.isEmpty) {
      couponCode = _extractCouponCodeFromMessage(message);
    }

    IconData icon;
    List<Color> gradientColors;
    Color iconColor;

    switch (type) {
      case 'promotion':
        icon = Icons.local_offer_rounded;
        gradientColors = [Colors.orange.shade400, Colors.orange.shade600];
        iconColor = Colors.orange.shade600;
        break;
      case 'booking':
      case 'booking_expired': // Added support for booking_expired type in details screen
        icon = Icons.event_available_rounded;
        gradientColors = [Colors.blue.shade400, Colors.blue.shade600];
        iconColor = Colors.blue.shade600;
        break;
      case 'announcement':
        icon = Icons.campaign_rounded;
        gradientColors = [Colors.purple.shade400, Colors.purple.shade600];
        iconColor = Colors.purple.shade600;
        break;
      case 'new_service':
        icon = Icons.add_business_rounded;
        gradientColors = [Colors.green.shade400, Colors.green.shade600];
        iconColor = Colors.green.shade600;
        break;
      default:
        icon = Icons.notifications_active_rounded;
        gradientColors = [Colors.indigo.shade400, Colors.indigo.shade600];
        iconColor = Colors.indigo.shade600;
    }

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
            'Notification Details',
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                backgroundColor,
                Colors.white,
              ],
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  margin: const EdgeInsets.only(bottom: 30),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              iconColor.withOpacity(0.1),
                              iconColor.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: iconColor.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _getTypeDisplayName(type),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: iconColor,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          formattedDate,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            message,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.grey.shade700,
                              height: 1.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],

                      if (couponCode != null && couponCode.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildCouponCodeWidget(context, couponCode, iconColor),
                      ],

                      if (type == 'new_service') ...[
                        const SizedBox(height: 24),
                        _buildNewServiceActionButton(context, iconColor),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewServiceActionButton(BuildContext context, Color accentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.1),
            accentColor.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.business_center_rounded,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'New Service Available',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'Add this service to your offerings and start earning more!',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _navigateToServiceManagement(context),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                'Manage My Services',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                shadowColor: accentColor.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToServiceManagement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const BuddyServiceManagementScreen(),
      ),
    );
  }

  Widget _buildCouponCodeWidget(BuildContext context, String couponCode, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withOpacity(0.3),
          width: 2,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.local_offer_rounded,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Coupon Code',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: CustomPaint(
              painter: DottedBorderPainter(color: accentColor.withOpacity(0.4)),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        couponCode,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                          letterSpacing: 2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _copyCouponCode(context, couponCode),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.copy_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          Text(
            'Tap to copy coupon code',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _copyCouponCode(BuildContext context, String couponCode) {
    Clipboard.setData(ClipboardData(text: couponCode));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'Coupon code copied!',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _getTypeDisplayName(String type) {
    switch (type) {
      case 'promotion':
        return 'Promotion';
      case 'booking':
        return 'Booking Update';
      case 'booking_expired': // Added display name for booking_expired type
        return 'Booking Expired';
      case 'announcement':
        return 'Announcement';
      case 'new_service':
        return 'New Service';
      default:
        return 'General';
    }
  }

  String? _extractCouponCodeFromMessage(String message) {
    // Split the message by common trigger words and look for codes after them
    final List<String> triggerWords = ['code', 'use code', 'coupon', 'promo'];

    for (String trigger in triggerWords) {
      final int index = message.toLowerCase().indexOf(trigger.toLowerCase());
      if (index != -1) {
        // Get the substring after the trigger word
        final String afterTrigger = message.substring(index + trigger.length).trim();

        // Look for the first alphanumeric sequence (likely the coupon code)
        final RegExp codeRegex = RegExp(r'^[^A-Z0-9]*([A-Z0-9]{4,12})');
        final Match? match = codeRegex.firstMatch(afterTrigger.toUpperCase());

        if (match != null) {
          final String? extractedCode = match.group(1);
          return extractedCode;
        }
      }
    }

    // Fallback: Look for any standalone alphanumeric code in the message
    final RegExp fallbackRegex = RegExp(r'\b([A-Z0-9]{6,12})\b');
    final Match? fallbackMatch = fallbackRegex.firstMatch(message.toUpperCase());
    if (fallbackMatch != null) {
      final String? fallbackCode = fallbackMatch.group(1);
      // Skip common words that might match the pattern
      if (fallbackCode != null && !['DISCOUNT', 'BOOKING', 'COUPON', 'PROMO'].contains(fallbackCode)) {
        return fallbackCode;
      }
    }

    return null;
  }
}

class DottedBorderPainter extends CustomPainter {
  final Color color;

  DottedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const double dashWidth = 4;
    const double dashSpace = 4;

    _drawDottedLine(canvas, paint, Offset.zero, Offset(size.width, 0), dashWidth, dashSpace);

    _drawDottedLine(canvas, paint, Offset(size.width, 0), Offset(size.width, size.height), dashWidth, dashSpace);

    _drawDottedLine(canvas, paint, Offset(size.width, size.height), Offset(0, size.height), dashWidth, dashSpace);

    _drawDottedLine(canvas, paint, Offset(0, size.height), Offset.zero, dashWidth, dashSpace);
  }

  void _drawDottedLine(Canvas canvas, Paint paint, Offset start, Offset end, double dashWidth, double dashSpace) {
    final double distance = (end - start).distance;
    final double dashCount = (distance / (dashWidth + dashSpace)).floor().toDouble();
    final Offset direction = (end - start) / distance;

    for (int i = 0; i < dashCount; i++) {
      final double startDistance = i * (dashWidth + dashSpace);
      final double endDistance = startDistance + dashWidth;

      final Offset dashStart = start + direction * startDistance;
      final Offset dashEnd = start + direction * endDistance;

      canvas.drawLine(dashStart, dashEnd, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
