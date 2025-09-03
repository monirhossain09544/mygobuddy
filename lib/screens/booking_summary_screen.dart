import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/payment_options_screen.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/constants.dart';

class BookingSummaryScreen extends StatefulWidget {
  final Map<String, dynamic> buddy;
  final String service; // This is the original English service name
  final DateTime date;
  final TimeOfDay time;
  final int durationInHours;
  final String? note;

  const BookingSummaryScreen({
    super.key,
    required this.buddy,
    required this.service,
    required this.date,
    required this.time,
    required this.durationInHours,
    this.note,
  });

  @override
  State<BookingSummaryScreen> createState() => _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends State<BookingSummaryScreen> {
  String _translatedService = '';
  bool _isLoading = true;

  // --- Coupon State ---
  final _couponController = TextEditingController();
  bool _isApplyingCoupon = false;
  String? _appliedCouponCode;
  double _discount = 0.0;
  String? _couponError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchTranslatedService();
      }
    });
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _fetchTranslatedService() async {
    if (!mounted) return;
    final localizations = AppLocalizations.of(context);
    try {
      final serviceData = await supabase
          .from('services')
          .select('name_key')
          .eq('name', widget.service)
          .single();
      final nameKey = serviceData['name_key'] as String?;
      if (nameKey != null) {
        setState(() {
          _translatedService = localizations.translate(nameKey, fallback: widget.service);
        });
      } else {
        setState(() {
          _translatedService = widget.service;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _translatedService = widget.service;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _applyCoupon() async {
    final localizations = AppLocalizations.of(context);
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isApplyingCoupon = true;
      _couponError = null;
    });

    try {
      final ratesMap = widget.buddy['rate'] as Map<String, dynamic>?;
      final buddyRate = (ratesMap?[widget.service] as num?)?.toDouble() ?? 50.0;
      final subtotal = buddyRate * widget.durationInHours;

      final response = await supabase.functions.invoke('smart-handler', body: {
        'action': 'validate-coupon',
        'code': code,
        'amount': subtotal,
      });

      if (!mounted) return;

      if (response.data['valid'] == true) {
        // Safely handle the discount value, which might be null
        final dynamic discountData = response.data['discount'];
        if (discountData != null) {
          final discountValue = (discountData as num).toDouble();
          setState(() {
            _discount = discountValue;
            _appliedCouponCode = code;
            _couponController.clear();
            context.showSnackBar(
              localizations.translate('booking_summary_coupon_success', fallback: 'Coupon applied!'),
              isError: false,
            );
          });
        } else {
          // This case can happen if the discount is 0. It's still valid.
          setState(() {
            _discount = 0.0;
            _appliedCouponCode = code;
            _couponController.clear();
            context.showSnackBar(
              localizations.translate('booking_summary_coupon_success', fallback: 'Coupon applied!'),
              isError: false,
            );
          });
        }
      } else {
        setState(() {
          _couponError = response.data['error'] ?? localizations.translate('booking_summary_coupon_invalid', fallback: 'Invalid coupon code.');
        });
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = localizations.translate('booking_summary_coupon_error', fallback: 'An error occurred.');
        if (e is FunctionException) {
          final details = e.details;
          if (details is Map && details.containsKey('error')) {
            errorMessage = details['error'];
          } else {
            errorMessage = e.toString();
          }
        } else {
          errorMessage = e.toString();
        }
        setState(() {
          _couponError = errorMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingCoupon = false;
        });
      }
    }
  }

  void _removeCoupon() {
    setState(() {
      _discount = 0.0;
      _appliedCouponCode = null;
      _couponError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color accentColor = Color(0xFFF15808);
    final localizations = AppLocalizations.of(context);
    final ratesMap = widget.buddy['rate'] as Map<String, dynamic>?;
    final buddyRate = (ratesMap?[widget.service] as num?)?.toDouble() ?? 50.0;
    final subtotal = buddyRate * widget.durationInHours;
    final serviceFee = 0.0;
    final totalCost = (subtotal - _discount) + serviceFee;
    final durationText = widget.durationInHours == 1
        ? localizations.translate('booking_summary_hour_singular', fallback: 'Hour')
        : localizations.translate('booking_summary_hour_plural', fallback: 'Hours');
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
            localizations.translate('booking_summary_title', fallback: 'Booking Summary'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: accentColor))
            : SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(localizations.translate('booking_summary_buddy_details', fallback: 'Buddy Details')),
              const SizedBox(height: 16),
              _buildBuddyInfoCard(widget.buddy, localizations),
              const SizedBox(height: 32),
              _buildSectionTitle(localizations.translate('booking_summary_booking_details', fallback: 'Booking Details')),
              const SizedBox(height: 16),
              _buildDetailsCard([
                _buildDetailRow(localizations.translate('booking_summary_service', fallback: 'Service'), _translatedService),
                _buildDetailRow(localizations.translate('booking_summary_date', fallback: 'Date'), DateFormat('dd MMMM, yyyy').format(widget.date)),
                _buildDetailRow(localizations.translate('booking_summary_time', fallback: 'Time'), widget.time.format(context)),
                _buildDetailRow(localizations.translate('booking_summary_duration', fallback: 'Duration'), '${widget.durationInHours} $durationText'),
                if (widget.note != null && widget.note!.isNotEmpty)
                  _buildDetailRow(localizations.translate('booking_summary_note', fallback: 'Note'), widget.note!),
              ]),
              const SizedBox(height: 32),
              _buildSectionTitle(localizations.translate('booking_summary_coupon_code', fallback: 'Coupon Code')),
              const SizedBox(height: 16),
              _buildCouponSection(localizations, accentColor, primaryTextColor),
              const SizedBox(height: 32),
              _buildSectionTitle(localizations.translate('booking_summary_payment_details', fallback: 'Payment Details')),
              const SizedBox(height: 16),
              _buildDetailsCard([
                _buildPaymentRow(localizations.translate('booking_summary_buddy_rate', fallback: 'Buddy Rate'), '\$${buddyRate.toStringAsFixed(2)} x ${widget.durationInHours} hr'),
                if (_discount > 0)
                  _buildPaymentRow(
                    localizations.translate('booking_summary_discount_applied', fallback: 'Discount ($_appliedCouponCode)'),
                    '- \$${_discount.toStringAsFixed(2)}',
                    isDiscount: true,
                  ),
                if (serviceFee > 0)
                  _buildPaymentRow(localizations.translate('booking_summary_service_fee', fallback: 'Service Fee'), '\$${serviceFee.toStringAsFixed(2)}'),
                const Divider(height: 24, thickness: 1),
                _buildPaymentRow(localizations.translate('booking_summary_total', fallback: 'Total'), '\$${totalCost.toStringAsFixed(2)}', isTotal: true),
              ]),
            ],
          ),
        ),
        bottomNavigationBar: _buildActionButton(context, accentColor, totalCost, localizations),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF111827),
      ),
    );
  }

  Widget _buildBuddyInfoCard(Map<String, dynamic> buddy, AppLocalizations localizations) {
    final String buddyName = buddy['name'] ?? 'No Name';
    final String? buddyImageUrl = buddy['profile_picture'];
    final String buddyTitle = buddy['title'] ?? localizations.translate('booking_summary_default_buddy_title', fallback: 'Verified Buddy');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: (buddyImageUrl != null && buddyImageUrl.isNotEmpty)
                ? NetworkImage(buddyImageUrl)
                : const AssetImage('assets/images/sam_wilson.png') as ImageProvider,
            backgroundColor: Colors.grey.shade200,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  buddyName,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  buddyTitle,
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                color: const Color(0xFF111827),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(String label, String value, {bool isTotal = false, bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isTotal
                  ? const Color(0xFF111827)
                  : isDiscount
                  ? Colors.green.shade700
                  : Colors.grey.shade600,
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: isDiscount ? Colors.green.shade700 : const Color(0xFF111827),
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponSection(AppLocalizations localizations, Color accentColor, Color primaryTextColor) {
    if (_appliedCouponCode != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.translate('booking_summary_coupon_applied_label', fallback: 'Coupon Applied'),
                    style: GoogleFonts.poppins(color: Colors.green.shade800, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  Text(
                    _appliedCouponCode!,
                    style: GoogleFonts.poppins(color: Colors.green.shade900, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.cancel, color: Colors.green.shade700),
              onPressed: _removeCoupon,
            )
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _couponController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: localizations.translate('booking_summary_coupon_hint', fallback: 'Enter coupon code'),
                  hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: accentColor, width: 1.5),
                  ),
                  errorText: _couponError,
                  errorMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isApplyingCoupon ? null : _applyCoupon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryTextColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isApplyingCoupon
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : Text(localizations.translate('booking_summary_coupon_apply', fallback: 'Apply')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, Color accentColor, double totalCost, AppLocalizations localizations) {
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(24.0, 10.0, 24.0, 34.0),
      child: SafeArea(
        top: false,
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentOptionsScreen(
                  amount: totalCost,
                  currency: 'usd',
                  buddy: widget.buddy,
                  service: widget.service,
                  date: widget.date,
                  time: widget.time,
                  durationInHours: widget.durationInHours,
                  note: widget.note,
                  couponCode: _appliedCouponCode, // Pass the coupon code
                ),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
          child: Text(
            localizations.translate('booking_summary_proceed_to_pay', fallback: 'Proceed to Pay'),
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
