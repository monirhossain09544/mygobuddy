// lib/models/dashboard_data.dart

// New class to model a single payout transaction
class Payout {
  final String id;
  final double amount;
  final String status;
  final DateTime requestedAt;

  Payout({
    required this.id,
    required this.amount,
    required this.status,
    required this.requestedAt,
  });

  factory Payout.fromJson(Map<String, dynamic> json) {
    return Payout(
      id: json['id'],
      amount: (json['amount'] as num).toDouble(),
      status: json['status'],
      requestedAt: DateTime.parse(json['requested_at']),
    );
  }
}


class PayoutMethod {
  final String id;
  final String type;
  final String? paypalAccountEmail;
  final bool? paypalVerified;

  PayoutMethod({
    required this.id,
    required this.type,
    this.paypalAccountEmail,
    this.paypalVerified,
  });

  factory PayoutMethod.fromJson(Map<String, dynamic> json) {
    return PayoutMethod(
      id: json['id'],
      type: json['type'],
      paypalAccountEmail: json['paypal_account_email'],
      paypalVerified: json['paypal_verified'] ?? false,
    );
  }

  bool get isPayPal => type == 'paypal';

  String get displayName => 'PayPal Account';

  String get displayDetails => paypalAccountEmail ?? '';

  String get statusText => paypalVerified == true ? 'Verified' : 'Unverified';
}

class WeeklyEarning {
  final String day;
  final double earning;

  WeeklyEarning({required this.day, required this.earning});

  factory WeeklyEarning.fromJson(Map<String, dynamic> json) {
    return WeeklyEarning(
      day: json['day']?.trim() ?? 'N/A',
      earning: (json['earning'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// This is the main data class, now unified to hold all necessary data.
class BuddyDashboardData {
  // Data for the main home screen UI
  final bool isAvailable;
  final List<Map<String, dynamic>> todaysBookings;
  final List<Map<String, dynamic>> pendingRequests;

  // Stat metrics
  final int todaysBookingsCount;
  final int completedBookingsCount;
  final int ongoingBookingsCount;
  final double monthlyEarnings;

  // Data for the detailed dashboard/payout screen
  final double availableBalance;
  final double totalLifetimeEarnings;
  final List<WeeklyEarning> weeklyEarnings;
  final PayoutMethod? payoutMethod;
  final List<Payout> recentPayouts; // New field for recent payouts

  BuddyDashboardData({
    required this.isAvailable,
    required this.todaysBookings,
    required this.pendingRequests,
    required this.todaysBookingsCount,
    required this.completedBookingsCount,
    required this.ongoingBookingsCount,
    required this.monthlyEarnings,
    required this.availableBalance,
    required this.totalLifetimeEarnings,
    required this.weeklyEarnings,
    this.payoutMethod,
    required this.recentPayouts, // Updated constructor
  });

  // The copyWith method is required for optimistic UI updates, fixing one of the errors.
  BuddyDashboardData copyWith({
    bool? isAvailable,
    List<Map<String, dynamic>>? todaysBookings,
    List<Map<String, dynamic>>? pendingRequests,
    int? todaysBookingsCount,
    int? completedBookingsCount,
    int? ongoingBookingsCount,
    double? monthlyEarnings,
    double? availableBalance,
    double? totalLifetimeEarnings,
    List<WeeklyEarning>? weeklyEarnings,
    PayoutMethod? payoutMethod,
    List<Payout>? recentPayouts, // Updated copyWith
  }) {
    return BuddyDashboardData(
      isAvailable: isAvailable ?? this.isAvailable,
      todaysBookings: todaysBookings ?? this.todaysBookings,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      todaysBookingsCount: todaysBookingsCount ?? this.todaysBookingsCount,
      completedBookingsCount: completedBookingsCount ?? this.completedBookingsCount,
      ongoingBookingsCount: ongoingBookingsCount ?? this.ongoingBookingsCount,
      monthlyEarnings: monthlyEarnings ?? this.monthlyEarnings,
      availableBalance: availableBalance ?? this.availableBalance,
      totalLifetimeEarnings: totalLifetimeEarnings ?? this.totalLifetimeEarnings,
      weeklyEarnings: weeklyEarnings ?? this.weeklyEarnings,
      payoutMethod: payoutMethod ?? this.payoutMethod,
      recentPayouts: recentPayouts ?? this.recentPayouts, // Updated copyWith
    );
  }
}
