import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mygobuddy/main.dart';

import 'constants.dart';

class AppLocalizations {
  final Locale locale;
  final Map<String, String> _localizedStrings;

  AppLocalizations(this.locale, this._localizedStrings);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
  _AppLocalizationsDelegate();

  /// Translates the given [key] into the current locale's string.
  ///
  /// You can provide an optional [fallback] string if the key is not found.
  /// You can provide an optional [args] map for string interpolation.
  /// For a key like 'hello_user' with value 'Hello, {name}!', you would call:
  /// `translate('hello_user', args: {'name': 'John'})`
  String translate(String key, {String? fallback, Map<String, String> args = const {}}) {
    // Use the translation, or the fallback, or the key itself.
    String value = _localizedStrings[key] ?? fallback ?? key;
    args.forEach((argKey, argValue) {
      value = value.replaceAll('{$argKey}', argValue);
    });
    return value;
  }

  // --- Specific getters for convenience ---

  String get language => translate('language', fallback: 'Language');
  String get saveChanges => translate('save_changes', fallback: 'Save Changes');
  String get welcomeBack => translate('welcome_back', fallback: 'Welcome Back!');
  String get availableBuddies => translate('available_buddies', fallback: 'Available Buddies');
  String get popularServices => translate('popular_services', fallback: 'Popular Services');
  String get expertsForYou => translate('experts_for_you', fallback: 'Experts For You');
  String get searchForServices => translate('search_for_services', fallback: 'Search for services...');
  String get viewAll => translate('view_all', fallback: 'View All');
  String get noBuddiesFound => translate('no_buddies_found', fallback: 'No buddies found for your country yet.');
  String get findingExperts => translate('finding_experts', fallback: 'Finding Experts...');
  String get searchingForBuddies => translate('searching_for_buddies', fallback: 'We\'re searching for top-rated buddies in your area.');
  String get expertIn => translate('expert_in', fallback: 'EXPERT IN');
  String get reviews => translate('reviews', fallback: 'reviews');
  String get viewProfile => translate('view_profile', fallback: 'View Profile');

  String get dashboardTitle => translate('dashboard_title', fallback: 'My Dashboard');
  String get dashboardAvailableForPayout => translate('dashboard_available_for_payout', fallback: 'Available for Payout');
  String get dashboardTodaysBookings => translate('dashboard_todays_bookings', fallback: 'Today\'s Bookings');
  String get dashboardCompleted => translate('dashboard_completed', fallback: 'Completed');
  String get dashboardOngoing => translate('dashboard_ongoing', fallback: 'Ongoing');
  String get dashboardWeeklyReport => translate('dashboard_weekly_report', fallback: 'Weekly Report');
  String get dashboardRequestPayout => translate('dashboard_request_payout', fallback: 'Request Payout');
  String get dashboardThisMonthsEarnings => translate('dashboard_this_months_earnings', fallback: 'This Month\'s Earnings');
  String get dashboardTotalLifetimeEarnings => translate('dashboard_total_lifetime_earnings', fallback: 'Total Lifetime Earnings');
  String get dashboardIncludesBookingsTips => translate('dashboard_includes_bookings_tips', fallback: 'Includes bookings + tips');
  String get dashboardEarningsSummary => translate('dashboard_earnings_summary', fallback: 'Earnings Summary');
  String get dashboardPayoutMethod => translate('dashboard_payout_method', fallback: 'Payout Method');
  String get dashboardRecentPayouts => translate('dashboard_recent_payouts', fallback: 'Recent Payouts');
  String get dashboardNoRecentPayouts => translate('dashboard_no_recent_payouts', fallback: 'No recent payouts.');
  String get dashboardTipsReceived => translate('dashboard_tips_received', fallback: 'Tips Received');
  String get dashboardNoTipsReceived => translate('dashboard_no_tips_received', fallback: 'No tips received yet');

  String get profileMenuDashboard => translate('profile_menu_dashboard', fallback: 'Dashboard');
  String get profileMenuManageServices => translate('profile_menu_manage_services', fallback: 'Manage Services');

  String get manageServicesTitle => translate('manage_services_title', fallback: 'Manage Services');
  String get manageServicesMyServices => translate('manage_services_my_services', fallback: 'My Services');
  String get manageServicesAvailableServices => translate('manage_services_available_services', fallback: 'Available Services');
  String get manageServicesNoServicesAdded => translate('manage_services_no_services_added', fallback: 'No services added yet');
  String get manageServicesAddServicesToEarn => translate('manage_services_add_services_to_earn', fallback: 'Add services to start earning!');
  String get manageServicesAllServicesAdded => translate('manage_services_all_services_added', fallback: 'All services added');
  String get manageServicesOfferingAllServices => translate('manage_services_offering_all_services', fallback: 'You\'re offering all available services!');
  String get manageServicesServiceEnabled => translate('manage_services_service_enabled', fallback: 'Service enabled');
  String get manageServicesServiceDisabled => translate('manage_services_service_disabled', fallback: 'Service disabled');
  String get manageServicesErrorUpdating => translate('manage_services_error_updating', fallback: 'Error updating service');
  String get manageServicesErrorAdding => translate('manage_services_error_adding', fallback: 'Error adding service');
  String get manageServicesErrorLoading => translate('manage_services_error_loading', fallback: 'Error loading services');
  String get manageServicesRetry => translate('manage_services_retry', fallback: 'Retry');
  String get manageServicesAdd => translate('manage_services_add', fallback: 'Add');

