import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/booking_service.dart';
import '../utils/localizations.dart';
import '../utils/constants.dart';

class BookingCancellationScreen extends StatefulWidget {
  final String bookingId;
  final String serviceName;
  final String buddyName;
  final String amount;

  const BookingCancellationScreen({
    Key? key,
    required this.bookingId,
    required this.serviceName,
    required this.buddyName,
    required this.amount,
  }) : super(key: key);

  @override
  State<BookingCancellationScreen> createState() => _BookingCancellationScreenState();
}

class _BookingCancellationScreenState extends State<BookingCancellationScreen> {
  String? selectedReason;
  final TextEditingController _customReasonController = TextEditingController();
  bool _isProcessing = false;

  final List<Map<String, dynamic>> cancellationReasons = [
    {
      'id': 'schedule_conflict',
      'title': 'Schedule Conflict',
      'subtitle': 'Something came up and I can\'t make it',
      'icon': Icons.schedule,
      'color': Colors.orange,
    },
    {
      'id': 'emergency',
      'title': 'Emergency',
      'subtitle': 'Unexpected urgent situation',
      'icon': Icons.emergency,
      'color': Colors.red,
    },
    {
      'id': 'buddy_issue',
      'title': 'Issue with Buddy',
      'subtitle': 'Concerns about the assigned buddy',
      'icon': Icons.person_off,
      'color': Colors.purple,
    },
    {
      'id': 'service_change',
      'title': 'Service No Longer Needed',
      'subtitle': 'I don\'t need this service anymore',
      'icon': Icons.cancel,
      'color': Colors.blue,
    },
    {
      'id': 'payment_issue',
      'title': 'Payment Problem',
      'subtitle': 'Issues with payment or billing',
      'icon': Icons.payment,
      'color': Colors.green,
    },
    {
      'id': 'other',
      'title': 'Other Reason',
      'subtitle': 'I\'ll specify my reason',
      'icon': Icons.edit,
      'color': Colors.grey,
    },
  ];

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  Future<void> _processCancellation() async {
    if (selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a cancellation reason'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (selectedReason == 'other' && _customReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide your custom reason'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final reason = selectedReason == 'other'
          ? _customReasonController.text.trim()
          : cancellationReasons.firstWhere((r) => r['id'] == selectedReason)['title'];

      final success = await BookingService.cancelBooking(widget.bookingId, reason);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking cancelled successfully. Refund will be processed within 3-5 business days.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.of(context).pop(true); // Return true to indicate cancellation success
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to cancel booking. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Cancel Booking',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: primaryTextColor,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Booking Info Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Booking Details',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.room_service, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      widget.serviceName,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person, color: Colors.green[600], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      widget.buddyName,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.attach_money, color: Colors.orange[600], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '\$${widget.amount}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Cancellation Reasons
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why are you cancelling?',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: cancellationReasons.length,
                      itemBuilder: (context, index) {
                        final reason = cancellationReasons[index];
                        final isSelected = selectedReason == reason['id'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  selectedReason = reason['id'];
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? primaryColor : Colors.grey[300]!,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: reason['color'].withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        reason['icon'],
                                        color: reason['color'],
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            reason['title'],
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: primaryTextColor,
                                            ),
                                          ),
                                          Text(
                                            reason['subtitle'],
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: primaryColor,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Custom reason input
                  if (selectedReason == 'other') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: _customReasonController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Please specify your reason for cancellation...',
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: secondaryTextColor),
                        ),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: primaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Cancel Button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processCancellation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isProcessing
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : Text(
                  'Cancel Booking & Process Refund',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
