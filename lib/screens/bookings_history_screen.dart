import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'refund_tracking_screen.dart'; // Import RefundTrackingScreen
import 'booking_details_screen.dart'; // Import BookingDetailsScreen

// Enum to represent the status of a booking
enum BookingStatus { all, confirmed, declined, cancelled, expired, completed }

class BookingsHistoryScreen extends StatefulWidget {
  const BookingsHistoryScreen({super.key});

  @override
  State<BookingsHistoryScreen> createState() => _BookingsHistoryScreenState();
}

class _BookingsHistoryScreenState extends State<BookingsHistoryScreen> {
  // Dummy data for the booking history
  List<Map<String, dynamic>> _allBookings = [];
  late List<Map<String, dynamic>> _filteredBookings;
  BookingStatus _selectedStatus = BookingStatus.all;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _filteredBookings = [];
    _fetchBookings();
  }

  Future<void> _fetchBookings() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser?.id;

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final response = await supabase
          .from('bookings')
          .select('''
            id,
            status,
            date,
            time,
            duration,
            amount,
            service,
            created_at,
            updated_at,
            expires_at,
            refund_status,
            client_id,
            buddy_id
          ''')
          .or('client_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .order('created_at', ascending: false);

      final bookings = response as List;
      final userIds = <String>{};
      for (final booking in bookings) {
        if (booking['client_id'] != null) userIds.add(booking['client_id']);
        if (booking['buddy_id'] != null) userIds.add(booking['buddy_id']);
      }

      Map<String, String> userNames = {};
      if (userIds.isNotEmpty) {
        final profilesResponse = await supabase
            .from('profiles')
            .select('id, name')
            .inFilter('id', userIds.toList());

        for (final profile in profilesResponse as List) {
          userNames[profile['id']] = profile['name'] ?? 'Unknown';
        }
      }

      _allBookings = bookings.map((booking) {
        // Determine the other party's name based on current user role
        String otherPartyName = 'Unknown';
        if (booking['client_id'] == currentUserId) {
          // Current user is client, show buddy name
          otherPartyName = userNames[booking['buddy_id']] ?? 'Unknown Buddy';
        } else {
          // Current user is buddy, show client name
          otherPartyName = userNames[booking['client_id']] ?? 'Unknown Client';
        }

        return {
          'id': booking['id'],
          'name': otherPartyName,
          'service': booking['service'] ?? 'Unknown Service',
          'date': DateTime.parse(booking['date']),
          'time': booking['time'] ?? '00:00:00',
          'status': _stringToBookingStatus(booking['status']),
          'amount': (booking['amount'] ?? 0).toDouble(),
          'refund_status': booking['refund_status'],
        };
      }).toList();

      _filterBookings();

    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  BookingStatus _stringToBookingStatus(String? status) {
    print('[v0] Booking status from database: "$status"');

    switch (status?.toLowerCase()) {
      case 'confirmed':
        return BookingStatus.confirmed;
      case 'declined':
        return BookingStatus.declined;
      case 'pending':
        return BookingStatus.confirmed; // Show pending as confirmed in history
      case 'cancelled':
        return BookingStatus.cancelled;
      case 'expired':
        return BookingStatus.expired;
      case 'completed':
        print('[v0] Mapping completed status to BookingStatus.completed');
        return BookingStatus.completed;
      case 'in_progress':
        return BookingStatus.confirmed; // Show in_progress as confirmed in history
      case 'accepted':
        return BookingStatus.confirmed; // Show accepted as confirmed in history
      default:
        print('[v0] Unknown status "$status", defaulting to confirmed');
        return BookingStatus.confirmed;
    }
  }

  void _filterBookings() {
    setState(() {
      _filteredBookings = _allBookings.where((booking) {
        final isHistoricalBooking = booking['status'] != BookingStatus.confirmed;
        final statusMatch = _selectedStatus == BookingStatus.all || booking['status'] == _selectedStatus;
        final dateMatch = booking['date'].month == _selectedDate.month && booking['date'].year == _selectedDate.year;
        return isHistoricalBooking && statusMatch && dateMatch;
      }).toList();
    });
  }

  String _statusToString(BookingStatus status) {
    String statusString = status.toString().split('.').last;
    return statusString[0].toUpperCase() + statusString.substring(1);
  }

  void _showStatusPicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SizedBox(
          height: 250,
          child: CupertinoPicker(
            itemExtent: 32.0,
            onSelectedItemChanged: (int index) {
              setState(() {
                _selectedStatus = BookingStatus.values[index];
                _filterBookings();
              });
            },
            scrollController: FixedExtentScrollController(
              initialItem: _selectedStatus.index,
            ),
            children: BookingStatus.values.map((BookingStatus status) {
              return Center(child: Text(_statusToString(status)));
            }).toList(),
          ),
        );
      },
    );
  }

  void _showDatePicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SizedBox(
          height: 250,
          child: CupertinoDatePicker(
            initialDateTime: _selectedDate,
            mode: CupertinoDatePickerMode.monthYear,
            onDateTimeChanged: (DateTime newDate) {
              setState(() {
                _selectedDate = newDate;
                _filterBookings();
              });
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);

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
          centerTitle: true,
          title: Text(
            'Bookings History',
            style: GoogleFonts.workSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: primaryTextColor,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: primaryTextColor,
                  size: 20,
                ),
                onPressed: _fetchBookings,
              ),
            ),
          ],
        ),
        body: Column(
            children: [
            _buildFilters(),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  'Error loading bookings',
                  style: GoogleFonts.poppins(fontSize: 16, color: Colors.red.shade600),
                ),
                Text(
                  _error!,
                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _fetchBookings,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
              : _filteredBookings.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy_outlined, size: 60, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No Bookings Found',
                  style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey.shade600),
                ),
                Text(
                  'Try adjusting your filters.',
                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500),
                ),
              ],
            ),
          )
              : RefreshIndicator(
            onRefresh: _fetchBookings,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              itemCount: _filteredBookings.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final booking = _filteredBookings[index];
                return _BookingHistoryItem(
                  id: booking['id'],
                  name: booking['name'],
                  service: booking['service'],
                  date: DateFormat('MMM dd, yyyy').format(booking['date']),
                  time: _formatTime(booking['time']),
                  status: booking['status'],
                  amount: booking['amount'],
                  refundStatus: booking['refund_status'],
                );
              },
            ),
          ),
        )
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
        mainAxisAlignment: MainAxisAlignment.center, // Centered the filters
        children: [
          _buildFilterChip(
            label: _statusToString(_selectedStatus),
            onTap: _showStatusPicker,
          ),
          const SizedBox(width: 32), // Increased spacing between filters
          _buildFilterChip(
            label: DateFormat('MMMM yyyy').format(_selectedDate),
            onTap: _showDatePicker,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.workSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down,
              color: const Color(0xFF6B7280),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String time) {
    try {
      final timeParts = time.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final timeOfDay = TimeOfDay(hour: hour, minute: minute);
      final now = DateTime.now();
      final dateTime = DateTime(now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
      return DateFormat('h:mm a').format(dateTime);
    } catch (e) {
      return time;
    }
  }
}

class _BookingHistoryItem extends StatelessWidget {
  final String id;
  final String name;
  final String service;
  final String date;
  final String time;
  final BookingStatus status;
  final double amount;
  final String? refundStatus;

  const _BookingHistoryItem({
    required this.id,
    required this.name,
    required this.service,
    required this.date,
    required this.time,
    required this.status,
    required this.amount,
    this.refundStatus,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> statusInfo = _getStatusInfo(status);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookingDetailsScreen(bookingId: id),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  color: statusInfo['iconColor'],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: statusInfo['bgColor'],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        statusInfo['icon'],
                        color: statusInfo['iconColor'],
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service,
                            style: GoogleFonts.workSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$name • $date',
                            style: GoogleFonts.openSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusInfo['bgColor'],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusInfo['text'],
                            style: GoogleFonts.workSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusInfo['textColor'],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${amount.toStringAsFixed(0)}',
                          style: GoogleFonts.workSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF19638D),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo(BookingStatus status) {
    switch (status) {
      case BookingStatus.confirmed:
        return {
          'icon': Icons.check,
          'text': 'Confirmed',
          'bgColor': Colors.blue.shade100,
          'iconColor': const Color(0xFF19638D),
          'textColor': const Color(0xFF19638D),
        };
      case BookingStatus.completed:
        return {
          'icon': Icons.check_circle,
          'text': 'Completed',
          'bgColor': Colors.blue.shade100,
          'iconColor': const Color(0xFF19638D),
          'textColor': const Color(0xFF19638D),
        };
      case BookingStatus.declined:
        return {
          'icon': Icons.close,
          'text': 'Declined',
          'bgColor': Colors.red.shade100,
          'iconColor': Colors.red.shade800,
          'textColor': Colors.red.shade800,
        };
      case BookingStatus.cancelled:
        return {
          'icon': Icons.cancel_outlined,
          'text': 'Cancelled',
          'bgColor': Colors.grey.shade100,
          'iconColor': Colors.grey.shade700,
          'textColor': Colors.grey.shade700,
        };
      case BookingStatus.expired:
        return {
          'icon': Icons.access_time_outlined,
          'text': 'Expired',
          'bgColor': Colors.amber.shade100,
          'iconColor': Colors.amber.shade800,
          'textColor': Colors.amber.shade800,
        };
      case BookingStatus.all:
        return {
          'icon': Icons.list,
          'text': 'All',
          'bgColor': Colors.blue.shade100,
          'iconColor': const Color(0xFF19638D),
          'textColor': const Color(0xFF19638D),
        };
    }
  }
}
