import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';

class MakePaymentScreen extends StatefulWidget {
  final double amount;
  final String currency;
  final Map<String, dynamic> buddy;
  final String service;
  final DateTime date;
  final TimeOfDay time;
  final int durationInHours;
  final String? note;
  final String? couponCode; // Added coupon code

  const MakePaymentScreen({
    super.key,
    required this.amount,
    required this.currency,
    required this.buddy,
    required this.service,
    required this.date,
    required this.time,
    required this.durationInHours,
    this.note,
    this.couponCode, // Added to constructor
  });

  @override
  State<MakePaymentScreen> createState() => _MakePaymentScreenState();
}

class _MakePaymentScreenState extends State<MakePaymentScreen> {
  bool _isProcessing = false;
  bool _saveCard = true;
  final CardFormEditController _cardController = CardFormEditController();

  Future<void> _handlePayPress() async {
    final localizations = AppLocalizations.of(context)!;
    if (!_cardController.details.complete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.translate('make_payment_snackbar_fill_details'))),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. Create Payment Intent on the server
      debugPrint('Creating payment intent for amount: \$${widget.amount}');

      final response = await supabase.functions.invoke('smart-handler', body: {
        'action': 'create-payment-intent',
        'amount': (widget.amount * 100).round(), // Convert to cents
        'currency': widget.currency.toLowerCase(),
        'saveCard': _saveCard,
        'couponCode': widget.couponCode, // Pass coupon code to backend
      });

      debugPrint('Payment intent response: ${response.data}');

      if (response.data == null || response.data['clientSecret'] == null) {
        throw Exception('Failed to create payment intent: ${response.data?['error'] ?? 'Unknown error'}');
      }

      final clientSecret = response.data['clientSecret'] as String;
      final paymentIntentId = response.data['paymentIntentId'] as String?;

      debugPrint('Client secret received: ${clientSecret.substring(0, 30)}...');
      debugPrint('Payment Intent ID: $paymentIntentId');

      // 2. Confirm the payment on the client using the card form
      debugPrint('Confirming payment with Stripe...');

      final paymentIntent = await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(
            billingDetails: BillingDetails(
              email: supabase.auth.currentUser?.email,
            ),
          ),
        ),
      );

      debugPrint('Payment confirmed successfully!');
      debugPrint('Payment Intent ID from confirmation: ${paymentIntent.id}');
      debugPrint('Payment status: ${paymentIntent.status}');

      // 3. Finalize the booking on the server, now that payment is confirmed
      await _finalizeBooking(paymentIntent.id);

      // 4. If all goes well, show the success dialog
      _showBookingSuccessDialog();

    } on StripeException catch (e) {
      debugPrint('Stripe error: ${e.error.localizedMessage}');
      debugPrint('Stripe error code: ${e.error.code}');
      debugPrint('Stripe error type: ${e.error.type}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${localizations.translate('make_payment_snackbar_payment_failed')}${e.error.localizedMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('General error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${localizations.translate('make_payment_snackbar_general_error')}${e.toString()}'),
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

  Future<void> _finalizeBooking(String paymentIntentId) async {
    final localizations = AppLocalizations.of(context)!;
    debugPrint('Finalizing booking with payment intent: $paymentIntentId');

    final bookingDate = DateFormat('yyyy-MM-dd').format(widget.date);
    final bookingTime = '${widget.time.hour.toString().padLeft(2, '0')}:${widget.time.minute.toString().padLeft(2, '0')}:00';

    final bookingDetails = {
      'buddy_id': widget.buddy['id'],
      'service': widget.service,
      'date': bookingDate,
      'time': bookingTime,
      'duration': widget.durationInHours * 60,
      'notes': widget.note,
      'amount': widget.amount,
    };

    debugPrint('Booking details: $bookingDetails');

    final response = await supabase.functions.invoke('smart-handler', body: {
      'action': 'create-booking-after-payment',
      'paymentIntentId': paymentIntentId,
      'bookingDetails': bookingDetails,
      'couponCode': widget.couponCode, // Pass coupon code to backend
    });

    debugPrint('Booking finalization response: ${response.data}');

    if (response.data?['success'] != true) {
      throw Exception(response.data?['error'] ?? localizations.translate('make_payment_exception_finalize_booking'));
    }
  }

  void _showBookingSuccessDialog() {
    final localizations = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            // Pop the dialog first
            Navigator.of(context).pop();
            // Then navigate back to the payment options screen and pop it with a success result
            Navigator.of(context).pop(true);
          }
        });
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.shade700,
                    size: 60,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    localizations.translate('make_payment_dialog_success_title'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color accentColor = Color(0xFFF15808);
    final localizations = AppLocalizations.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            localizations.translate('make_payment_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              CardFormField(
                controller: _cardController,
                style: CardFormStyle(
                  backgroundColor: Colors.white,
                  textColor: primaryTextColor,
                  placeholderColor: Colors.grey.shade400,
                  borderColor: Colors.grey.shade300,
                  borderRadius: 8,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Switch(
                    value: _saveCard,
                    onChanged: (value) {
                      setState(() {
                        _saveCard = value;
                      });
                    },
                    activeColor: accentColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      localizations.translate('make_payment_label_save_card'),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildPayButton(context, accentColor),
      ),
    );
  }

  Widget _buildPayButton(BuildContext context, Color accentColor) {
    final localizations = AppLocalizations.of(context)!;
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(24.0, 10.0, 24.0, 34.0),
      child: SafeArea(
        top: false,
        child: ElevatedButton(
          onPressed: _isProcessing ? null : _handlePayPress,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
          child: _isProcessing
              ? const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
          )
              : Text(
            '${localizations.translate('make_payment_button_pay')} \$${widget.amount.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
