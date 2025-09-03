import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/verification_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';

class BuddyProfileSetupScreen extends StatefulWidget {
  const BuddyProfileSetupScreen({super.key});
  @override
  State<BuddyProfileSetupScreen> createState() =>
      _BuddyProfileSetupScreenState();
}

class _BuddyProfileSetupScreenState extends State<BuddyProfileSetupScreen> {
  final TextEditingController _experienceController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _isLoading = false;

  // State for the custom dropdown
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isDropdownOpen = false;
  List<Map<String, String>> _selectedServices = [];
  List<Map<String, dynamic>> _services = [];
  bool _isFetchingServices = true;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  @override
  void dispose() {
    _removeOverlay();
    _experienceController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _fetchServices() async {
    try {
      final response = await supabase
          .from('services')
          .select('id, name, name_key, service_rates')
          .order('id');
      // Convert service_rates to string if it is not already
      response.forEach((service) {
        if (service['service_rates'] is double) {
          service['service_rates'] = service['service_rates'].toString();
        }
      });
      if (mounted) {
        setState(() {
          _services = response;
          _isFetchingServices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        context.showSnackBar(
          localizations.translate('buddy_setup_error_fetching_services',
              args: {'error': e.toString()}),
          isError: true,
        );
        setState(() {
          _isFetchingServices = false;
        });
      }
    }
  }

  Future<void> _saveAndContinue() async {
    final localizations = AppLocalizations.of(context);
    // Basic validation (location check removed)
    if (_selectedServices.isEmpty ||
        _experienceController.text.trim().isEmpty ||
        _bioController.text.trim().isEmpty) {
      context.showSnackBar(
        localizations.translate('buddy_setup_validation_fill_all_fields'),
        isError: true,
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = supabase.auth.currentUser!.id;
      // Fetch all necessary data from the profiles table, including lat/lng
      final profileData = await supabase
          .from('profiles')
          .select(
          'name, profile_picture, languages_spoken, country, location, latitude, longitude')
          .eq('id', userId)
          .single();
      final languagesStr = profileData['languages_spoken'] as String?;
      List<String> languagesList = [];
      if (languagesStr != null && languagesStr.isNotEmpty) {
        languagesList = languagesStr.split(', ').toList();
      }

      final updates = {
        'id': userId,
        'name': profileData['name'],
        'profile_picture': profileData['profile_picture'],
        'location': profileData['location'],
        'latitude': profileData['latitude'],
        'longitude': profileData['longitude'],
        'experience_level': _experienceController.text.trim(),
        'bio': _bioController.text.trim(),
        'languages': languagesList,
        'profileComplete': true,
        'verified': false, // Default verification status
        'updated_at': DateTime.now().toIso8601String(),
        'country': profileData['country'],
        'tier': 'standard',
      };
      await supabase.from('buddies').upsert(updates);

      // First, delete any existing buddy services for this user
      await supabase.from('buddy_services').delete().eq('buddy_id', userId);

      // Then insert the new services
      final List<Map<String, dynamic>> buddyServicesData = [];
      for (var selectedService in _selectedServices) {
        final serviceName = selectedService['name']!;
        final matchingService = _services.firstWhere(
              (s) => s['name'] == serviceName,
          orElse: () => throw Exception('Service $serviceName not found'),
        );

        // Get the service ID and rate
        final serviceId = matchingService['id'] ?? matchingService['name_key']; // Fallback to name_key if id not available
        final rate = matchingService['service_rates'];
        double hourlyRate;

        if (rate is double) {
          hourlyRate = rate;
        } else if (rate is String) {
          try {
            hourlyRate = double.parse(rate);
          } catch (e) {
            throw Exception('Invalid rate for service $serviceName: $rate');
          }
        } else {
          throw Exception('Invalid rate type for service $serviceName: $rate');
        }

        buddyServicesData.add({
          'buddy_id': userId,
          'service_id': serviceId,
          'hourly_rate': hourlyRate,
          'is_active': true,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      if (buddyServicesData.isNotEmpty) {
        await supabase.from('buddy_services').insert(buddyServicesData);
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const VerificationScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
          localizations.translate('buddy_setup_error_saving_profile',
              args: {'error': e.toString()}),
          isError: true,
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

  void _toggleDropdown() {
    if (_isFetchingServices) return;
    if (_isDropdownOpen) {
      _removeOverlay();
    } else {
      _createOverlay();
    }
    setState(() {
      _isDropdownOpen = !_isDropdownOpen;
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _createOverlay() {
    _removeOverlay();
    assert(_overlayEntry == null);
    final localizations = AppLocalizations.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: _layerLink.leaderSize?.width,
          child: CompositedTransformFollower(
            link: _layerLink,
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
                children: _services.map((service) {
                  final bool isSelected = _selectedServices
                      .any((s) => s['name_key'] == service['name_key']);
                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedServices.removeWhere(
                                  (s) => s['name_key'] == service['name_key']);
                        } else {
                          _selectedServices.add({
                            'name': service['name'] as String,
                            'name_key': service['name_key'] as String
                          });
                        }
                      });
                      _createOverlay();
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
                          localizations.translate(service['name_key']),
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
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF19638D);
    const Color accentColor = Color(0xFFF15808);
    const Color backgroundColor = Color(0xFFF8F8F8);
    final localizations = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: GestureDetector(
        onTap: () {
          if (_isDropdownOpen) {
            _toggleDropdown();
          }
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          backgroundColor: backgroundColor,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          Text(
                            'Complete Your Profile',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                color: primaryColor,
                                fontSize: 24,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 40),
                          // Form Fields
                          _buildDropdownField(localizations),
                          const SizedBox(height: 18),
                          _buildProfileTextField(
                            controller: _experienceController,
                            icon: Icons.star_border,
                            label: localizations
                                .translate('buddy_setup_experience_label'),
                            hint: localizations
                                .translate('buddy_setup_experience_hint'),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 18),
                          _buildProfileTextField(
                            controller: _bioController,
                            icon: Icons.edit_outlined,
                            label:
                            localizations.translate('buddy_setup_bio_label'),
                            hint: '',
                            maxLines: 5,
                          ),
                          const SizedBox(height: 18),
                          const SizedBox(
                              height:
                              24), // Space at the bottom of scroll view
                        ],
                      ),
                    ),
                  ),
                ),
                // Fixed Action Buttons at the bottom
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: const BorderSide(color: accentColor),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                              localizations.translate('buddy_setup_button_back'),
                              style: GoogleFonts.poppins(
                                  color: accentColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveAndContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                              : Text(
                              localizations
                                  .translate('buddy_setup_button_save'),
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField(AppLocalizations localizations) {
    final translatedServiceNames = _selectedServices
        .map((s) => localizations.translate(s['name_key']!))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.room_service_outlined,
                color: Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(localizations.translate('buddy_setup_services_label'),
                style: GoogleFonts.poppins(
                    color: const Color(0xFF292D32),
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        CompositedTransformTarget(
          link: _layerLink,
          child: GestureDetector(
            onTap: _toggleDropdown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _isDropdownOpen
                        ? const Color(0xFF19638D)
                        : Colors.grey.shade300,
                    width: _isDropdownOpen ? 1.5 : 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _isFetchingServices
                        ? Row(
                      children: [
                        const SizedBox(
                          height: 16,
                          width: 16,
                          child:
                          CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          localizations
                              .translate('buddy_setup_services_fetching'),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    )
                        : Text(
                      _selectedServices.isEmpty
                          ? localizations
                          .translate('buddy_setup_services_select')
                          : translatedServiceNames.join(', '),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: _selectedServices.isEmpty
                            ? Colors.grey[400]
                            : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _isDropdownOpen
                        ? Icons.arrow_drop_up
                        : Icons.arrow_drop_down,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTextField({
    required IconData icon,
    required String label,
    String? hint,
    int maxLines = 1,
    TextEditingController? controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.poppins(
                    color: const Color(0xFF292D32),
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.poppins(
            color: const Color(0xFF292D32),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
            GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                BorderSide(color: Colors.grey.shade300, width: 0.5)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                BorderSide(color: Colors.grey.shade300, width: 0.5)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                const BorderSide(color: Color(0xFF19638D), width: 1.5)),
          ),
        ),
      ],
    );
  }
}
