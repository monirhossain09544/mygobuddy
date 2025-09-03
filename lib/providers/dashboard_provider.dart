import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mygobuddy/models/dashboard_data.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'dart:async';

enum DashboardState { initial, loading, success, error }

class DashboardProvider with ChangeNotifier {
  BuddyDashboardData? _dashboardData;
  BuddyDashboardData? get dashboardData => _dashboardData;

  DashboardState _state = DashboardState.initial;
  DashboardState get state => _state;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  StreamSubscription<List<Map<String, dynamic>>>? _bookingSubscription;

  @override
  void dispose() {
    _bookingSubscription?.cancel();
    super.dispose();
  }

  Future<void> fetchDashboardData({bool force = false}) async {
    if (_state == DashboardState.loading && !force) return;

    _state = DashboardState.loading;
    notifyListeners();

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw 'User not logged in.';
      }

      if (_bookingSubscription == null) {
        _setupRealTimeSync(userId);
      }

      // Consolidate database calls for efficiency
      final List<Future<dynamic>> futures = [
        supabase.rpc('get_buddy_dashboard_data'),
        // Fetch bookings needed for UI cards (today's bookings, pending requests)
        supabase
            .from('bookings')
            .select('*, client:client_id(*)')
            .eq('buddy_id', userId)
            .inFilter('status', ['confirmed', 'in_progress', 'accepted', 'pending']) // Only fetch relevant statuses
            .order('date', ascending: true)
            .order('time', ascending: true),
      ];

      final responses = await Future.wait(futures);

      // Cast the results
      final rpcResponse = responses[0] as Map<String, dynamic>;
      final bookingsResponse = responses[1] as List<dynamic>;

      // Parse data from the main RPC function
      final weeklyEarningsList = (rpcResponse['weeklyEarnings'] as List<dynamic>?)
          ?.map((e) => WeeklyEarning.fromJson(e as Map<String, dynamic>))
          .toList() ?? [];
      final payoutMethodData = rpcResponse['payoutMethod'] as Map<String, dynamic>?;
      final isAvailable = rpcResponse['isAvailable'] as bool? ?? true;

      // New: Parse recent payouts
      final recentPayoutsList = (rpcResponse['recentPayouts'] as List<dynamic>?)
          ?.map((p) => Payout.fromJson(p as Map<String, dynamic>))
          .toList() ?? [];

      // Filter bookings from the second query for UI display
      final allBookingsForUI = bookingsResponse.map((b) => b as Map<String, dynamic>).toList();
      final today = DateUtils.dateOnly(DateTime.now());
      final now = DateTime.now(); // Add current time for expiration checks

      final todaysBookings = allBookingsForUI.where((b) {
        final bookingDate = DateUtils.dateOnly(DateTime.parse(b['date']));
        return bookingDate.isAtSameMomentAs(today) && (b['status'] != 'pending');
      }).toList();

      final pendingRequests = allBookingsForUI.where((b) {
        if (b['status'] == 'pending') {
          final expiresAtStr = b['expires_at'] as String?;
          if (expiresAtStr != null) {
            final expiresAt = DateTime.parse(expiresAtStr);
            // Only include non-expired pending bookings
            return now.isBefore(expiresAt);
          }
        }
        return b['status'] == 'pending';
      }).toList();

      _dashboardData = BuddyDashboardData(
        // Data from RPC
        isAvailable: isAvailable,
        availableBalance: (rpcResponse['availableBalance'] as num?)?.toDouble() ?? 0.0,
        totalLifetimeEarnings: (rpcResponse['totalLifetimeEarnings'] as num?)?.toDouble() ?? 0.0,
        todaysBookingsCount: (rpcResponse['todaysBookingsCount'] as int?) ?? 0,
        completedBookingsCount: (rpcResponse['completedBookingsCount'] as int?) ?? 0,
        ongoingBookingsCount: (rpcResponse['ongoingBookingsCount'] as int?) ?? 0,
        monthlyEarnings: (rpcResponse['monthlyEarnings'] as num?)?.toDouble() ?? 0.0,
        weeklyEarnings: weeklyEarningsList,
        payoutMethod: payoutMethodData != null ? PayoutMethod.fromJson(payoutMethodData) : null,
        recentPayouts: recentPayoutsList, // Pass the new list here
        // Data from the separate bookings query for UI cards
        todaysBookings: todaysBookings,
        pendingRequests: pendingRequests,
      );

