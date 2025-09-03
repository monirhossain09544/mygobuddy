import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/models/dashboard_data.dart';
import 'package:mygobuddy/providers/dashboard_provider.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/providers/trip_provider.dart';
import 'package:mygobuddy/screens/buddy_bookings_screen.dart';
import 'package:mygobuddy/screens/buddy_profile_screen.dart';
import 'package:mygobuddy/screens/buddy_trip_screen.dart';
import 'package:mygobuddy/screens/pending_booking_details_screen.dart';
import 'package:mygobuddy/screens/notifications_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

// Helper function for detail rows in cards
Widget _buildDetailRow(IconData icon, String label, String value) {
  return Row(
    children: [
      Icon(icon, color: Colors.grey.shade500, size: 20),
      const SizedBox(width: 12),
      Text(
        '$label:',
        style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827)),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class BuddyHomeScreen extends StatefulWidget {
  const BuddyHomeScreen({super.key});
  @override
  State<BuddyHomeScreen> createState() => _BuddyHomeScreenState();
}

class _BuddyHomeScreenState extends State<BuddyHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    // Fetch profile for the app bar and dashboard data for the body
    await Future.wait([
      Provider.of<ProfileProvider>(context, listen: false).fetchProfile(),
      Provider.of<DashboardProvider>(context, listen: false).fetchDashboardData(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final profileProvider = context.watch<ProfileProvider>();
    final profileData = profileProvider.profileData;
    final String name = profileData?['name'] ?? localizations.buddyHomeUser;
    final String? avatarUrl = profileData?['profile_picture'];
    final String firstName = name.split(' ').first;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: _buildAppBar(context, firstName, avatarUrl),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: Consumer<DashboardProvider>(
          builder: (context, dashboardProvider, child) {
            switch (dashboardProvider.state) {
              case DashboardState.loading:
              case DashboardState.initial:
                return const Center(child: CircularProgressIndicator());
              case DashboardState.error:
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error: ${dashboardProvider.errorMessage}\nPull down to refresh.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              case DashboardState.success:
                final data = dashboardProvider.dashboardData;
                if (data == null) {
                  return const Center(child: Text('No data available. Pull down to refresh.'));
                }
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  children: [
                    const SizedBox(height: 16),
                    _buildAvailabilityCard(context, data.isAvailable),
                    const SizedBox(height: 32),
                    _buildSectionHeader(localizations.buddyHomeQuickSummary),
                    const SizedBox(height: 16),
                    _buildDashboardGrid(data),
                    const SizedBox(height: 32),
                    _buildSectionHeader(localizations.buddyHomeTodaysBookings),
                    const SizedBox(height: 16),
                    _buildTodaysBookingsList(data.todaysBookings, _refreshData),
                    const SizedBox(height: 32),
                    _buildSectionHeader(
                      localizations.buddyHomePendingRequests,
                      onViewAll: data.pendingRequests.isNotEmpty
                          ? () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const BuddyBookingsScreen()));
                      }
                          : null,
                    ),
                    const SizedBox(height: 16),
                    _buildPendingRequestList(data.pendingRequests, _refreshData),
                    const SizedBox(height: 20),
                  ],
                );
            }
          },
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, String firstName, String? avatarUrl) {
    final localizations = AppLocalizations.of(context);
    const primaryColor = Color(0xFF19638D);
    return AppBar(
      toolbarHeight: 80,
      backgroundColor: const Color(0xFFF9FAFB),
      elevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFF9FAFB),
        statusBarIconBrightness: Brightness.dark,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('EEEE, MMMM d').format(DateTime.now()),
            style: GoogleFonts.poppins(color: const Color(0xFF6B7280), fontSize: 15),
          ),
          Text(
            localizations.buddyHomeGreeting(firstName),
            style: GoogleFonts.poppins(color: const Color(0xFF111827), fontSize: 26, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_outlined, color: primaryColor, size: 28),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(right: 20.0, left: 8.0),
          child: GestureDetector(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (context) => const BuddyProfileScreen()));
              if (mounted) {
                _refreshData();
              }
            },
            child: CircleAvatar(
              radius: 24,
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
              child: (avatarUrl == null || avatarUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey) : null,
              backgroundColor: Colors.grey[200],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvailabilityCard(BuildContext context, bool isAvailable) {
    final localizations = AppLocalizations.of(context);
    const primaryColor = Color(0xFF19638D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localizations.buddyHomeYourStatus, style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  isAvailable ? localizations.buddyHomeYouAreOnline : localizations.buddyHomeYouAreOffline,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: isAvailable,
            onChanged: (newStatus) {
              context.read<DashboardProvider>().updateAvailability(newStatus);
            },
            activeColor: Colors.white.withOpacity(0.4),
            trackColor: Colors.black.withOpacity(0.2),
            thumbColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardGrid(BuddyDashboardData data) {
    final localizations = AppLocalizations.of(context);
    final currencyFormat = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final stats = [
      {'icon': Icons.calendar_today_outlined, 'label': localizations.buddyHomeTodaysBookings, 'value': data.todaysBookingsCount.toString(), 'color': const Color(0xFF19638D)},
      {'icon': Icons.check_circle_outline, 'label': localizations.buddyHomeCompleted, 'value': data.completedBookingsCount.toString(), 'color': Colors.green.shade600},
      {'icon': Icons.hourglass_top_outlined, 'label': localizations.buddyHomeOngoing, 'value': data.ongoingBookingsCount.toString(), 'color': Colors.orange.shade700},
      {'icon': Icons.account_balance_wallet_outlined, 'label': localizations.buddyHomeThisMonth, 'value': currencyFormat.format(data.monthlyEarnings), 'color': Colors.blue.shade600},
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.2),
      itemBuilder: (context, index) {
        final stat = stats[index];
        return _StatCard(icon: stat['icon'] as IconData, label: stat['label'] as String, value: stat['value'] as String, color: stat['color'] as Color);
      },
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onViewAll, String? viewAllText}) {
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            child: Text(viewAllText ?? localizations.buddyHomeViewAll, style: GoogleFonts.poppins(color: const Color(0xFFF15808), fontWeight: FontWeight.w600, fontSize: 13)),
          ),
      ],
    );
  }

  Widget _buildTodaysBookingsList(List<Map<String, dynamic>> bookings, VoidCallback onStateChanged) {
    final localizations = AppLocalizations.of(context);
    if (bookings.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: Text(localizations.buddyHomeNoBookingsToday, style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 15)),
      );
    }
    return SizedBox(
      height: 350,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: bookings.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) => _TodaysBookingCard(
          booking: bookings[index],
          onStateChanged: onStateChanged,
        ),
      ),
    );
  }

  Widget _buildPendingRequestList(List<Map<String, dynamic>> requests, VoidCallback onStateChanged) {
    final localizations = AppLocalizations.of(context);
    if (requests.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: Text(localizations.buddyHomeNoPendingRequests, style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 15)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: requests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _PendingRequestCard(
        booking: requests[index],
        onStateChanged: onStateChanged,
      ),
    );
  }
}

