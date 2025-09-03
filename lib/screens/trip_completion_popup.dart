import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'dart:io';
import '../providers/trip_provider.dart';
import '../utils/localizations.dart';

class TripCompletionPopup extends StatefulWidget {
  final String bookingId;
  final String buddyName;
  final String buddyImage;

  const TripCompletionPopup({
    Key? key,
    required this.bookingId,
    required this.buddyName,
    required this.buddyImage,
  }) : super(key: key);

  @override
  State<TripCompletionPopup> createState() => _TripCompletionPopupState();
}

class _TripCompletionPopupState extends State<TripCompletionPopup>
    with TickerProviderStateMixin {
  int _rating = 0;
  final TextEditingController _reviewController = TextEditingController();
  final TextEditingController _customTipController = TextEditingController();
  List<File> _selectedImages = [];
  double? _selectedTip;
  bool _isSubmitting = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  final List<double> _presetTips = [1.0, 5.0, 10.0];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _reviewController.dispose();
    _customTipController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();

    if (images.isNotEmpty) {
      setState(() {
        _selectedImages = images.map((image) => File(image.path)).toList();
      });
    }
  }

  void _selectTip(double amount) {
    setState(() {
      _selectedTip = amount;
      _customTipController.clear();
    });
  }

  void _onCustomTipChanged(String value) {
    final double? customAmount = double.tryParse(value);
    if (customAmount != null && customAmount > 0) {
      setState(() {
        _selectedTip = customAmount;
      });
    }
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('pleaseSelectRating')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);

      String? paymentIntentId;
      if (_selectedTip != null && _selectedTip! > 0) {
        // Create payment intent for tip
        final clientSecret = await tripProvider.processTipPayment(_selectedTip!, widget.bookingId);

        if (clientSecret != null) {
          // Present payment sheet to user
          await Stripe.instance.presentPaymentSheet();

          // Extract payment intent ID from client secret
          paymentIntentId = clientSecret.split('_secret_')[0];

          // Confirm the payment
          final paymentConfirmed = await tripProvider.confirmTipPayment(paymentIntentId, widget.bookingId);

          if (!paymentConfirmed) {
            throw Exception('Tip payment confirmation failed');
          }
        } else {
          throw Exception('Failed to create tip payment');
        }
      }

      // Submit review and tip to database
      await tripProvider.submitReviewAndTip(
        bookingId: widget.bookingId,
        rating: _rating,
        reviewText: _reviewController.text.trim(),
        reviewImages: _selectedImages,
        tipAmount: _selectedTip,
      );

      // Close popup with success
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('reviewSubmittedSuccessfully')),
          backgroundColor: const Color(0xFF059669), // Primary green
        ),
      );

      if (_selectedTip != null && _selectedTip! > 0) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Tip of \$${_selectedTip!.toStringAsFixed(2)} sent to ${widget.buddyName}!',
                ),
                backgroundColor: const Color(0xFF10B981),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } catch (e) {
      String errorMessage = e.toString();
      if (e is StripeException) {
        errorMessage = e.error.localizedMessage ?? 'Payment failed';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $errorMessage'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with close button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9), // Muted background
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    // Buddy avatar
                    CircleAvatar(
                      radius: 25,
                      backgroundImage: NetworkImage(widget.buddyImage),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).translate('rateYourRide'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF475569), // Foreground
                            ),
                          ),
                          Text(
                            '${AppLocalizations.of(context).translate('with')} ${widget.buddyName}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Star Rating
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return GestureDetector(
                            onTap: () => setState(() => _rating = index + 1),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                index < _rating ? Icons.star : Icons.star_border,
                                size: 40,
                                color: index < _rating
                                    ? const Color(0xFF10B981) // Accent color
                                    : const Color(0xFFE2E8F0), // Border color
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Review Text
                    Text(
                      AppLocalizations.of(context).translate('shareYourExperience'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reviewController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).translate('writeYourReview'),
                        hintStyle: const TextStyle(color: Color(0xFF475569)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Image Upload
                    GestureDetector(
                      onTap: _pickImages,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFE2E8F0),
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.camera_alt_outlined,
                              size: 32,
                              color: Color(0xFF059669),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedImages.isEmpty
                                  ? AppLocalizations.of(context).translate('uploadPhoto')
                                  : '${_selectedImages.length} ${AppLocalizations.of(context).translate('photosSelected')}',
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Tip Section
                    Text(
                      AppLocalizations.of(context).translate('addTip'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Preset tip buttons
                    Row(
                      children: _presetTips.map((amount) {
                        final isSelected = _selectedTip == amount;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: () => _selectTip(amount),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF059669)
                                      : Colors.white,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF059669)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '\$${amount.toInt()}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF475569),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 12),

                    // Custom tip input
                    TextField(
                      controller: _customTipController,
                      keyboardType: TextInputType.number,
                      onChanged: _onCustomTipChanged,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).translate('customAmount'),
                        hintStyle: const TextStyle(color: Color(0xFF475569)),
                        prefixText: '\$ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitReview,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : Text(
                          AppLocalizations.of(context).translate('submitFeedback'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
