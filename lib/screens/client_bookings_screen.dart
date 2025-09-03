import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/screens/booking_details_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';
import 'dart:async';

enum ClientBookingTab { upcoming, past }

enum BookingStatus { all, pending, accepted, inProgress, completed, cancelled, declined, expired }

class ClientBookingsScreen extends StatefulWidget {
  const ClientBookingsScreen({super.key});

  @override
  State<ClientBookingsScreen> createState() => _ClientBookingsScreenState();
}

class _ClientBookingsScreenState extends State<ClientBookingsScreen> {
  ClientBookingTab _selectedTab = ClientBookingTab.upcoming;
  late Future<List<Map<String, dynamic>>> _bookingsFuture;
  final String? _currentUserId = supabase.auth.currentUser?.id;

  StreamSubscription<List<Map<String, dynamic>>>? _bookingSubscription;
  List<Map<String, dynamic>> _cachedBookings = [];

  BookingStatus _selectedStatus = BookingStatus.all;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadBookings();
    _listenForBookingUpdates();
  }

  @override
  void dispose() {
    _bookingSubscription?.cancel();
    super.dispose();
  }

  void _listenForBookingUpdates() {
    if (_currentUserId == null) return;

    _bookingSubscription = supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .listen((bookings) {
      // Filter bookings for current user
      final userBookings = bookings.where((booking) =>
      booking['client_id'] == _currentUserId
      ).toList();

      if (mounted) {
        setState(() {
          _cachedBookings = userBookings;
          // Refresh the current view with updated data
          _loadBookings();
        });

        _checkForNewlyStartedTrips(userBookings);
      }
    });
  }

  void _checkForNewlyStartedTrips(List<Map<String, dynamic>> newBookings) {
    final appLocalizations = AppLocalizations.of(context)!;

    for (final booking in newBookings) {
      final confirmationRequested = booking['confirmation_requested_at'] != null;
      final buddyConfirmed = booking['buddy_confirmed'] as bool? ?? false;
      final clientConfirmed = booking['client_confirmed'] as bool? ?? false;
      final bothConfirmed = booking['both_confirmed'] as bool? ?? false;

      if (confirmationRequested && !clientConfirmed && buddyConfirmed) {
        // Buddy confirmed, waiting for client
        final buddy = booking['buddies'] as Map<String, dynamic>? ?? {};
        final buddyName = buddy['name'] ?? 'Your buddy';
        final service = booking['service'] ?? 'Service';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.touch_app, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$buddyName is ready to start! Confirm to begin your $service trip.',
                    style: GoogleFonts.workSans(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF3B82F6),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            action: SnackBarAction(
              label: 'Confirm',
              textColor: Colors.white,
              onPressed: () => _confirmTripStart(booking['id']),
            ),
          ),
        );
        break;
      } else if (confirmationRequested && !clientConfirmed && !buddyConfirmed) {
        // Initial confirmation request
        final buddy = booking['buddies'] as Map<String, dynamic>? ?? {};
        final buddyName = buddy['name'] ?? 'Your buddy';
        final service = booking['service'] ?? 'Service';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$buddyName wants to start your $service trip. Please confirm.',
                    style: GoogleFonts.workSans(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF8B5CF6),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            action: SnackBarAction(
              label: 'Confirm',
              textColor: Colors.white,
              onPressed: () => _confirmTripStart(booking['id']),
            ),
          ),
        );
        break;
      } else if (booking['status'] == 'in_progress' && bothConfirmed) {
        final buddy = booking['buddies'] as Map<String, dynamic>? ?? {};
        final buddyName = buddy['name'] ?? 'Your buddy';
        final service = booking['service'] ?? 'Service';

        // Show notification that trip has started
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.directions_run, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trip started! $buddyName is now providing $service',
                    style: GoogleFonts.workSans(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            action: SnackBarAction(
              label: 'View Trip',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to trip screen (TripScreen will automatically show active trip)
                Navigator.pushNamed(context, '/trip');
              },
            ),
          ),
        );
        break; // Only show one notification at a time
      }
    }
  }

  Future<void> _confirmTripStart(String bookingId) async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final response = await supabase.rpc('confirm_trip_start', params: {
        'booking_id': bookingId,
        'user_id': currentUserId,
        'user_type': 'client',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip confirmed! Your buddy will be notified.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        _loadBookings(); // Refresh bookings
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming trip: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _loadBookings() {
    setState(() {
      if (_selectedTab == ClientBookingTab.upcoming) {
        _bookingsFuture = _fetchBookings(['pending', 'accepted', 'in_progress']);
      } else {
        _bookingsFuture = _fetchBookings(['completed', 'cancelled', 'declined', 'expired']);
      }
    });
  }

  void _onTabSelected(ClientBookingTab tab) {
    if (_selectedTab != tab) {
      setState(() {
        _selectedTab = tab;
        _selectedStatus = BookingStatus.all;
        _selectedDate = DateTime.now();
        _loadBookings();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBookings(List<String> statuses) async {
    if (_currentUserId == null) return [];
    try {
      List<Map<String, dynamic>> bookings;

      if (_cachedBookings.isNotEmpty) {
        bookings = _cachedBookings;
      } else {
        final response = await supabase
            .from('bookings')
            .select('*')
            .eq('client_id', _currentUserId!)
            .inFilter('status', statuses)
            .order('created_at', ascending: false);

        bookings = List<Map<String, dynamic>>.from(response);
      }

      for (var booking in bookings) {
        final buddyId = booking['buddy_id'];
        if (buddyId != null) {
          try {
            final buddyResponse = await supabase
                .from('buddies')
                .select('id, name, profile_picture')
                .eq('id', buddyId)
                .single();

            booking['buddies'] = buddyResponse;
          } catch (e) {
            booking['buddies'] = {};
          }
        } else {
          booking['buddies'] = {};
        }
      }

      // Filter by status and apply other filters
      final filteredByStatus = bookings.where((booking) =>
          statuses.contains(booking['status'])
      ).toList();

      return _applyFilters(filteredByStatus);
    } catch (e) {
      if (mounted) {
        final appLocalizations = AppLocalizations.of(context)!;
        context.showSnackBar(
          '${appLocalizations.translate('clientBookings_errorFetching')}: ${e.toString()}',
          isError: true,
        );
      }
      return [];
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> bookings) {
    return bookings.where((booking) {
      // Status filter
      if (_selectedStatus != BookingStatus.all) {
        final bookingStatus = booking['status'] as String?;
        final statusMatch = _getStatusFromString(bookingStatus) == _selectedStatus;
        if (!statusMatch) return false;
      }

      // Date filter (month and year)
      final bookingDate = DateTime.parse(booking['date']);
      final dateMatch = bookingDate.month == _selectedDate.month &&
          bookingDate.year == _selectedDate.year;

      return dateMatch;
    }).toList();
  }

  BookingStatus _getStatusFromString(String? status) {
    switch (status) {
      case 'pending': return BookingStatus.pending;
      case 'accepted': return BookingStatus.accepted;
      case 'in_progress': return BookingStatus.inProgress;
      case 'completed': return BookingStatus.completed;
      case 'cancelled': return BookingStatus.cancelled;
      case 'declined': return BookingStatus.declined;
      case 'expired': return BookingStatus.expired;
      default: return BookingStatus.all;
    }
  }

  String _statusToString(BookingStatus status) {
    switch (status) {
      case BookingStatus.all: return 'All';
      case BookingStatus.pending: return 'Pending';
      case BookingStatus.accepted: return 'Confirmed';
      case BookingStatus.inProgress: return 'Active Trip';
      case BookingStatus.completed: return 'Completed';
      case BookingStatus.cancelled: return 'Cancelled';
      case BookingStatus.declined: return 'Declined';
      case BookingStatus.expired: return 'Expired';
    }
  }

  void _showStatusPicker() {
    final availableStatuses = _selectedTab == ClientBookingTab.upcoming
        ? [BookingStatus.all, BookingStatus.pending, BookingStatus.accepted, BookingStatus.inProgress]
        : [BookingStatus.all, BookingStatus.completed, BookingStatus.cancelled, BookingStatus.declined, BookingStatus.expired];

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SizedBox(
          height: 250,
          child: CupertinoPicker(
            itemExtent: 32.0,
            onSelectedItemChanged: (int index) {
              setState(() {
                _selectedStatus = availableStatuses[index];
                _loadBookings();
              });
            },
            scrollController: FixedExtentScrollController(
              initialItem: availableStatuses.indexOf(_selectedStatus),
            ),
            children: availableStatuses.map((BookingStatus status) {
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
                _loadBookings();
              });
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9FAFB),
        elevation: 0,
        centerTitle: true,
        title: Text(
          appLocalizations.translate('clientBookings_title'),
          style: GoogleFonts.workSans( // Updated to Work Sans for consistency
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildTabSelector(appLocalizations),
          _buildFilters(appLocalizations),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _bookingsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '${appLocalizations.translate('clientBookings_errorFetching')}: ${snapshot.error}',
                      style: GoogleFonts.workSans(color: Colors.red), // Updated font
                    ),
                  );
                }
                final bookings = snapshot.data ?? [];
                if (bookings.isEmpty) {
                  return _buildEmptyState(appLocalizations);
                }
                return RefreshIndicator(
                  onRefresh: () async => _loadBookings(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: bookings.length,
                    itemBuilder: (context, index) {
                      final booking = bookings[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _BookingHistoryCard(booking: booking, appLocalizations: appLocalizations),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(AppLocalizations appLocalizations) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.grey.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _CustomTabButton(
              label: appLocalizations.translate('clientBookings_upcoming'),
              isSelected: _selectedTab == ClientBookingTab.upcoming,
              onTap: () => _onTabSelected(ClientBookingTab.upcoming),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _CustomTabButton(
              label: appLocalizations.translate('clientBookings_past'),
              isSelected: _selectedTab == ClientBookingTab.past,
              onTap: () => _onTabSelected(ClientBookingTab.past),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(AppLocalizations appLocalizations) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Row(
        children: [
          _buildFilterChip(
            label: _statusToString(_selectedStatus),
            onTap: _showStatusPicker,
          ),
          const SizedBox(width: 24),
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
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.workSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            color: Colors.grey.shade700,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations appLocalizations) {
    IconData icon;
    String title;
    String subtitle;

    if (_selectedTab == ClientBookingTab.upcoming) {
      icon = Icons.event_available_outlined;
      title = appLocalizations.translate('clientBookings_noUpcoming');
      subtitle = appLocalizations.translate('clientBookings_noUpcomingDesc');
    } else {
      icon = Icons.history_outlined;
      title = appLocalizations.translate('clientBookings_noPast');
      subtitle = appLocalizations.translate('clientBookings_noPastDesc');
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 48, color: const Color(0xFF10B981)),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: GoogleFonts.workSans(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.openSans(
                fontSize: 14,
                color: const Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomTabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CustomTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: const Color(0xFF10B981).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.workSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF6B7280),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingHistoryCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final AppLocalizations appLocalizations;
  const _BookingHistoryCard({required this.booking, required this.appLocalizations});

  Map<String, dynamic> _getConfirmationStatus() {
    final buddyConfirmed = booking['buddy_confirmed'] as bool? ?? false;
    final clientConfirmed = booking['client_confirmed'] as bool? ?? false;
    final bothConfirmed = booking['both_confirmed'] as bool? ?? false;
    final confirmationRequested = booking['confirmation_requested_at'] != null;
    final status = booking['status'] as String? ?? 'unknown';

    if (status == 'accepted' && confirmationRequested) {
      if (bothConfirmed) {
        return {
          'showConfirmation': false,
          'message': 'Both Confirmed - Starting Soon!',
          'color': Colors.green.shade600,
          'backgroundColor': Colors.green.shade50,
          'icon': Icons.check_circle,
        };
      } else if (buddyConfirmed && !clientConfirmed) {
        return {
          'showConfirmation': true,
          'message': 'Buddy Ready - Your Confirmation Needed',
          'color': Colors.blue.shade600,
          'backgroundColor': Colors.blue.shade50,
          'icon': Icons.touch_app,
        };
      } else if (!buddyConfirmed && clientConfirmed) {
        return {
          'showConfirmation': false,
          'message': 'You Confirmed - Waiting for Buddy',
          'color': Colors.orange.shade600,
          'backgroundColor': Colors.orange.shade50,
          'icon': Icons.hourglass_empty,
        };
      } else if (!buddyConfirmed && !clientConfirmed) {
        return {
          'showConfirmation': true,
          'message': 'Confirmation Requested',
          'color': Colors.purple.shade600,
          'backgroundColor': Colors.purple.shade50,
          'icon': Icons.notifications_active,
        };
      }
    }

    return {'showConfirmation': false};
  }

  @override
  Widget build(BuildContext context) {
    final buddy = booking['buddies'] as Map<String, dynamic>? ?? {};
    final buddyName = buddy['name'] ?? appLocalizations.translate('clientBookings_defaultBuddy');
    final buddyAvatar = buddy['profile_picture'] as String?;
    final service = booking['service'] ?? appLocalizations.translate('clientBookings_defaultService');
    final date = booking['date'] != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['date'])) : appLocalizations.translate('clientBookings_defaultDate');
    final time = booking['time'] ?? '00:00';
    final amount = booking['amount']?.toString() ?? '0';
    final status = booking['status'] as String? ?? 'unknown';

    final confirmationStatus = _getConfirmationStatus();
    final showConfirmation = confirmationStatus['showConfirmation'] as bool? ?? false;

    return GestureDetector(
      onTap: () {
        if (status == 'in_progress') {
          Navigator.pushNamed(context, '/trip');
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BookingDetailsScreen(bookingId: booking['id']),
            ),
          );
        }
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
          gradient: status == 'in_progress' ? LinearGradient(
            colors: [
              const Color(0xFF10B981).withOpacity(0.02),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ) : null,
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
                  color: _getStatusInfo(status)['iconColor'],
                ),
              ),
              if (status == 'in_progress')
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.6),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getStatusInfo(status)['bgColor'],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _getStatusInfo(status)['icon'],
                            color: _getStatusInfo(status)['iconColor'],
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
                                '$buddyName • $date',
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
                                color: _getStatusInfo(status)['bgColor'],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _getStatusInfo(status)['text'],
                                style: GoogleFonts.workSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _getStatusInfo(status)['textColor'],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$$amount',
                              style: GoogleFonts.workSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (showConfirmation) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: confirmationStatus['backgroundColor'] as Color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (confirmationStatus['color'] as Color).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              confirmationStatus['icon'] as IconData,
                              color: confirmationStatus['color'] as Color,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                confirmationStatus['message'] as String,
                                style: GoogleFonts.workSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: confirmationStatus['color'] as Color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () {
                                // Call the function from the parent widget
                                final parent = context.findAncestorStateOfType<_ClientBookingsScreenState>();
                                if (parent != null) {
                                  parent._confirmTripStart(booking['id']);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF10B981),
                                      const Color(0xFF059669),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  'Confirm',
                                  style: GoogleFonts.workSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
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
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
        return {
          'icon': Icons.hourglass_empty_rounded,
          'text': 'Pending',
          'bgColor': Colors.orange.shade100,
          'iconColor': Colors.orange.shade800,
          'textColor': Colors.orange.shade800,
        };
      case 'accepted':
        return {
          'icon': Icons.check,
          'text': 'Confirmed',
          'bgColor': Colors.green.shade100,
          'iconColor': Colors.green.shade800,
          'textColor': Colors.green.shade800,
        };
      case 'in_progress':
        return {
          'icon': Icons.directions_run,
          'text': 'Active Trip',
          'bgColor': const Color(0xFF10B981).withOpacity(0.1),
          'iconColor': const Color(0xFF10B981),
          'textColor': const Color(0xFF10B981),
        };
      case 'completed':
        return {
          'icon': Icons.check_circle,
          'text': 'Completed',
          'bgColor': Colors.blue.shade100,
          'iconColor': Colors.blue.shade800,
          'textColor': Colors.blue.shade800,
        };
      case 'cancelled':
      case 'declined':
        return {
          'icon': Icons.close,
          'text': 'Declined',
          'bgColor': Colors.red.shade100,
          'iconColor': Colors.red.shade800,
          'textColor': Colors.red.shade800,
        };
      case 'expired':
        return {
          'icon': Icons.access_time_outlined,
          'text': 'Expired',
          'bgColor': Colors.amber.shade100,
          'iconColor': Colors.amber.shade800,
          'textColor': Colors.amber.shade800,
        };
      default:
        return {
          'icon': Icons.help_outline_rounded,
          'text': 'Unknown',
          'bgColor': Colors.grey.shade100,
          'iconColor': Colors.grey.shade700,
          'textColor': Colors.grey.shade700,
        };
    }
  }
}
