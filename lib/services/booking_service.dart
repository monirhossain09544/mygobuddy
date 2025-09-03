import 'package:mygobuddy/main.dart';

import '../utils/constants.dart';

class BookingService {
  static Future<bool> cancelBooking(String bookingId, String reason) async {
    return await cancelBookingWithRefund(bookingId, reason);
  }

  static Future<bool> cancelBookingWithRefund(String bookingId, String reason) async {
    try {
      final bookingResponse = await supabase
          .from('bookings')
          .select('payment_intent_id, amount, status')
          .eq('id', bookingId)
          .single();

      final status = bookingResponse['status'] as String?;

      // Check if booking is already cancelled or refunded
      if (status == 'cancelled' || status == 'refunded') {
        throw Exception('This booking has already been cancelled and refunded.');
      }

      final paymentIntentId = bookingResponse['payment_intent_id'] as String?;
      final amount = (bookingResponse['amount'] as num?)?.toDouble();

      await supabase
          .from('bookings')
          .update({
        'status': 'cancelled',
        'cancellation_reason': reason,
        'cancelled_at': DateTime.now().toIso8601String(),
        'refund_amount': amount?.toString() ?? '0.00',
        'refund_status': 'pending',
        'refund_initiated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', bookingId);

      if (paymentIntentId != null && paymentIntentId.startsWith('paypal_')) {
        // Handle PayPal refund
        final paypalOrderId = paymentIntentId.replaceFirst('paypal_', '');

        try {
          final paypalResponse = await supabase.functions.invoke(
            'rapid-task',
            body: {
              'action': 'refund-paypal-payment',
              'orderId': paypalOrderId,
              'reason': reason,
              'bookingId': bookingId, // Pass bookingId for status updates
            },
          );

          if (paypalResponse.data != null && paypalResponse.data['error'] != null) {
            final errorMessage = paypalResponse.data['error'] as String;
            throw Exception('PayPal refund failed: $errorMessage');
          }
        } catch (e) {
          // Handle PayPal-specific errors
          final errorString = e.toString();
          if (errorString.contains('REFUNDED') ||
              errorString.contains('already been refunded') ||
              errorString.contains('Current status: REFUNDED')) {
            await supabase
                .from('bookings')
                .update({
              'refund_status': 'completed',
              'refund_completed_at': DateTime.now().toIso8601String(),
            })
                .eq('id', bookingId);

            return true; // Treat as successful cancellation
          }
          await supabase
              .from('bookings')
              .update({
            'refund_status': 'failed',
            'refund_error_message': errorString,
          })
              .eq('id', bookingId);
          rethrow;
        }
      } else {
        final response = await supabase.functions.invoke(
          'smart-handler',
          body: {
            'action': 'cancel-booking-with-refund',
            'bookingId': bookingId,
            'reason': reason,
          },
        );

        if (response.data != null && response.data['error'] != null) {
          await supabase
              .from('bookings')
              .update({
            'refund_status': 'failed',
            'refund_error_message': response.data['error'],
          })
              .eq('id', bookingId);
          throw Exception('Cancellation failed: ${response.data['error']}');
        }
      }

      return true;
    } catch (e) {
      print('Booking cancellation error: $e');
      rethrow;
    }
  }
}
