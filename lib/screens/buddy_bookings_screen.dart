import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/providers/trip_provider.dart';
import 'package:mygobuddy/screens/buddy_trip_screen.dart';
import 'package:mygobuddy/screens/chat_screen.dart';
import 'package:mygobuddy/screens/pending_booking_details_screen.dart';
import 'package:mygobuddy/screens/bookings_history_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';

enum BuddyTab { newRequests, upcoming }

class BuddyBookingsScreen extends StatefulWidget {
  const BuddyBookingsScreen({super.key});
  @override
  State<BuddyBookingsScreen> createState() => _BuddyBookingsScreenState();
}

class _BuddyBookingsScreenState extends State<BuddyBookingsScreen> {
  BuddyTab _selectedTab = BuddyTab.newRequests;
  final String? _currentUserId = supabase.auth.currentUser?.id;
  late Future<List<Map<String, dynamic>>> _bookingsFuture;

  // For service translations
  Map<String, String> _serviceTranslationMap = {};
  bool _areServicesTranslated = false;

  @override
  void initState() {
    super.initState();
    _loadBookings();
    // We need localizations to be ready before we can load service translations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadServiceTranslations();
      }
    });
  }

  Future<void> _loadServiceTranslations() async {
    if (!mounted) return;
    final localizations = AppLocalizations.of(context);
    try {
      final response = await supabase.from('services').select('name, name_key');
      final Map<String, String> translationMap = {};
      for (var service in response) {
        final serviceName = service['name'] as String;
        final nameKey = service['name_key'] as String?;
        if (nameKey != null) {
          translationMap[serviceName] =
              localizations.translate(nameKey, fallback: serviceName);
        } else {
          translationMap[serviceName] = serviceName;
        }
      }
      if (mounted) {
        setState(() {
          _serviceTranslationMap = translationMap;
          _areServicesTranslated = true;
        });
      }
    } catch (e) {
      // Handle error if needed, but for now, we can just fall back to English names
      if (mounted) {
        setState(() {
          _areServicesTranslated =
          true; // Allow UI to build even if translations fail
        });
      }
    }
  }

  void _loadBookings() {
    setState(() {
      if (_selectedTab == BuddyTab.newRequests) {
        _bookingsFuture = _fetchBookings(['pending']);
      } else if (_selectedTab == BuddyTab.upcoming) {
        _bookingsFuture = _fetchBookings(['accepted', 'in_progress']);
      }
    });
  }

  void _onTabSelected(BuddyTab tab) {
    if (_selectedTab != tab) {
      setState(() {
        _selectedTab = tab;
        _loadBookings();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBookings(
      List<String> statuses) async {
    if (_currentUserId == null) return [];
    try {
      final orFilter = statuses.map((s) => 'status.eq.$s').join(',');
      final response = await supabase
          .from('bookings')
          .select('*, client:client_id(id, name, profile_picture, location)')
          .eq('buddy_id', _currentUserId!)
          .or(orFilter)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> bookings = List<Map<String, dynamic>>.from(response);
      final now = DateTime.now();

      // Filter expired bookings only for pending requests
      if (_selectedTab == BuddyTab.newRequests) {
        bookings = bookings.where((booking) {
          if (booking['status'] == 'pending') {
            final expiresAtStr = booking['expires_at'] as String?;
            if (expiresAtStr != null) {
              final expiresAt = DateTime.parse(expiresAtStr);
              return now.isBefore(expiresAt);
            }
          }
          return true;
        }).toList();
      }

      return bookings;
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        context.showSnackBar(
          localizations
              .translate('buddy_bookings_error_fetch', args: {'error': e.toString()}),
          isError: true,
        );
      }
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9FAFB),
        elevation: 0,
        centerTitle: true,
        title: Text(
          localizations.translate('buddy_bookings_title'),
          style: GoogleFonts.workSans( // Updated to Work Sans for consistency
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
          ),
        ),
        actions: [
          Container( // Added modern container styling for history button
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
                Icons.history,
                color: Color(0xFF111827),
                size: 20,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BookingsHistoryScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabSelector(localizations),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _bookingsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: GoogleFonts.workSans(color: Colors.red), // Updated font
                    ),
                  );
                }

                final bookings = snapshot.data ?? [];

                if (bookings.isEmpty) {
                  return _buildEmptyState(localizations);
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: bookings.length,
                  itemBuilder: (context, index) {
                    final booking = bookings[index];
                    return Padding( // Added spacing between cards
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildBookingCard(booking, localizations),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(AppLocalizations localizations) {
    return Container( // Enhanced tab selector with gradient background
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
              label: localizations.translate('buddy_bookings_tab_new_requests'),
              isSelected: _selectedTab == BuddyTab.newRequests,
              onTap: () => _onTabSelected(BuddyTab.newRequests),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _CustomTabButton(
              label: localizations.translate('buddy_bookings_tab_upcoming'),
              isSelected: _selectedTab == BuddyTab.upcoming,
              onTap: () => _onTabSelected(BuddyTab.upcoming),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations localizations) {
    IconData icon;
    String title;
    String subtitle;

    switch (_selectedTab) {
      case BuddyTab.newRequests:
        icon = Icons.notifications_active_outlined;
        title = localizations.translate('buddy_bookings_empty_new_requests_title');
        subtitle = localizations.translate('buddy_bookings_empty_new_requests_subtitle');
        break;
      case BuddyTab.upcoming:
        icon = Icons.calendar_today_outlined;
        title = localizations.translate('buddy_bookings_empty_upcoming_title');
        subtitle = localizations.translate('buddy_bookings_empty_upcoming_subtitle');
        break;
    }

    return Center(
      child: Container( // Enhanced empty state with modern card design
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
                color: const Color(0xFF19638D).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 48, color: const Color(0xFF19638D)),
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

  Widget _buildBookingCard(Map<String, dynamic> booking, AppLocalizations localizations) {
    final client = booking['client'] as Map<String, dynamic>? ?? {};
    final clientName = client['name'] ?? 'Unknown Client';
    final clientAvatar = client['profile_picture'] as String?;
    final serviceName = booking['service'] as String? ?? '';
    final translatedService = _serviceTranslationMap[serviceName] ?? serviceName;
    final status = booking['status'] as String? ?? '';
    final date = booking['date'] != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['date'])) : 'Unknown Date';

    if (_selectedTab == BuddyTab.newRequests) {
      return _NewRequestCard(
        booking: booking,
        onStateChanged: _loadBookings,
        serviceTranslationMap: _serviceTranslationMap,
      );
    } else if (_selectedTab == BuddyTab.upcoming) {
      return _UpcomingBookingCard(
        booking: booking,
        onStateChanged: _loadBookings,
        serviceTranslationMap: _serviceTranslationMap,
      );
    } else {
      return Container(); // Placeholder for history tab, should not reach here
    }
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
          gradient: isSelected // Enhanced with gradient backgrounds
              ? const LinearGradient(
            colors: [Color(0xFF19638D), Color(0xFF19638D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: const Color(0xFF19638D).withOpacity(0.3),
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
                style: GoogleFonts.workSans( // Updated font
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

class _NewRequestCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onStateChanged;
  final Map<String, String> serviceTranslationMap;

  const _NewRequestCard({
    required this.booking,
    required this.onStateChanged,
    required this.serviceTranslationMap,
  });

  Future<void> _startChat(BuildContext context, String otherUserId,
      String otherUserName, String? otherUserAvatar) async {
    final localizations = AppLocalizations.of(context);
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      context.showSnackBar(
          localizations.translate('buddy_bookings_error_not_logged_in'),
          isError: true);
      return;
    }
    try {
      final data = await supabase.rpc('get_or_create_conversation', params: {
        'p_other_participant_id': otherUserId,
      });
      final conversationId = data as String;
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
              otherUserAvatar: otherUserAvatar,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar(
          localizations.translate('buddy_bookings_error_start_chat',
              args: {'error': e.toString()}),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final client = booking['client'] as Map<String, dynamic>? ?? {};
    final clientName = client['name'] ??
        localizations.translate('buddy_bookings_unknown_client');
    final clientAvatar = client['profile_picture'] as String?;
    final clientId = client['id'] as String?;
    final serviceName = booking['service'] as String? ?? '';
    final translatedService = serviceTranslationMap[serviceName] ?? serviceName;
    final date = booking['date'] != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['date'])) : 'Unknown Date';
    final time = booking['time'] ?? '00:00';
    final amount = booking['amount']?.toString() ?? '0';

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  PendingBookingDetailsScreen(booking: booking)),
        );
        if (result == true) {
          onStateChanged();
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
                  color: Colors.orange.shade800,
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
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.hourglass_empty_rounded,
                        color: Colors.orange.shade800,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            translatedService.isNotEmpty
                                ? translatedService
                                : localizations.translate('buddy_bookings_service_not_specified'),
                            style: GoogleFonts.workSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$clientName • $date',
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
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Pending',
                            style: GoogleFonts.workSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$$amount',
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
}

class _UpcomingBookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onStateChanged;
  final Map<String, String> serviceTranslationMap;

  const _UpcomingBookingCard({
    required this.booking,
    required this.onStateChanged,
    required this.serviceTranslationMap,
  });

  bool _isTripStartable() {
    try {
      final dateStr = booking['date'] as String;
      final timeStr = booking['time'] as String;
      final bookingDateTime = DateTime.parse('$dateStr $timeStr');
      final now = DateTime.now();
      final timeDifference = bookingDateTime.difference(now);
      return timeDifference.inMinutes <= 30 && !timeDifference.isNegative;
    } catch (e) {
      return false;
    }
  }

  Future<void> _startTrip(BuildContext context, String bookingId) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations
            .translate('buddy_bookings_start_trip_dialog_title')),
        content: Text(localizations
            .translate('buddy_bookings_start_trip_dialog_content')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                  localizations.translate('buddy_bookings_dialog_cancel'))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                  localizations.translate('buddy_bookings_dialog_confirm'))),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      Provider.of<TripProvider>(context, listen: false).startTrip(bookingId);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => BuddyTripScreen(bookingId: bookingId),
      ));
      if (context.mounted) {
        onStateChanged();
      }
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar(
          localizations.translate('buddy_bookings_error_start_trip',
              args: {'error': e.toString()}),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final client = booking['client'] as Map<String, dynamic>? ?? {};
    final clientName = client['name'] ??
        localizations.translate('buddy_bookings_unknown_client');
    final clientAvatar = client['profile_picture'] as String?;
    final bookingId = booking['id'] as String;
    final status = booking['status'] as String? ?? '';
    final serviceName = booking['service'] as String? ?? '';
    final translatedService = serviceTranslationMap[serviceName] ?? serviceName;

    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final isTripActive =
        tripProvider.isTripActive(bookingId) || status == 'in_progress';
    final canStartTrip = _isTripStartable();

    return Container( // Enhanced upcoming booking card with modern design
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.grey.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isTripActive
                      ? [Colors.blue.shade400, Colors.blue.shade600]
                      : [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container( // Enhanced avatar with shadow
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: (clientAvatar != null && clientAvatar.isNotEmpty)
                          ? Image.network(
                        clientAvatar,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Container(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              child: const Icon(Icons.person_outline,
                                  size: 28, color: Color(0xFF3B82F6)),
                            ),
                      )
                          : Container(
                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                        child: const Icon(Icons.person_outline,
                            color: Color(0xFF3B82F6), size: 28),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientName,
                        style: GoogleFonts.workSans( // Updated typography
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row( // Enhanced service and date display
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              translatedService.isNotEmpty
                                  ? translatedService
                                  : localizations.translate('buddy_bookings_unknown_service'),
                              style: GoogleFonts.openSans(
                                fontSize: 12,
                                color: const Color(0xFF3B82F6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM dd, HH:mm').format(DateTime.parse(booking['date'] + ' ' + booking['time'])),
                            style: GoogleFonts.openSans(
                              fontSize: 13,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container( // Enhanced action button with modern styling
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (isTripActive ? Colors.blue : const Color(0xFF3B82F6)).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    icon: Icon(
                        isTripActive
                            ? Icons.visibility_outlined
                            : Icons.play_arrow_rounded,
                        size: 18),
                    onPressed: (isTripActive || canStartTrip)
                        ? () {
                      if (isTripActive) {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) =>
                              BuddyTripScreen(bookingId: bookingId),
                        ));
                      } else {
                        _startTrip(context, bookingId);
                      }
                    }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isTripActive
                          ? Colors.blue.shade600
                          : const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    label: Text(
                      isTripActive
                          ? localizations.translate('buddy_bookings_view_trip_button')
                          : localizations.translate('buddy_bookings_start_trip_button'),
                      style: GoogleFonts.workSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