class _TodaysBookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onStateChanged;
  const _TodaysBookingCard({
    required this.booking,
    required this.onStateChanged,
  });

  bool _isTripStartable() {
    final status = booking['status'] as String? ?? 'Unknown';

    if (status == 'in_progress') {
      return false; // Already active, not startable
    }

    try {
      final dateStr = booking['date'] as String;
      final timeStr = booking['time'] as String;
      final bookingDateTime = DateTime.parse('$dateStr $timeStr');
      final now = DateTime.now();
      final timeDifference = bookingDateTime.difference(now);

      return timeDifference.inMinutes <= 30 && timeDifference.inMinutes >= -30;
    } catch (e) {
      return false;
    }
  }

  Map<String, dynamic> _getConfirmationStatus() {
    final buddyConfirmed = booking['buddy_confirmed'] as bool? ?? false;
    final clientConfirmed = booking['client_confirmed'] as bool? ?? false;
    final bothConfirmed = booking['both_confirmed'] as bool? ?? false;
    final confirmationRequested = booking['confirmation_requested_at'] != null;

    if (bothConfirmed) {
      return {
        'message': 'Both Confirmed - Trip Starting!',
        'color': Colors.green.shade600,
        'backgroundColor': Colors.green.shade50,
        'icon': Icons.check_circle,
        'canStart': true,
        'showConfirmation': false,
      };
    } else if (confirmationRequested) {
      if (buddyConfirmed && !clientConfirmed) {
        return {
          'message': 'Waiting for Client',
          'color': Colors.orange.shade600,
          'backgroundColor': Colors.orange.shade50,
          'icon': Icons.hourglass_empty,
          'canStart': false,
          'showConfirmation': false,
        };
      } else if (!buddyConfirmed && clientConfirmed) {
        return {
          'message': 'Client Confirmed - Your Turn!',
          'color': Colors.blue.shade600,
          'backgroundColor': Colors.blue.shade50,
          'icon': Icons.touch_app,
          'canStart': false,
          'showConfirmation': true,
        };
      } else if (!buddyConfirmed && !clientConfirmed) {
        return {
          'message': 'Confirmation Requested',
          'color': Colors.purple.shade600,
          'backgroundColor': Colors.purple.shade50,
          'icon': Icons.touch_app,
          'canStart': false,
          'showConfirmation': true,
        };
      }
    }

    return {
      'message': 'Ready to Request Start',
      'color': Colors.green.shade600,
      'backgroundColor': Colors.green.shade50,
      'icon': Icons.play_circle_outline,
      'canStart': false,
      'showConfirmation': false,
    };
  }

  Map<String, dynamic> _getTimeStatus() {
    final status = booking['status'] as String? ?? 'Unknown';

    if (status == 'in_progress') {
      return {
        'message': 'Trip Active',
        'color': Colors.blue.shade600,
        'backgroundColor': Colors.blue.shade50,
        'icon': Icons.directions_run,
        'canStart': false,
        'isActive': true,
      };
    }

    try {
      final dateStr = booking['date'] as String;
      final timeStr = booking['time'] as String;
      final bookingDateTime = DateTime.parse('$dateStr $timeStr');
      final now = DateTime.now();
      final timeDifference = bookingDateTime.difference(now);

      if (timeDifference.inMinutes < -30) {
        return {
          'message': 'Too late to start',
          'color': Colors.red.shade600,
          'backgroundColor': Colors.red.shade50,
          'icon': Icons.schedule_outlined,
          'canStart': false,
          'isActive': false,
        };
      } else if (timeDifference.inMinutes >= -30 && timeDifference.inMinutes <= 30) {
        if (timeDifference.isNegative) {
          final minutesLate = timeDifference.inMinutes.abs();
          return {
            'message': '${minutesLate}m late - Can start!',
            'color': Colors.orange.shade600,
            'backgroundColor': Colors.orange.shade50,
            'icon': Icons.play_circle_outline,
            'canStart': true,
            'isActive': false,
          };
        } else {
          return {
            'message': 'Ready to start!',
            'color': Colors.green.shade600,
            'backgroundColor': Colors.green.shade50,
            'icon': Icons.play_circle_outline,
            'canStart': true,
            'isActive': false,
          };
        }
      } else {
        final hours = timeDifference.inHours;
        final minutes = timeDifference.inMinutes % 60;
        String timeText = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
        return {
          'message': 'Starts in $timeText',
          'color': Colors.orange.shade600,
          'backgroundColor': Colors.orange.shade50,
          'icon': Icons.timer_outlined,
          'canStart': false,
          'isActive': false,
        };
      }
    } catch (e) {
      return {
        'message': 'Time error',
        'color': Colors.grey.shade600,
        'backgroundColor': Colors.grey.shade50,
        'icon': Icons.error_outline,
        'canStart': false,
        'isActive': false,
      };
    }
  }

  Future<void> _requestTripConfirmation(BuildContext context) async {
    try {
      final response = await supabase.rpc('request_trip_confirmation', params: {
        'booking_id': booking['id'],
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Confirmation request sent to client!'),
            backgroundColor: Colors.green,
          ),
        );
        Provider.of<DashboardProvider>(context, listen: false).fetchDashboardData();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error requesting confirmation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmTripStart(BuildContext context) async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final response = await supabase.rpc('confirm_trip_start', params: {
        'booking_id': booking['id'],
        'user_id': currentUserId,
        'user_type': 'buddy',
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip confirmed! Waiting for client confirmation.'),
            backgroundColor: Colors.blue,
          ),
        );
        Provider.of<DashboardProvider>(context, listen: false).fetchDashboardData();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming trip: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripProvider = Provider.of<TripProvider>(context);
    final isTripActive = tripProvider.isTripActive(booking['id']);
    final client = booking['client'] as Map<String, dynamic>? ?? {};
    final clientName = client['name'] as String? ?? 'Unknown Client';
    final clientAvatarUrl = client['profile_picture'] as String?;
    final status = booking['status'] as String? ?? 'Unknown';

    final timeStatus = _getTimeStatus();
    final canStartTrip = timeStatus['canStart'] as bool;
    final isActive = timeStatus['isActive'] as bool;

    final confirmationStatus = _getConfirmationStatus();
    final showConfirmation = confirmationStatus['showConfirmation'] as bool;
    final bothConfirmed = booking['both_confirmed'] as bool? ?? false;

    final isOngoing = status == 'in_progress';

    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
        border: isActive ? Border.all(color: Colors.blue.shade200, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isActive ? Border.all(color: Colors.blue.shade400, width: 2) : null,
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundImage: clientAvatarUrl != null && clientAvatarUrl.isNotEmpty ? NetworkImage(clientAvatarUrl) : null,
                  child: clientAvatarUrl == null || clientAvatarUrl.isEmpty ? const Icon(Icons.person) : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(clientName, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
                    const SizedBox(height: 2),
                    Text(booking['service'] as String? ?? 'Service', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isOngoing ? Colors.blue.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: isActive ? Border.all(color: Colors.blue.shade300, width: 1) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      isOngoing ? 'Ongoing' : 'Upcoming',
                      style: GoogleFonts.poppins(
                        color: isOngoing ? Colors.blue.shade700 : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          _buildDetailRow(Icons.calendar_today_outlined, 'Date', DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['date']))),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.access_time_outlined, color: Colors.grey.shade500, size: 20),
              const SizedBox(width: 12),
              Text(
                'Time:',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 8),
              Text(
                booking['time'] as String? ?? 'N/A',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827)),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: timeStatus['backgroundColor'] as Color,
                  borderRadius: BorderRadius.circular(12),
                  border: isActive ? Border.all(color: timeStatus['color'] as Color, width: 1) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      timeStatus['icon'] as IconData,
                      size: 14,
                      color: timeStatus['color'] as Color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeStatus['message'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: timeStatus['color'] as Color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.location_on_outlined, 'Location', client['location'] as String? ?? 'N/A'),

          if (canStartTrip && !isOngoing && !isActive) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: confirmationStatus['backgroundColor'] as Color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (confirmationStatus['color'] as Color).withOpacity(0.3)),
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
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: confirmationStatus['color'] as Color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: (isOngoing || isTripActive || isActive || bothConfirmed)
                  ? LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
                  : (canStartTrip && showConfirmation)
                  ? LinearGradient(
                colors: [Colors.green.shade500, Colors.green.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
                  : canStartTrip
                  ? LinearGradient(
                colors: [Colors.purple.shade500, Colors.purple.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
                  : null,
              color: !canStartTrip && !isOngoing && !isTripActive && !isActive ? Colors.grey.shade300 : null,
              boxShadow: (canStartTrip || isTripActive || isOngoing || isActive || bothConfirmed) ? [
                BoxShadow(
                  color: ((isOngoing || isTripActive || isActive || bothConfirmed) ? Colors.blue.shade600 :
                  showConfirmation ? Colors.green.shade600 : Colors.purple.shade600).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ] : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (booking['status'] == 'confirmed' || booking['status'] == 'in_progress' || booking['status'] == 'accepted') ? () async {
                  if (isOngoing || isTripActive || isActive || bothConfirmed) {
                    final tripProvider = Provider.of<TripProvider>(context, listen: false);
                    if (booking['status'] == 'confirmed' || booking['status'] == 'accepted') {
                      try {
                        await supabase.from('bookings').update({'status': 'in_progress'}).eq('id', booking['id']);
                        tripProvider.startTrip(booking['id']);
                        onStateChanged();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error starting trip: $e')));
                        }
                        return;
                      }
                    }
                    final tripEnded = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (context) => BuddyTripScreen(bookingId: booking['id'])),
                    );
                    if (tripEnded == true) {
                      onStateChanged();
                    }
                  } else if (canStartTrip && showConfirmation) {
                    await _confirmTripStart(context);
                  } else if (canStartTrip && !showConfirmation) {
                    await _requestTripConfirmation(context);
                  }
                } : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (isOngoing || isTripActive || isActive || bothConfirmed)
                              ? Icons.visibility_rounded
                              : showConfirmation
                              ? Icons.check_circle_outline
                              : canStartTrip
                              ? Icons.touch_app
                              : Icons.schedule_outlined,
                          size: 20,
                          color: (canStartTrip || isTripActive || isOngoing || isActive || bothConfirmed) ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        (isOngoing || isTripActive || isActive || bothConfirmed)
                            ? 'View Active Trip'
                            : showConfirmation
                            ? 'Confirm Start'
                            : canStartTrip
                            ? 'Request Start'
                            : timeStatus['message'] as String,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: (canStartTrip || isTripActive || isOngoing || isActive || bothConfirmed) ? Colors.white : Colors.grey.shade600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isOngoing || isTripActive || isActive || bothConfirmed) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
              Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingRequestCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onStateChanged;
  const _PendingRequestCard({
    required this.booking,
    required this.onStateChanged,
  });
  @override
  Widget build(BuildContext context) {
    final client = booking['client'] as Map<String, dynamic>? ?? {};
    final clientName = client['name'] as String? ?? 'Unknown Client';
    final clientAvatarUrl = client['profile_picture'] as String?;
    return InkWell(
      onTap: () async {
        final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => PendingBookingDetailsScreen(booking: booking)));
        if (result == true && context.mounted) {
          onStateChanged();
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1.0),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundImage: clientAvatarUrl != null && clientAvatarUrl.isNotEmpty ? NetworkImage(clientAvatarUrl) : null,
              child: clientAvatarUrl == null || clientAvatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clientName, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                  const SizedBox(height: 2),
                  Text(
                    '${booking['service'] as String? ?? 'Service'} at ${booking['time'] as String? ?? 'N/A'}',
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
