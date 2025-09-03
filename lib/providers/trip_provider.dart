import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripProvider with ChangeNotifier {
  final FlutterBackgroundService _service = FlutterBackgroundService();
  String? _activeBookingId;
  Duration _duration = Duration.zero;
  bool _isServiceRunning = false;
  bool _isPaused = false;
  DateTime? _serverStartTime;
  StreamSubscription<List<Map<String, dynamic>>>? _bookingSubscription;
  Timer? _durationTimer;

  String? get activeBookingId => _activeBookingId;
  Duration get duration => _duration;
  bool get isPaused => _isPaused;

  TripProvider() {
    _initialize();
  }

  void _initialize() async {
    _isServiceRunning = await _service.isRunning();

    _listenForActiveBookings();

    _service.on('updateTrip').listen((data) {
      if (data != null && data['booking_id'] != null) {
        _activeBookingId = data['booking_id'] as String;
        _duration = Duration(seconds: data['duration']);
        if (_isPaused) {
          _isPaused = false;
        }
        notifyListeners();
      }
    });

    _service.on('tripPaused').listen((data) {
      if (data != null && data['booking_id'] != null) {
        if (!_isPaused) {
          _isPaused = true;
          notifyListeners();
        }
      }
    });

    _service.on('stop').listen((_) {
      if (_isServiceRunning) {
        _activeBookingId = null;
        _duration = Duration.zero;
        _isServiceRunning = false;
        _isPaused = false;
        _serverStartTime = null;
        _durationTimer?.cancel();
        notifyListeners();
      }
    });
  }

  void _listenForActiveBookings() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _bookingSubscription = supabase
        .from('bookings')
        .stream(primaryKey: ['id']).listen((bookings) {
      final activeBookings = bookings.where((booking) =>
      (booking['buddy_id'] == userId || booking['client_id'] == userId) &&
          booking['status'] == 'in_progress'
      ).toList();

      if (activeBookings.isNotEmpty) {
        final activeBooking = activeBookings.first;
        final bookingId = activeBooking['id'] as String;

        if (_activeBookingId != bookingId) {
          _activeBookingId = bookingId;
          _serverStartTime = DateTime.parse(activeBooking['updated_at'] ?? DateTime.now().toIso8601String());
          _calculateServerBasedDuration();

          final currentDuration = DateTime.now().difference(_serverStartTime!);
          _duration = currentDuration;

          notifyListeners();
        }
      } else if (_activeBookingId != null) {
        final completedBookings = bookings.where((booking) =>
        (booking['buddy_id'] == userId || booking['client_id'] == userId) &&
            booking['status'] == 'completed' &&
            booking['id'] == _activeBookingId
        ).toList();

        if (completedBookings.isNotEmpty) {
          // Trip was completed, keep final duration
          final finalDuration = _duration;
          _activeBookingId = null;
          _duration = finalDuration;
          _serverStartTime = null;
          _isPaused = false;
          _durationTimer?.cancel();
          notifyListeners();
        } else {
          // Trip ended on another device
          _activeBookingId = null;
          _duration = Duration.zero;
          _serverStartTime = null;
          _isPaused = false;
          _durationTimer?.cancel();
          notifyListeners();
        }
      }
    });
  }

  void _calculateServerBasedDuration() {
    if (_serverStartTime == null) return;

    _durationTimer?.cancel();

    final now = DateTime.now();
    final serverDuration = now.difference(_serverStartTime!);
    _duration = serverDuration;

    // Start a timer to keep updating the duration
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeBookingId == null || _serverStartTime == null) {
        timer.cancel();
        return;
      }

      final currentDuration = DateTime.now().difference(_serverStartTime!);
      _duration = currentDuration;
      notifyListeners();
    });

    notifyListeners();
  }

  bool isTripActive(String bookingId) {
    return _activeBookingId == bookingId && (_isServiceRunning || _serverStartTime != null);
  }

  Duration getTripDuration(String bookingId) {
    if (_activeBookingId == bookingId) {
      if (_serverStartTime != null) {
        return DateTime.now().difference(_serverStartTime!);
      }
      return _duration;
    }
    return _duration;
  }

  Future<void> startTrip(String bookingId) async {
    if (_activeBookingId != null) return;

    try {
      // First, verify that both parties have confirmed the trip
      final booking = await supabase
          .from('bookings')
          .select('duration, both_confirmed, buddy_confirmed, client_confirmed, status')
          .eq('id', bookingId)
          .single();

      final bothConfirmed = booking['both_confirmed'] as bool? ?? false;
      final status = booking['status'] as String? ?? '';

      // Only allow trip start if both parties have confirmed
      if (!bothConfirmed) {
        debugPrint("Cannot start trip: Both parties must confirm first");
        throw Exception("Trip requires confirmation from both buddy and client");
      }

      // Ensure booking is in accepted status (should be automatically updated by trigger)
      if (status != 'accepted' && status != 'in_progress') {
        debugPrint("Cannot start trip: Booking status is $status, expected 'accepted' or 'in_progress'");
        throw Exception("Booking is not in a valid state to start trip");
      }

      final int bookedDurationMinutes = booking['duration'] as int? ?? 0;

      // Ensure the service is running before invoking tasks.
      if (!await _service.isRunning()) {
        await _service.startService();
      }

      final startTime = DateTime.now();

      // Update booking status to in_progress (if not already)
      if (status != 'in_progress') {
        await supabase.from('bookings').update({
          'status': 'in_progress',
          'updated_at': startTime.toIso8601String(),
        }).eq('id', bookingId);
      }

      _activeBookingId = bookingId;
      _duration = Duration.zero;
      _serverStartTime = startTime;
      _isPaused = false;
      _isServiceRunning = true;
      notifyListeners();

      _service.invoke('startTask', {
        'task': 'startTrip',
        'booking_id': bookingId,
        'start_time': startTime.toIso8601String(),
        'booked_duration_minutes': bookedDurationMinutes,
      });

      debugPrint("Trip started successfully for booking $bookingId with dual confirmation");
    } catch (e) {
      debugPrint("Failed to start trip: $e");
      rethrow; // Re-throw to let the UI handle the error
    }
  }

  Future<void> pauseTrip(String bookingId) async {
    if (_activeBookingId != bookingId || _isPaused) return;
    _isPaused = true;
    _service.invoke('startTask', {'task': 'pauseTrip', 'booking_id': bookingId});
    notifyListeners();
  }

  Future<void> resumeTrip(String bookingId) async {
    if (_activeBookingId != bookingId || !_isPaused) return;
    _isPaused = false;
    _service.invoke('startTask', {'task': 'resumeTrip', 'booking_id': bookingId});
    notifyListeners();
  }

  Future<void> endTrip(String bookingId) async {
    try {
      final confirmationRequested = await this.requestTripCompletionConfirmation(bookingId);

      if (!confirmationRequested) {
        throw Exception("Failed to request trip completion confirmation");
      }

      debugPrint("Trip completion confirmation requested for booking $bookingId");

      // The trip will be completed automatically when both parties confirm
      // via the database trigger system

    } catch (e) {
      debugPrint("Failed to end trip: $e");
      rethrow;
    }
  }

  Future<bool> requestTripCompletionConfirmation(String bookingId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await supabase.rpc('request_trip_completion_confirmation', params: {
        'booking_id': bookingId,
        'requesting_user_id': userId,
      });

      return response['success'] == true;
    } catch (e) {
      debugPrint("Failed to request trip completion confirmation: $e");
      return false;
    }
  }

  Future<bool> confirmTripCompletion(String bookingId, String userType) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await supabase.rpc('confirm_trip_completion', params: {
        'booking_id': bookingId,
        'user_id': userId,
        'user_type': userType,
      });

      return response['success'] == true;
    } catch (e) {
      debugPrint("Failed to confirm trip completion: $e");
      return false;
    }
  }

  Future<void> submitReviewAndTip({
    required String bookingId,
    required int rating,
    String? reviewText,
    List<File>? reviewImages,
    double? tipAmount,
  }) async {
    try {
      debugPrint('[v0] Starting submitReviewAndTip - bookingId: $bookingId, rating: $rating, tipAmount: $tipAmount');

      if (tipAmount != null && tipAmount > 0) {
        debugPrint('[v0] Checking if tip already exists for booking: $bookingId');
        try {
          final existingTip = await supabase
              .from('tips')
              .select('id, amount, status, booking_id, client_id, buddy_id')
              .eq('booking_id', bookingId)
              .maybeSingle();

          if (existingTip != null) {
            debugPrint('[v0] FOUND EXISTING TIP - cannot process payment');
            debugPrint('[v0] - Tip ID: ${existingTip['id']}');
            debugPrint('[v0] - Amount: ${existingTip['amount']}');
            debugPrint('[v0] - Status: ${existingTip['status']}');
            throw Exception('A tip has already been given for this booking');
          }
          debugPrint('[v0] No existing tip found for booking $bookingId, proceeding with payment');
        } catch (e) {
          if (e.toString().contains('already been given')) {
            rethrow;
          }
          debugPrint('[v0] Error checking existing tip (continuing): $e');
        }
      }

      // Upload images if provided
      List<String>? imageUrls;
      if (reviewImages != null && reviewImages.isNotEmpty) {
        debugPrint('[v0] Uploading ${reviewImages.length} review images');
        imageUrls = await _uploadReviewImages(reviewImages, bookingId);
        debugPrint('[v0] Uploaded images: $imageUrls');
      }

      String? transactionId;
      if (tipAmount != null && tipAmount > 0) {
        debugPrint('[v0] Processing tip payment for amount: \$${tipAmount.toStringAsFixed(2)}');

        try {
          // Create payment intent
          final clientSecret = await processTipPayment(tipAmount, bookingId);
          debugPrint('[v0] Payment intent created, clientSecret: ${clientSecret?.substring(0, 20)}...');

          if (clientSecret != null) {
            // Extract payment intent ID from client secret
            final paymentIntentId = clientSecret.split('_secret_')[0];
            debugPrint('[v0] Extracted paymentIntentId: $paymentIntentId');

            // Confirm the payment
            debugPrint('[v0] Confirming payment...');
            final paymentConfirmed = await confirmTipPayment(paymentIntentId, bookingId);
            debugPrint('[v0] Payment confirmation result: $paymentConfirmed');

            if (paymentConfirmed) {
              transactionId = paymentIntentId;
              debugPrint('[v0] Payment successful, transactionId: $transactionId');
            } else {
              debugPrint('[v0] Payment confirmation failed');
              throw Exception('Payment confirmation failed');
            }
          } else {
            debugPrint('[v0] Client secret is null - payment initialization failed');
            throw Exception('Payment initialization failed');
          }
        } catch (paymentError) {
          debugPrint('[v0] Payment processing error: $paymentError');
          rethrow;
        }
      } else {
        debugPrint('[v0] No tip amount provided, skipping payment processing');
      }

      final String finalReviewText = reviewText?.trim() ?? '';
      debugPrint('[v0] Final review text length: ${finalReviewText.length}');

      debugPrint('[v0] Calling submit_review_and_tip RPC with params:');
      debugPrint('[v0] - p_booking_id: $bookingId');
      debugPrint('[v0] - p_rating: $rating');
      debugPrint('[v0] - p_review_text: ${finalReviewText.isNotEmpty ? "provided" : "empty"}');
      debugPrint('[v0] - p_review_images: ${imageUrls?.length ?? 0} images');
      debugPrint('[v0] - p_tip_amount: $tipAmount');
      debugPrint('[v0] - p_payment_method: ${tipAmount != null ? 'card' : null}');
      debugPrint('[v0] - p_transaction_id: $transactionId');

      try {
        final response = await supabase.rpc('submit_review_and_tip', params: {
          'p_booking_id': bookingId,
          'p_rating': rating,
          'p_review_text': finalReviewText,
          'p_review_images': imageUrls,
          'p_tip_amount': tipAmount,
          'p_payment_method': tipAmount != null ? 'card' : null,
          'p_transaction_id': transactionId,
        });

        debugPrint('[v0] RPC response: $response');

        if (response['success'] != true) {
          debugPrint('[v0] RPC failed with message: ${response['message']}');
          throw Exception(response['message'] ?? 'Failed to submit review');
        }

        debugPrint('[v0] Review and tip submitted successfully');
      } catch (rpcError) {
        debugPrint('[v0] RPC error: $rpcError');
        debugPrint('[v0] RPC error type: ${rpcError.runtimeType}');

        final errorMessage = rpcError.toString().toLowerCase();
        if (errorMessage.contains('reviews_booking_id_key')) {
          debugPrint('[v0] Review duplicate constraint violation detected');
          throw Exception('A review has already been submitted for this booking');
        } else if (errorMessage.contains('tips_booking_id_key')) {
          debugPrint('[v0] Tip duplicate constraint violation detected');
          throw Exception('A tip has already been given for this booking');
        } else if (errorMessage.contains('duplicate key') || errorMessage.contains('unique constraint')) {
          debugPrint('[v0] Generic unique constraint violation detected');
          throw Exception('This action has already been completed for this booking');
        }

        rethrow;
      }
    } catch (e) {
      debugPrint('[v0] Error in submitReviewAndTip: $e');
      debugPrint('[v0] Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<List<String>> _uploadReviewImages(List<File> images, String bookingId) async {
    List<String> imageUrls = [];

    for (int i = 0; i < images.length; i++) {
      try {
        final file = images[i];
        final fileName = 'review_${bookingId}_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final filePath = 'reviews/$fileName';

        // Upload to Supabase Storage
        await supabase.storage.from('review-images').upload(filePath, file);

        // Get public URL
        final publicUrl = supabase.storage.from('review-images').getPublicUrl(filePath);
        imageUrls.add(publicUrl);
      } catch (e) {
        debugPrint('Error uploading image $i: $e');
        // Continue with other images even if one fails
      }
    }

    return imageUrls;
  }

  Future<String?> processTipPayment(double amount, String bookingId) async {
    try {
      debugPrint('[v0] processTipPayment called with amount: \$${amount.toStringAsFixed(2)}, bookingId: $bookingId');

      final requestBody = {
        'action': 'process-tip-payment',
        'booking_id': bookingId,
        'amount': amount,
        'currency': 'usd',
      };
      debugPrint('[v0] Sending request to smart-handler: $requestBody');

      final response = await supabase.functions.invoke('smart-handler', body: requestBody);
      debugPrint('[v0] smart-handler response: ${response.data}');

      if (response.data['success'] == true) {
        final clientSecret = response.data['clientSecret'] as String?;
        debugPrint('[v0] Payment intent created successfully, clientSecret length: ${clientSecret?.length}');
        return clientSecret;
      } else {
        final error = response.data['error'] ?? 'Payment failed';
        debugPrint('[v0] Payment processing failed: $error');
        throw Exception(error);
      }
    } catch (e) {
      debugPrint('[v0] Exception in processTipPayment: $e');
      debugPrint('[v0] Exception type: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<bool> confirmTipPayment(String paymentIntentId, String bookingId) async {
    try {
      debugPrint('[v0] confirmTipPayment called with paymentIntentId: $paymentIntentId, bookingId: $bookingId');

      final requestBody = {
        'action': 'confirm-tip-payment',
        'paymentIntentId': paymentIntentId,
        'booking_id': bookingId,
      };
      debugPrint('[v0] Sending confirmation request: $requestBody');

      final response = await supabase.functions.invoke('smart-handler', body: requestBody);
      debugPrint('[v0] Confirmation response: ${response.data}');

      final success = response.data['success'] == true;
      debugPrint('[v0] Payment confirmation result: $success');

      if (!success) {
        debugPrint('[v0] Payment confirmation failed with error: ${response.data['error']}');
      }

      return success;
    } catch (e) {
      debugPrint('[v0] Exception in confirmTipPayment: $e');
      debugPrint('[v0] Exception type: ${e.runtimeType}');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getBuddyReviews(String buddyId, {int limit = 10}) async {
    try {
      final response = await supabase
          .from('reviews')
          .select('''
            id,
            rating,
            review_text,
            review_images,
            created_at,
            profiles!reviews_client_id_fkey(
              first_name,
              last_name,
              profile_image
            )
          ''')
          .eq('buddy_id', buddyId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching buddy reviews: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getBuddyTipsSummary(String buddyId) async {
    try {
      final response = await supabase
          .from('tips')
          .select('amount')
          .eq('buddy_id', buddyId)
          .eq('status', 'completed');

      double totalTips = 0;
      int tipCount = 0;

      for (final tip in response) {
        totalTips += (tip['amount'] as num).toDouble();
        tipCount++;
      }

      return {
        'total_tips': totalTips,
        'tip_count': tipCount,
        'average_tip': tipCount > 0 ? totalTips / tipCount : 0,
      };
    } catch (e) {
      debugPrint('Error fetching buddy tips summary: $e');
      return {
        'total_tips': 0.0,
        'tip_count': 0,
        'average_tip': 0.0,
      };
    }
  }

  Future<void> updateReview({
    required String reviewId,
    required String bookingId,
    required int rating,
    String? reviewText,
    List<File>? reviewImages,
  }) async {
    try {
      debugPrint('[v0] Starting updateReview - reviewId: $reviewId, bookingId: $bookingId, rating: $rating');

      // Upload images if provided
      List<String>? imageUrls;
      if (reviewImages != null && reviewImages.isNotEmpty) {
        debugPrint('[v0] Uploading ${reviewImages.length} review images');
        imageUrls = await _uploadReviewImages(reviewImages, bookingId);
        debugPrint('[v0] Uploaded images: $imageUrls');
      }

      final String finalReviewText = reviewText?.trim() ?? '';
      debugPrint('[v0] Final review text length: ${finalReviewText.length}');

      // Update the existing review
      await supabase.from('reviews').update({
        'rating': rating,
        'review_text': finalReviewText,
        'review_images': imageUrls,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', reviewId);

      debugPrint('[v0] Review updated successfully');
    } catch (e) {
      debugPrint('[v0] Error in updateReview: $e');
      rethrow;
    }
  }

  void clearTripState() {
    if (_isServiceRunning) {
      _service.invoke('stop');
    }
    _activeBookingId = null;
    _duration = Duration.zero;
    _isPaused = false;
    _isServiceRunning = false;
    _serverStartTime = null;
    _durationTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _bookingSubscription?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }
}
