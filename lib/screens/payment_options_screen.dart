import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/make_payment_screen.dart';
import 'package:mygobuddy/screens/paypal_webview_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:shimmer/shimmer.dart';

class PaymentOptionsScreen extends StatefulWidget {
  final double amount;
  final String currency;
  final Map<String, dynamic> buddy;
  final String service;
  final DateTime date;
  final TimeOfDay time;
  final int durationInHours;
  final String? note;
  final String? couponCode; // Added coupon code

  const PaymentOptionsScreen({
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
  State<PaymentOptionsScreen> createState() => _PaymentOptionsScreenState();
}

class _PaymentOptionsScreenState extends State<PaymentOptionsScreen> {
  List<dynamic> _savedCards = [];
  bool _isLoading = true;
  String? _selectedCardId;
  bool _isProcessingPayment = false;
  bool _hasInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // DO NOT fetch data here because context for localizations is not available.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fetch data here as context is available.
    // The flag prevents fetching again on subsequent rebuilds.
    if (!_hasInitialized) {
      _hasInitialized = true;
      _fetchSavedCards();
    }
  }

  String _getCurrencySymbol(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return currencyCode;
    }
  }

  Future<void> _fetchSavedCards() async {
    // It's safe to use context here now.
    final localizations = AppLocalizations.of(context)!;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await supabase.functions.invoke('smart-handler',
          body: {'action': 'list-payment-methods'});

      if (!mounted) return;

      if (response.data != null) {
        if (response.data is List) {
          setState(() {
            _savedCards = response.data;
            if (_savedCards.isNotEmpty) {
              _selectedCardId = _savedCards.first['id'];
            }
          });
        } else if (response.data is Map && response.data['error'] != null) {
          throw Exception(response.data['error']);
        } else {
          throw Exception('Unexpected response format from server.');
        }
      } else {
        setState(() {
          _savedCards = [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching saved cards: $e');
      if (mounted) {
        setState(() {
          _error = localizations.translate('payment_options_error_fetching_cards',
              fallback: 'Could not load payment methods.');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${_error!} ${e.toString()}'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleConfirmBooking() async {
    final localizations = AppLocalizations.of(context)!;
    if (_selectedCardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
            Text(localizations.translate('payment_options_error_select_card', fallback: 'Please select a card to proceed')),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isProcessingPayment = true;
    });

    try {
      debugPrint('Processing payment with saved card: $_selectedCardId');
      debugPrint('Amount: ${widget.amount}');

      final bookingDate = DateFormat('yyyy-MM-dd').format(widget.date);
      final bookingTime =
          '${widget.time.hour.toString().padLeft(2, '0')}:${widget.time.minute.toString().padLeft(2, '0')}:00';

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
        'action': 'pay-with-saved-card',
        'paymentMethodId': _selectedCardId,
        'amount': (widget.amount * 100).round(), // Convert to cents
        'currency': widget.currency.toLowerCase(),
        'bookingDetails': bookingDetails,
        'couponCode': widget.couponCode, // Pass coupon code to backend
      });

      debugPrint('Payment response: ${response.data}');

      if (response.data['success'] == true) {
        _showBookingSuccessDialog();
      } else {
        throw Exception(response.data['error'] ??
            localizations.translate('payment_options_exception_booking_failed', fallback: 'Booking failed'));
      }
    } catch (e) {
      debugPrint('Payment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${localizations.translate('payment_options_error_payment_failed', fallback: 'Payment failed')}${e.toString()}'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
        });
      }
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
                    localizations.translate('payment_options_dialog_success_title', fallback: 'Booking Successful!'),
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
          surfaceTintColor: backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            localizations.translate('payment_options_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: _buildBodyContent(accentColor, localizations),
        bottomNavigationBar: _buildConfirmButton(accentColor, localizations),
      ),
    );
  }

  Widget _buildBodyContent(Color accentColor, AppLocalizations localizations) {
    if (_isLoading) {
      return _buildShimmerEffect();
    } else if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchSavedCards,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildPaymentSummary(accentColor, localizations),
            const SizedBox(height: 32),
            _buildSectionHeader(localizations
                .translate('payment_options_header_saved_cards')),
            const SizedBox(height: 16),
            _buildSavedCardsSection(accentColor, localizations),
            const SizedBox(height: 32),
            _buildSectionHeader(localizations
                .translate('payment_options_header_other_methods')),
            const SizedBox(height: 16),
            _buildOtherMethodsSection(localizations),
            const SizedBox(
                height: 100), // Space for the bottom button
          ],
        ),
      );
    }
  }

  Widget _buildShimmerEffect() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 80.0,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: 200,
              height: 20.0,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 3,
                separatorBuilder: (context, index) =>
                const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: 200,
              height: 20.0,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummary(Color accentColor, AppLocalizations localizations) {
    final currencySymbol = _getCurrencySymbol(widget.currency);
    final amountString =
    NumberFormat("#,##0.00", "en_US").format(widget.amount);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              localizations.translate('payment_options_summary_total', fallback: 'Total'),
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280),
              ),
            ),
            Text(
              '$currencySymbol$amountString',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF111827),
      ),
    );
  }

  Widget _buildSavedCardsSection(
      Color accentColor, AppLocalizations localizations) {
    if (_savedCards.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            localizations.translate('payment_options_empty_saved_cards', fallback: 'No saved cards'),
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _savedCards.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cardData = _savedCards[index];
        final card = cardData['card'];
        final cardId = cardData['id'];
        final isSelected = _selectedCardId == cardId;

        return InkWell(
          onTap: () {
            setState(() {
              _selectedCardId = cardId;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? accentColor : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/${card['brand'] == 'visa' ? 'visa_logo.png' : 'master_card.png'}',
                  height: 22,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '**** **** **** ${card['last4']}',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF111827),
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: accentColor,
                    size: 22,
                  )
                else
                  Icon(
                    Icons.radio_button_unchecked,
                    color: Colors.grey.shade300,
                    size: 22,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOtherMethodsSection(AppLocalizations localizations) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _buildOtherMethodItem(
            icon: Icons.add_card,
            text: localizations.translate('payment_options_method_add_card', fallback: 'Add New Card'),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => MakePaymentScreen(
                      amount: widget.amount,
                      currency: widget.currency,
                      buddy: widget.buddy,
                      service: widget.service,
                      date: widget.date,
                      time: widget.time,
                      durationInHours: widget.durationInHours,
                      note: widget.note,
                      couponCode: widget.couponCode, // Pass coupon code
                    )),
              );
              if (result == true) {
                _fetchSavedCards();
              }
            },
          ),
          const Divider(height: 1, indent: 20, endIndent: 20),
          _buildOtherMethodItem(
            imagePath: 'assets/images/paypal_logo.png',
            text: localizations.translate('payment_options_method_paypal', fallback: 'Pay with PayPal'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PaypalWebViewScreen(
                    amount: widget.amount,
                    currency: widget.currency,
                    buddy: widget.buddy,
                    service: widget.service,
                    date: widget.date,
                    time: widget.time,
                    durationInHours: widget.durationInHours,
                    note: widget.note,
                    couponCode: widget.couponCode,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOtherMethodItem({
    IconData? icon,
    String? imagePath,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: icon != null
          ? Icon(icon, color: const Color(0xFF111827))
          : Padding(
        padding: const EdgeInsets.all(4.0),
        child: Image.asset(imagePath!, height: 25),
      ),
      title: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF111827),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
    );
  }

  Widget _buildConfirmButton(Color accentColor, AppLocalizations localizations) {
    final canPress = !_isProcessingPayment && _savedCards.isNotEmpty && _selectedCardId != null;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24.0, 10.0, 24.0, 24.0),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: canPress ? _handleConfirmBooking : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: accentColor.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: _isProcessingPayment
              ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 3))
              : Text(
            localizations.translate('payment_options_button_pay_now', fallback: 'Pay Now'),
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