  String get updateDialogTitle => translate('update_dialog_title', fallback: 'Update Available');
  String get updateDialogVersion => translate('update_dialog_version', fallback: 'Version');
  String get updateDialogWhatsNew => translate('update_dialog_whats_new', fallback: 'What\'s New');
  String get updateDialogSkip => translate('update_dialog_skip', fallback: 'Skip');
  String get updateDialogUpdate => translate('update_dialog_update', fallback: 'Update');
  String get updateDialogErrorOpeningStore => translate('update_dialog_error_opening_store', fallback: 'Could not open app store');

  String get cancellationTitle => translate('cancellation_title', fallback: 'Cancel Booking');
  String get cancellationReasonLabel => translate('cancellation_reason_label', fallback: 'Please select a reason for cancellation:');
  String get cancellationCustomReasonHint => translate('cancellation_custom_reason_hint', fallback: 'Please specify your reason...');
  String get cancellationKeepBooking => translate('cancellation_keep_booking', fallback: 'Keep Booking');
  String get cancellationConfirmCancel => translate('cancellation_confirm_cancel', fallback: 'Cancel Booking');

  String get deleteAccountTitle => translate('delete_account_title', fallback: 'Delete Account');
  String get deleteAccountWarningTitle => translate('delete_account_warning_title', fallback: 'Are you sure?');
  String get deleteAccountWarningMessage => translate('delete_account_warning_message', fallback: 'This action cannot be undone. All your data will be permanently deleted.');
  String get deleteAccountConfirmPasswordLabel => translate('delete_account_confirm_password_label', fallback: 'Confirm your password');
  String get deleteAccountConfirmPasswordHint => translate('delete_account_confirm_password_hint', fallback: 'Enter your current password');
  String get deleteAccountButton => translate('delete_account_button', fallback: 'Delete Account');
  String get deleteAccountDialogTitle => translate('delete_account_dialog_title', fallback: 'Delete Account');
  String get deleteAccountDialogContent => translate('delete_account_dialog_content', fallback: 'This will permanently delete your account and all associated data.');
  String get deleteAccountDialogCancel => translate('delete_account_dialog_cancel', fallback: 'Cancel');
  String get deleteAccountDialogConfirm => translate('delete_account_dialog_confirm', fallback: 'Delete');
  String get deleteAccountPasswordRequired => translate('delete_account_password_required', fallback: 'Password is required to delete account');
  String get deleteAccountInvalidPassword => translate('delete_account_invalid_password', fallback: 'Invalid password. Please try again.');
  String get deleteAccountSuccess => translate('delete_account_success', fallback: 'Account deleted successfully');
  String get deleteAccountWarningDataLoss => translate('delete_account_warning_data_loss', fallback: 'The following data will be permanently deleted:');
  String get deleteAccountDataProfile => translate('delete_account_data_profile', fallback: 'Profile information and settings');
  String get deleteAccountDataBookings => translate('delete_account_data_bookings', fallback: 'Booking history and transactions');
  String get deleteAccountDataMessages => translate('delete_account_data_messages', fallback: 'Messages and conversations');
  String get deleteAccountDataTransactions => translate('delete_account_data_transactions', fallback: 'Payment and transaction history');

  String cancellationRefundInfo(String amount) => translate('cancellation_refund_info',
      fallback: 'You will receive a full refund of {amount}', args: {'amount': amount});
  String cancellationSuccessWithRefund(String amount) => translate('cancellation_success_with_refund',
      fallback: 'Booking cancelled successfully! Refund of {amount} is being processed.', args: {'amount': amount});
  String get cancellationSuccess => translate('cancellation_success', fallback: 'Booking cancelled successfully!');
  String cancellationError(String error) => translate('cancellation_error',
      fallback: 'Failed to cancel booking: {error}', args: {'error': error});

  String deleteAccountError(String error) => translate('delete_account_error',
      fallback: 'Failed to delete account: {error}', args: {'error': error});

  String hiUser(String name) => translate('hi_user', fallback: 'Hi {name},', args: {'name': name});

