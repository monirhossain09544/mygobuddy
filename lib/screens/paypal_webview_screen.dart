import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:intl/intl.dart';

class PaypalWebViewScreen extends StatefulWidget {
  final double amount;
  final String currency;
  final Map<String, dynamic> buddy;
  final String service;
  final DateTime date;
  final TimeOfDay time;
  final int durationInHours;
  final String? note;
  final String? couponCode;

  const PaypalWebViewScreen({
    super.key,
    required this.amount,
    required this.currency,
    required this.buddy,
    required this.service,
    required this.date,
    required this.time,
    required this.durationInHours,
    this.note,
    this.couponCode,
  });

  @override
  State<PaypalWebViewScreen> createState() => _PaypalWebViewScreenState();
}

class _PaypalWebViewScreenState extends State<PaypalWebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _orderId;
  bool _didInit = false; // Flag to prevent multiple initializations

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Move initialization here to safely access context for localizations
    if (!_didInit) {
      _createPaypalOrder();
      _didInit = true;
    }
  }

  Future<void> _createPaypalOrder() async {
    // It's now safe to get localizations here
    final localizations = AppLocalizations.of(context)!;
    try {
      final response = await supabase.functions.invoke('rapid-task', body: {
        'action': 'create-order',
        'amount': widget.amount,
        'currency': widget.currency,
      });

      // Check for function-level errors before processing
      if (response.data is Map && response.data['error'] != null) {
        throw Exception(response.data['error']);
      }

      if (response.data != null && response.data['approveUrl'] != null) {
        if (!mounted) return;
        setState(() {
          _orderId = response.data['orderId'];
          _controller = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setNavigationDelegate(
              NavigationDelegate(
                onPageFinished: (String url) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                },
                onNavigationRequest: (NavigationRequest request) {
                  if (request.url
                      .startsWith('https://mygobuddy.app/paypal/success')) {
                    _capturePaypalOrder();
                    return NavigationDecision.prevent;
                  }
                  if (request.url
                      .startsWith('https://mygobuddy.app/paypal/cancel')) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(localizations
                              .translate('paypal_payment_cancelled')),
                          backgroundColor: Colors.orange),
                    );
                    return NavigationDecision.prevent;
                  }
                  return NavigationDecision.navigate;
                },
              ),
            )
            ..loadRequest(Uri.parse(response.data['approveUrl']));
        });
      } else {
        // Handle cases where approveUrl is null but no explicit error was sent
        throw Exception(
            localizations.translate('paypal_error_creating_order'));
      }
    } catch (e) {
      if (!mounted) return;
      // Pop the screen and show an error message
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${localizations.translate('paypal_generic_error')}: ${e.toString()}'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _capturePaypalOrder() async {
    if (_orderId == null) return;
    final localizations = AppLocalizations.of(context)!;

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
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
        'coupon_used': widget.couponCode,
      };

      final response = await supabase.functions.invoke('rapid-task', body: {
        'action': 'capture-order',
        'orderId': _orderId,
        'bookingDetails': bookingDetails,
      });

      // Check for function-level errors
      if (response.data is Map && response.data['error'] != null) {
        throw Exception(response.data['error']);
      }

      if (response.data['success'] == true) {
        _showBookingSuccessDialog();
      } else {
        throw Exception(
            localizations.translate('paypal_error_capturing_payment'));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${localizations.translate('paypal_payment_failed')}: ${e.toString()}'),
            backgroundColor: Colors.red),
      );
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
            Navigator.of(context).pop(); // Close the dialog
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const MainScreen(initialIndex: 1)),
                  (Route<dynamic> route) => false,
            );
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
              padding:
              const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
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
                    localizations.translate('paypal_booking_successful'),
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
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(localizations.translate('paypal_webview_title')),
        centerTitle: true,
        backgroundColor: const Color(0xFFF9FAFB),
        elevation: 0,
        titleTextStyle: GoogleFonts.poppins(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Stack(
        children: [
          // Only build the WebView when the controller is ready
          if (_controller != null) WebViewWidget(controller: _controller!),
          // Show a loading indicator on top
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFF15808),
              ),
            ),
        ],
      ),
    );
  }
}
