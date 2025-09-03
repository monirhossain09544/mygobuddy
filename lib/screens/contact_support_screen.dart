import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/cupertino.dart';

class ContactSupportScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialSubject;

  const ContactSupportScreen({
    super.key,
    this.initialCategory,
    this.initialSubject,
  });

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCategory = 'General';
  String _selectedPriority = 'Medium';
  bool _isSubmitting = false;

  final LayerLink _categoryLayerLink = LayerLink();
  final LayerLink _priorityLayerLink = LayerLink();
  OverlayEntry? _categoryOverlayEntry;
  OverlayEntry? _priorityOverlayEntry;
  bool _isCategoryDropdownOpen = false;
  bool _isPriorityDropdownOpen = false;

  final List<String> _categories = [
    'General',
    'Payment',
    'Technical',
  ];

  final List<String> _priorities = ['Medium'];

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      switch (widget.initialCategory) {
        case 'account_issues':
          _selectedCategory = 'General';
          break;
        case 'payment_issues':
          _selectedCategory = 'Payment';
          break;
        case 'technical_support':
          _selectedCategory = 'Technical';
          break;
        default:
          _selectedCategory = 'General';
      }
    }
    if (widget.initialSubject != null) {
      _subjectController.text = widget.initialSubject!;
    }
  }

  @override
  void dispose() {
    _removeCategoryOverlay();
    _removePriorityOverlay();
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _toggleCategoryDropdown() {
    if (_isCategoryDropdownOpen) {
      _removeCategoryOverlay();
    } else {
      _removePriorityOverlay(); // Close other dropdown
      _createCategoryOverlay();
    }
    setState(() {
      _isCategoryDropdownOpen = !_isCategoryDropdownOpen;
      _isPriorityDropdownOpen = false;
    });
  }

  void _togglePriorityDropdown() {
    if (_isPriorityDropdownOpen) {
      _removePriorityOverlay();
    } else {
      _removeCategoryOverlay(); // Close other dropdown
      _createPriorityOverlay();
    }
    setState(() {
      _isPriorityDropdownOpen = !_isPriorityDropdownOpen;
      _isCategoryDropdownOpen = false;
    });
  }

  void _removeCategoryOverlay() {
    _categoryOverlayEntry?.remove();
    _categoryOverlayEntry = null;
  }

  void _removePriorityOverlay() {
    _priorityOverlayEntry?.remove();
    _priorityOverlayEntry = null;
  }

  void _createCategoryOverlay() {
    _removeCategoryOverlay();
    final localizations = AppLocalizations.of(context);

    _categoryOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: _categoryLayerLink.leaderSize?.width,
          child: CompositedTransformFollower(
            link: _categoryLayerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 8.0),
            child: Material(
              elevation: 4.0,
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _categories.map((category) {
                  final bool isSelected = category == _selectedCategory;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategory = category;
                      });
                      _toggleCategoryDropdown();
                    },
                    child: Container(
                      color: isSelected
                          ? const Color(0xFF19638D)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          category,
                          style: GoogleFonts.poppins(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_categoryOverlayEntry!);
  }

  void _createPriorityOverlay() {
    _removePriorityOverlay();
    final localizations = AppLocalizations.of(context);

    _priorityOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: _priorityLayerLink.leaderSize?.width,
          child: CompositedTransformFollower(
            link: _priorityLayerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 8.0),
            child: Material(
              elevation: 4.0,
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _priorities.map((priority) {
                  final bool isSelected = priority == _selectedPriority;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPriority = priority;
                      });
                      _togglePriorityDropdown();
                    },
                    child: Container(
                      color: isSelected
                          ? const Color(0xFF19638D)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _getPriorityColor(priority),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              priority,
                              style: GoogleFonts.poppins(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_priorityOverlayEntry!);
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final localizations = AppLocalizations.of(context);

      final user = Supabase.instance.client.auth.currentUser;
      final now = DateTime.now().toIso8601String();

      // Generate ticket number
      final ticketNumber = 'TKT${DateTime.now().millisecondsSinceEpoch}';

      // Get user profile info
      String userName = 'Anonymous User';
      String userEmail = user?.email ?? 'no-email@example.com';
      String userType = 'Client';

      if (user != null) {
        try {
          final profileResponse = await Supabase.instance.client
              .from('profiles')
              .select('name, role')
              .eq('id', user.id)
              .single();

          userName = profileResponse['name'] ?? 'Anonymous User';
          userType = profileResponse['role'] == 'buddy' ? 'Buddy' : 'Client';
        } catch (e) {
          print('[v0] Profile fetch error: $e');
          // Use default values if profile fetch fails
        }
      }

      final ticketData = {
        'ticket_number': ticketNumber,
        'subject': _subjectController.text.trim(),
        'description': _descriptionController.text.trim(),
        'user_id': user?.id,
        'user_name': userName,
        'user_email': userEmail,
        'user_type': userType,
        'category': _selectedCategory,
        'status': 'Open',
        'priority': _selectedPriority,
        'created_at': now,
        'updated_at': now,
      };

      print('[v0] Submitting ticket with data: $ticketData');

      await Supabase.instance.client.from('support_tickets').insert(ticketData);

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.translate('support_ticket_submitted_success')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // Navigate back
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('[v0] Support ticket submission error: $e');
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.translate('support_ticket_submit_error')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    const Color primaryColor = Color(0xFF19638D);
    const Color accentColor = Color(0xFFF15808);
    const Color backgroundColor = Color(0xFFF9FAFB);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: GestureDetector(
        onTap: () {
          if (_isCategoryDropdownOpen) {
            _toggleCategoryDropdown();
          }
          if (_isPriorityDropdownOpen) {
            _togglePriorityDropdown();
          }
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(
            backgroundColor: backgroundColor,
            surfaceTintColor: backgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF111827), size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              localizations.translate('contact_support_title'),
              style: GoogleFonts.poppins(
                color: const Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20.0),
              children: [
                // Header message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: primaryColor, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          localizations.translate('contact_support_header_message'),
                          style: GoogleFonts.poppins(
                            color: primaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Category selection
                Text(
                  localizations.translate('support_category_label'),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                CompositedTransformTarget(
                  link: _categoryLayerLink,
                  child: GestureDetector(
                    onTap: _toggleCategoryDropdown,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isCategoryDropdownOpen
                              ? const Color(0xFF19638D)
                              : Colors.grey.shade300,
                          width: _isCategoryDropdownOpen ? 1.5 : 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedCategory,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          Icon(
                            _isCategoryDropdownOpen
                                ? Icons.arrow_drop_up
                                : Icons.arrow_drop_down,
                            color: Colors.grey[600],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Priority selection
                Text(
                  localizations.translate('support_priority_label'),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                CompositedTransformTarget(
                  link: _priorityLayerLink,
                  child: GestureDetector(
                    onTap: _togglePriorityDropdown,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isPriorityDropdownOpen
                              ? const Color(0xFF19638D)
                              : Colors.grey.shade300,
                          width: _isPriorityDropdownOpen ? 1.5 : 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getPriorityColor(_selectedPriority),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _selectedPriority,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            _isPriorityDropdownOpen
                                ? Icons.arrow_drop_up
                                : Icons.arrow_drop_down,
                            color: Colors.grey[600],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Subject field
                Text(
                  localizations.translate('support_subject_label'),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _subjectController,
                  decoration: InputDecoration(
                    hintText: localizations.translate('support_subject_hint'),
                    hintStyle: GoogleFonts.poppins(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: primaryColor, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  style: GoogleFonts.poppins(fontSize: 14),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return localizations.translate('support_subject_required');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Description field
                Text(
                  localizations.translate('support_description_label'),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: localizations.translate('support_description_hint'),
                    hintStyle: GoogleFonts.poppins(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: primaryColor, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  style: GoogleFonts.poppins(fontSize: 14),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return localizations.translate('support_description_required');
                    }
                    if (value.trim().length < 10) {
                      return localizations.translate('support_description_too_short');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitTicket,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
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
                      localizations.translate('support_submit_button'),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'low':
        return Colors.green;
      case 'Medium':
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      case 'urgent':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