  String buddyHomeGreeting(String name) => translate('buddy_home_greeting',
      fallback: 'Hi, {name}!', args: {'name': name});
  String get buddyHomeYourStatus => translate('buddy_home_your_status', fallback: 'Your Status');
  String get buddyHomeYouAreOnline => translate('buddy_home_you_are_online', fallback: 'You are Online');
  String get buddyHomeYouAreOffline => translate('buddy_home_you_are_offline', fallback: 'You are Offline');
  String get buddyHomeQuickSummary => translate('buddy_home_quick_summary', fallback: 'Quick Summary');
  String get buddyHomeTodaysBookings => translate('buddy_home_todays_bookings', fallback: 'Today\'s Bookings');
  String get buddyHomePendingRequests => translate('buddy_home_pending_requests', fallback: 'Pending Requests');
  String get buddyHomeViewAll => translate('buddy_home_view_all', fallback: 'View All');
  String get buddyHomeCompleted => translate('buddy_home_completed', fallback: 'Completed');
  String get buddyHomeOngoing => translate('buddy_home_ongoing', fallback: 'Ongoing');
  String get buddyHomeThisMonth => translate('buddy_home_this_month', fallback: 'This Month');
  String get buddyHomeNoBookingsToday => translate('buddy_home_no_bookings_today', fallback: 'No bookings for today.');
  String get buddyHomeNoPendingRequests => translate('buddy_home_no_pending_requests', fallback: 'No pending requests.');
  String get buddyHomeDate => translate('buddy_home_date', fallback: 'Date');
  String get buddyHomeTime => translate('buddy_home_time', fallback: 'Time');
  String get buddyHomeLocation => translate('buddy_home_location', fallback: 'Location');
  String get buddyHomeService => translate('buddy_home_service', fallback: 'Service');
  String get buddyHomeUnknownClient => translate('buddy_home_unknown_client', fallback: 'Unknown Client');
  String get buddyHomeUser => translate('buddy_home_user', fallback: 'User');
  String get buddyHomeNA => translate('buddy_home_na', fallback: 'N/A');
  String get buddyHomeUpcoming => translate('buddy_home_upcoming', fallback: 'Upcoming');
  String get buddyHomeOngoingStatus => translate('buddy_home_ongoing_status', fallback: 'Ongoing');
  String get buddyHomeTripActive => translate('buddy_home_trip_active', fallback: 'Trip Active');
  String get buddyHomeReadyToStart => translate('buddy_home_ready_to_start', fallback: 'Ready to start!');
  String get buddyHomeTooLateToStart => translate('buddy_home_too_late_to_start', fallback: 'Too late to start');
  String get buddyHomeTimeError => translate('buddy_home_time_error', fallback: 'Time error');
  String buddyHomeStartsIn(String time) => translate('buddy_home_starts_in',
      fallback: 'Starts in {time}', args: {'time': time});
  String buddyHomeLateCanStart(String minutes) => translate('buddy_home_late_can_start',
      fallback: '{minutes}m late - Can start!', args: {'minutes': minutes});
  String get buddyHomeBothConfirmed => translate('buddy_home_both_confirmed', fallback: 'Both Confirmed - Trip Starting!');
  String get buddyHomeWaitingForClient => translate('buddy_home_waiting_for_client', fallback: 'Waiting for Client');
  String get buddyHomeClientConfirmed => translate('buddy_home_client_confirmed', fallback: 'Client Confirmed - Your Turn!');
  String get buddyHomeConfirmationRequested => translate('buddy_home_confirmation_requested', fallback: 'Confirmation Requested');
  String get buddyHomeReadyToRequestStart => translate('buddy_home_ready_to_request_start', fallback: 'Ready to Request Start');
  String get buddyHomeViewActiveTrip => translate('buddy_home_view_active_trip', fallback: 'View Active Trip');
  String get buddyHomeConfirmStart => translate('buddy_home_confirm_start', fallback: 'Confirm Start');
  String get buddyHomeRequestStart => translate('buddy_home_request_start', fallback: 'Request Start');
  String get buddyHomeConfirmationSent => translate('buddy_home_confirmation_sent', fallback: 'Confirmation request sent to client!');
  String get buddyHomeTripConfirmed => translate('buddy_home_trip_confirmed', fallback: 'Trip confirmed! Waiting for client confirmation.');
  String buddyHomeErrorRequesting(String error) => translate('buddy_home_error_requesting',
      fallback: 'Error requesting confirmation: {error}', args: {'error': error});
  String buddyHomeErrorConfirming(String error) => translate('buddy_home_error_confirming',
      fallback: 'Error confirming trip: {error}', args: {'error': error});
  String buddyHomeErrorStarting(String error) => translate('buddy_home_error_starting',
      fallback: 'Error starting trip: {error}', args: {'error': error});
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    // Supported languages
    return ['en', 'es'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final langCode = locale.languageCode;

    Map<String, String> fallbackTranslations = {};
    // Only fetch fallback if the selected language is not English
    if (langCode != 'en') {
      fallbackTranslations = await _fetchTranslations('en');
    }

    final translations = await _fetchTranslations(langCode);

    // Merge the maps, with the current locale's translations taking precedence
    final mergedTranslations = {...fallbackTranslations, ...translations};

    return AppLocalizations(locale, mergedTranslations);
  }

  Future<Map<String, String>> _fetchTranslations(String langCode) async {
    try {
      final response = await supabase
          .from('translations')
          .select('key, value')
          .eq('lang', langCode);

      return {
        for (var row in response) row['key'] as String: row['value'] as String
      };
    } catch (e) {
      debugPrint('Error fetching translations for $langCode: $e');
      // Return an empty map on error so the app can continue with fallback/keys
      return {};
    }
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => true;
}
