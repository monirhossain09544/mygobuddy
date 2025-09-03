import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'dart:io';
import '../providers/trip_provider.dart';
import '../utils/localizations.dart';
import '../utils/constants.dart'; // Added import for constants to access global supabase

class ReviewScreen extends StatefulWidget {
  final String bookingId;
  final String buddyName;
  final String buddyImage;
  final String serviceName;
  final Map<String, dynamic>? existingReview;

  const ReviewScreen({
    Key? key,
    required this.bookingId,
    required this.buddyName,
    required this.buddyImage,
    required this.serviceName,
    this.existingReview,
  }) : super(key: key);

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with TickerProviderStateMixin {
  int _rating = 0;
  final TextEditingController _reviewController = TextEditingController();
  final TextEditingController _customTipController = TextEditingController();
  List<File> _selectedImages = [];
  double? _selectedTip;
  bool _isSubmitting = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool get _isEditing => widget.existingReview != null;

  final List<double> _presetTips = [1.0, 5.0, 10.0, 20.0];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    _fadeController.forward();

    if (_isEditing) {
      _populateExistingReview();
    }
  }

  void _populateExistingReview() {
    final review = widget.existingReview!;
    setState(() {
      _rating = review['rating'] ?? 0;
      _reviewController.text = review['review_text'] ?? '';
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _reviewController.dispose();
    _customTipController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();

    if (images.isNotEmpty && images.length <= 5) {
      setState(() {
        _selectedImages = images.map((image) => File(image.path)).toList();
      });
    } else if (images.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('maxFivePhotos')),
          backgroundColor: Colors.orange,
        ),
      );
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
    } else if (value.isEmpty) {
      setState(() {
        _selectedTip = null;
      });
    }
  }

  Future<void> _submitReview() async {
    final bool hasReview = _rating > 0 || _reviewController.text.trim().isNotEmpty || _selectedImages.isNotEmpty;
    final bool hasTip = _selectedTip != null && _selectedTip! > 0;

    if (!hasReview && !hasTip) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('pleaseAddReviewOrTip')),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);

      if (hasTip) {
        try {
          final existingTip = await supabase
              .from('tips')
              .select('id, amount, status')
              .eq('booking_id', widget.bookingId)
              .maybeSingle();

          if (existingTip != null) {
            throw Exception('A tip has already been given for this booking');
          }
        } catch (e) {
          if (e.toString().contains('already been given')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${e.toString()}'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setState(() {
              _isSubmitting = false;
            });
            return;
          }
        }
      }

      String? paymentIntentId;
      if (hasTip) {
        try {
          final clientSecret = await tripProvider.processTipPayment(_selectedTip!, widget.bookingId);

          if (clientSecret != null) {
            await Stripe.instance.initPaymentSheet(
              paymentSheetParameters: SetupPaymentSheetParameters(
                paymentIntentClientSecret: clientSecret,
                merchantDisplayName: 'MyGoBuddy',
                style: ThemeMode.system,
              ),
            );

            await Stripe.instance.presentPaymentSheet();

            paymentIntentId = clientSecret.split('_secret_')[0];

            final paymentConfirmed = await tripProvider.confirmTipPayment(paymentIntentId, widget.bookingId);

            if (!paymentConfirmed) {
              throw Exception('Tip payment confirmation failed');
            }
          } else {
            throw Exception('Failed to create tip payment');
          }
        } catch (e) {
          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(AppLocalizations.of(context).translate('paymentFailed')),
              content: Text(AppLocalizations.of(context).translate('continueWithoutTip')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(AppLocalizations.of(context).translate('cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(AppLocalizations.of(context).translate('continueWithoutTip')),
                ),
              ],
            ),
          );

          if (shouldContinue != true) {
            setState(() {
              _isSubmitting = false;
            });
            return;
          }

          _selectedTip = null;
        }
      }

      if (hasReview && _rating > 0) {
        if (_isEditing) {
          await tripProvider.updateReview(
            reviewId: widget.existingReview!['id'],
            rating: _rating,
            reviewText: _reviewController.text.trim().isNotEmpty ? _reviewController.text.trim() : null,
            reviewImages: _selectedImages.isNotEmpty ? _selectedImages : null,
            bookingId: widget.bookingId,
          );
        } else {
          await tripProvider.submitReviewAndTip(
            bookingId: widget.bookingId,
            rating: _rating,
            reviewText: _reviewController.text.trim().isNotEmpty ? _reviewController.text.trim() : null,
            reviewImages: _selectedImages.isNotEmpty ? _selectedImages : null,
            tipAmount: null, // Don't pass tip amount since it's already processed
          );
        }
      } else if (hasTip && !hasReview) {
        // For now, we'll skip review submission if no rating is provided
        // The tip was already processed above
      }

      Navigator.of(context).pop(true);

      String successMessage;
      if (_isEditing) {
        successMessage = AppLocalizations.of(context).translate('reviewUpdatedSuccessfully');
      } else if (hasReview && hasTip) {
        successMessage = AppLocalizations.of(context).translate('reviewAndTipSubmitted');
      } else if (hasReview) {
        successMessage = AppLocalizations.of(context).translate('reviewSubmittedSuccessfully');
      } else {
        successMessage = AppLocalizations.of(context).translate('tipSentSuccessfully');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
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
                behavior: SnackBarBehavior.floating,
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
          behavior: SnackBarBehavior.floating,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Color(0xFF475569)),
        ),
        title: Text(
          _isEditing
              ? AppLocalizations.of(context).translate('editReview')
              : AppLocalizations.of(context).translate('leaveReview'),
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: NetworkImage(widget.buddyImage),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.buddyName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.serviceName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).translate('rateYourExperience'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return GestureDetector(
                            onTap: () => setState(() => _rating = index + 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                index < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                size: 44,
                                color: index < _rating
                                    ? const Color(0xFFFBBF24)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    if (_rating > 0) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _getRatingText(_rating),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).translate('shareYourExperience'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reviewController,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).translate('writeYourReview'),
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).translate('addPhotos'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickImages,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFE2E8F0),
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFF8FAFC),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _selectedImages.isEmpty ? Icons.add_photo_alternate_outlined : Icons.photo_library_outlined,
                              size: 40,
                              color: const Color(0xFF059669),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedImages.isEmpty
                                  ? AppLocalizations.of(context).translate('uploadPhoto')
                                  : '${_selectedImages.length} ${AppLocalizations.of(context).translate('photosSelected')}',
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
                            if (_selectedImages.isEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context).translate('optionalUpToFivePhotos'),
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_selectedImages.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedImages.length,
                          itemBuilder: (context, index) {
                            return Container(
                              margin: const EdgeInsets.only(right: 12),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _selectedImages[index],
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedImages.removeAt(index);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.favorite_outline,
                          color: Color(0xFF059669),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context).translate('addTip'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context).translate('showAppreciationOptional'),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),

                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      children: _presetTips.map((amount) {
                        final isSelected = _selectedTip == amount;
                        return GestureDetector(
                          onTap: () => _selectTip(amount),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFF8FAFC),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFE2E8F0),
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                '\$${amount.toInt()}',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: _customTipController,
                      keyboardType: TextInputType.number,
                      onChanged: _onCustomTipChanged,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).translate('customAmount'),
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        prefixText: '\$ ',
                        prefixStyle: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : Text(
                    _isEditing
                        ? AppLocalizations.of(context).translate('updateReview')
                        : AppLocalizations.of(context).translate('submitFeedback'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return AppLocalizations.of(context).translate('poor');
      case 2:
        return AppLocalizations.of(context).translate('fair');
      case 3:
        return AppLocalizations.of(context).translate('good');
      case 4:
        return AppLocalizations.of(context).translate('veryGood');
      case 5:
        return AppLocalizations.of(context).translate('excellent');
      default:
        return '';
    }
  }
}
