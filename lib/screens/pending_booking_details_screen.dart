import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:mygobuddy/screens/chat_screen.dart';

class PendingBookingDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> booking;

  const PendingBookingDetailsScreen({super.key, required this.booking});

  @override
  State<PendingBookingDetailsScreen> createState() =>
      _PendingBookingDetailsScreenState();
}

class _PendingBookingDetailsScreenState
    extends State<PendingBookingDetailsScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? get _clientProfile => widget.booking['client'];

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

  Future<void> _updateBookingStatus(String newStatus) async {
    if (_isLoading) return;

    if (newStatus == 'accepted') {
      final expiresAtStr = widget.booking['expires_at'] as String?;
      if (expiresAtStr != null) {
        final expiresAt = DateTime.parse(expiresAtStr);
        final now = DateTime.now().toUtc();

        if (now.isAfter(expiresAt)) {
          final localizations = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.translate('pending_booking_details_booking_expired', fallback: 'This booking has expired and can no longer be accepted.')),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop(true); // Return true to refresh the parent screen
          return;
        }
      }

      final bookingDate = DateTime.parse(widget.booking['date']);
      final timeParts = (widget.booking['time'] as String).split(':');
      final bookingTime = TimeOfDay(hour: int.parse(timeParts[0]), minute: int.parse(timeParts[1]));

      final bookingDateTime = DateTime(
        bookingDate.year,
        bookingDate.month,
        bookingDate.day,
        bookingTime.hour,
        bookingTime.minute,
      ).toUtc();

      final currentUtc = DateTime.now().toUtc();

      if (bookingDateTime.isBefore(currentUtc.subtract(Duration(minutes: 5)))) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('This booking time has already passed and cannot be accepted.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    final localizations = AppLocalizations.of(context)!;

    try {
      await supabase
          .from('bookings')
          .update({'status': newStatus})
          .eq('id', widget.booking['id']);

      if (mounted) {
        final successMessage = newStatus == 'accepted'
            ? localizations.translate('pending_booking_details_snackbar_accepted')
            : localizations.translate('pending_booking_details_snackbar_declined');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.translate('pending_booking_details_snackbar_error', args: {'error': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          localizations.translate('pending_booking_details_title'),
          style: GoogleFonts.poppins(
            color: primaryTextColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _clientProfile == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(localizations),
            const SizedBox(height: 24),
            _buildSectionTitle(localizations.translate('pending_booking_details_booking_section')),
            const SizedBox(height: 16),
            _buildModernDetailsCards(localizations),
            const SizedBox(height: 24),
            if (widget.booking['notes'] != null && widget.booking['notes']!.isNotEmpty) ...[
              _buildNotesCard(localizations),
              const SizedBox(height: 24),
            ],
            _buildAmountPaidSection(localizations),
          ],
        ),
      ),
      bottomNavigationBar: _buildActionButtons(localizations),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF111827),
      ),
    );
  }

  Widget _buildHeroCard(AppLocalizations localizations) {
    if (_clientProfile == null) {
      return Text(localizations.translate('pending_booking_details_client_unavailable'));
    }

    final String clientName = _clientProfile!['name'] ?? localizations.translate('pending_booking_details_no_name');
    final String? clientImageUrl = _clientProfile!['profile_picture'];
    final String service = widget.booking['service'] ?? localizations.translate('pending_booking_details_na');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF15803d),
            const Color(0xFF166534),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15803d).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundImage: (clientImageUrl != null && clientImageUrl.isNotEmpty)
                      ? NetworkImage(clientImageUrl)
                      : const AssetImage('assets/images/default_avatar.png') as ImageProvider,
                  backgroundColor: Colors.white.withOpacity(0.2),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'New booking request',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: () async {
                    try {
                      final currentUserId = supabase.auth.currentUser?.id;
                      final clientId = widget.booking['client_id'];
                      if (currentUserId == null || clientId == null) return;

                      final conversationId = await _getOrCreateConversation(
                          currentUserId,
                          clientId
                      );

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            conversationId: conversationId,
                            otherUserName: clientName,
                            otherUserAvatar: clientImageUrl,
                            otherUserId: clientId,
                          ),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error opening chat: ${e.toString()}')),
                      );
                    }
                  },
                  icon: Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              service,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDetailsCards(AppLocalizations localizations) {
    final date = DateTime.parse(widget.booking['date']);
    final timeParts = (widget.booking['time'] as String).split(':');
    final time = TimeOfDay(hour: int.parse(timeParts[0]), minute: int.parse(timeParts[1]));
    final String location = _clientProfile?['location'] ?? localizations.translate('pending_booking_details_na');

    final durationInMinutes = widget.booking['duration'] as int? ?? 0;
    final hours = (durationInMinutes / 60).round();
    final durationText = hours == 1
        ? localizations.translate('pending_booking_details_duration_hour', args: {'count': hours.toString()})
        : localizations.translate('pending_booking_details_duration_hours', args: {'count': hours.toString()});

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ModernVisualCard(
                icon: Icons.calendar_today_outlined,
                iconColor: const Color(0xFF15803d),
                iconBgColor: const Color(0xFFf0fdf4),
                label: localizations.translate('pending_booking_details_date_label'),
                value: DateFormat('MMM dd\nyyyy').format(date),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, const Color(0xFFf0fdf4)],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModernVisualCard(
                icon: Icons.access_time_rounded,
                iconColor: const Color(0xFF84cc16),
                iconBgColor: const Color(0xFFf7fee7),
                label: localizations.translate('pending_booking_details_time_label'),
                value: time.format(context),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, const Color(0xFFf7fee7)],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ModernVisualCard(
                icon: Icons.timelapse_rounded,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFecfdf5),
                label: localizations.translate('pending_booking_details_duration_label'),
                value: durationText,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, const Color(0xFFecfdf5)],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModernVisualCard(
                icon: Icons.location_on_outlined,
                iconColor: const Color(0xFF65a30d),
                iconBgColor: const Color(0xFFf7fee7),
                label: localizations.translate('pending_booking_details_location_label'),
                value: location,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, const Color(0xFFf7fee7)],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNotesCard(AppLocalizations localizations) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFfef3c7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.note_outlined,
                  color: const Color(0xFFf59e0b),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                localizations.translate('pending_booking_details_note_label'),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.booking['notes']!,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF6b7280),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountPaidSection(AppLocalizations localizations) {
    final amount = widget.booking['amount']?.toString() ?? '0';
    final priceText = '\$${double.parse(amount).toStringAsFixed(2)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFecfdf5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.attach_money_rounded,
              color: const Color(0xFF059669),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Amount Paid',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF6b7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                priceText,
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF059669),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(AppLocalizations localizations) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
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
                  onPressed: _isLoading ? null : () => _updateBookingStatus('declined'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFdc2626),
                    side: BorderSide(color: const Color(0xFFdc2626), width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    localizations.translate('pending_booking_details_decline_button'),
                    style: GoogleFonts.poppins(
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
                  onPressed: _isLoading ? null : () => _updateBookingStatus('accepted'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803d),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                      : Text(
                    localizations.translate('pending_booking_details_accept_button'),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            style: GoogleFonts.poppins(
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
              style: GoogleFonts.poppins(
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