      _state = DashboardState.success;
    } catch (e) {
      _errorMessage = 'Failed to load dashboard data: $e';
      _state = DashboardState.error;
      debugPrint(_errorMessage);
    } finally {
      notifyListeners();
    }
  }

  void _setupRealTimeSync(String userId) {
    _bookingSubscription = supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .listen((bookings) {
      // Filter bookings for current buddy
      final buddyBookings = bookings.where((booking) =>
      booking['buddy_id'] == userId
      ).toList();

      // Check for confirmation status changes
      _handleConfirmationUpdates(buddyBookings);

      // Update dashboard data with latest booking information
      if (_dashboardData != null) {
        _updateDashboardWithLatestBookings(buddyBookings);
      }
    });
  }

  void _handleConfirmationUpdates(List<Map<String, dynamic>> bookings) {
    for (final booking in bookings) {
      final confirmationRequested = booking['confirmation_requested_at'] != null;
      final buddyConfirmed = booking['buddy_confirmed'] as bool? ?? false;
      final clientConfirmed = booking['client_confirmed'] as bool? ?? false;
      final bothConfirmed = booking['both_confirmed'] as bool? ?? false;
      final status = booking['status'] as String? ?? '';

      // Check if this is a new confirmation request or status change
      if (confirmationRequested && !buddyConfirmed && !clientConfirmed) {
        // New confirmation request - buddy should see this
        debugPrint('[Dashboard] New confirmation request detected for booking ${booking['id']}');
      } else if (confirmationRequested && clientConfirmed && !buddyConfirmed) {
        // Client confirmed, buddy needs to confirm
        debugPrint('[Dashboard] Client confirmed, buddy needs to confirm for booking ${booking['id']}');
      } else if (bothConfirmed && status == 'in_progress') {
        // Trip started after both confirmations
        debugPrint('[Dashboard] Trip started after dual confirmation for booking ${booking['id']}');
      }
    }
  }

  void _updateDashboardWithLatestBookings(List<Map<String, dynamic>> latestBookings) {
    if (_dashboardData == null) return;

    final today = DateUtils.dateOnly(DateTime.now());
    final now = DateTime.now();

    // Filter and update today's bookings
    final todaysBookings = latestBookings.where((b) {
      final bookingDate = DateUtils.dateOnly(DateTime.parse(b['date']));
      return bookingDate.isAtSameMomentAs(today) && (b['status'] != 'pending');
    }).toList();

    // Filter and update pending requests
    final pendingRequests = latestBookings.where((b) {
      if (b['status'] == 'pending') {
        final expiresAtStr = b['expires_at'] as String?;
        if (expiresAtStr != null) {
          final expiresAt = DateTime.parse(expiresAtStr);
          return now.isBefore(expiresAt);
        }
      }
      return b['status'] == 'pending';
    }).toList();

    // Update dashboard data with latest booking information
    _dashboardData = _dashboardData!.copyWith(
      todaysBookings: todaysBookings,
      pendingRequests: pendingRequests,
    );

    notifyListeners();
  }

  Future<void> updateAvailability(bool newStatus) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || _dashboardData == null) return;

    final originalData = _dashboardData!;
    _dashboardData = originalData.copyWith(isAvailable: newStatus);
    notifyListeners();

    try {
      debugPrint('[v0] AVAILABILITY UPDATE: Starting update to $newStatus for user $userId');
      debugPrint('[v0] AVAILABILITY UPDATE: Original status was ${originalData.isAvailable}');

      final result = await supabase.rpc('sync_buddy_availability', params: {'new_status': newStatus});
      debugPrint('[v0] AVAILABILITY UPDATE: Sync result: $result');

      final service = FlutterBackgroundService();
      var isRunning = await service.isRunning();
      if (newStatus) {
        if (!isRunning) {
          await service.startService();
        }
        service.invoke('startTask', {'task': 'startKeepAlive'});
        debugPrint('[v0] AVAILABILITY UPDATE: Started background service');
      } else {
        if (isRunning) {
          service.invoke('stop');
        }
        debugPrint('[v0] AVAILABILITY UPDATE: Stopped background service');
      }

      debugPrint('[v0] AVAILABILITY UPDATE: Successfully completed update to $newStatus');
    } catch (e) {
      debugPrint('[v0] AVAILABILITY UPDATE: Error occurred: $e');
      _dashboardData = originalData.copyWith(isAvailable: !newStatus);
      notifyListeners();
    }
  }

  Future<String?> requestPayout(double amount) async {
    if (amount <= 0) {
      return "Please enter a valid amount.";
    }

    try {
      // Call the new secure SQL function
      final result = await supabase.rpc(
        'request_buddy_payout',
        params: {'payout_amount': amount},
      ) as String;

      if (result == 'success') {
        // Refresh data to show updated balance
        await fetchDashboardData(force: true);
        return null; // Indicates success
      } else {
        // The function returned a specific error message
        return result;
      }
    } catch (e) {
      debugPrint('Error requesting payout: $e');
      return 'An error occurred. Please try again.';
    }
  }
}
