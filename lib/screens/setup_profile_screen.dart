import 'dart:io';
import 'dart:ui';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:language_picker/languages.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/buddy_profile_setup_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class SetupProfileScreen extends StatefulWidget {
  final bool isBuddy;
  const SetupProfileScreen({super.key, required this.isBuddy});
  @override
  State<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends State<SetupProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _languagesController = TextEditingController();
  String? _avatarUrl;
  XFile? _imageFile;
  bool _isLoading = false;
  bool _isDetectingLocation = false;
  String? _country;

  double? _detectedLatitude;
  double? _detectedLongitude;

  Country _selectedCountry = Country(
    phoneCode: '1',
    countryCode: 'US',
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: 'United States',
    example: '2015550123',
    displayName: 'United States (US) [+1]',
    displayNameNoCountryCode: 'United States (US)',
    e164Key: '1-US-0',
  );
  final List<Language> _selectedLanguages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getProfile();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _languagesController.dispose();
    super.dispose();
  }

  Future<void> _getProfile() async {
    setState(() {
      _isLoading = true;
    });
    final localizations = AppLocalizations.of(context)!;
    try {
      final userId = supabase.auth.currentUser!.id;
      final data = await supabase
          .from('profiles')
          .select(
          'name, profile_picture, phone_number, location, languages_spoken, country, latitude, longitude')
          .eq('id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        _nameController.text = data['name'] ?? '';
        _locationController.text = data['location'] ?? '';
        _avatarUrl = data['profile_picture'];
        _country = data['country'];
        _detectedLatitude = data['latitude'];
        _detectedLongitude = data['longitude'];

        final fullPhoneNumber = data['phone_number'] as String?;
        if (fullPhoneNumber != null && fullPhoneNumber.startsWith('+')) {
          const List<String> desiredCountryCodes = [
            'US',
            'CA',
            'GB',
            'ES',
            'DE',
            'FR',
            'IN'
          ];
          final List<Country> availableCountries = CountryService()
              .getAll()
              .where((country) =>
              desiredCountryCodes.contains(country.countryCode))
              .toList();
          availableCountries.sort((a, b) {
            final lengthCompare =
            b.phoneCode.length.compareTo(a.phoneCode.length);
            if (lengthCompare != 0) return lengthCompare;
            if (a.phoneCode == '1') {
              if (a.countryCode == 'US') return -1;
              if (b.countryCode == 'US') return 1;
            }
            return a.name.compareTo(b.name);
          });
          Country? matchedCountry;
          String numberPart = '';
          for (final country in availableCountries) {
            if (fullPhoneNumber.substring(1).startsWith(country.phoneCode)) {
              matchedCountry = country;
              numberPart =
                  fullPhoneNumber.substring(1 + country.phoneCode.length);
              break;
            }
          }
          if (matchedCountry != null) {
            _selectedCountry = matchedCountry;
            _phoneController.text = numberPart;
          } else {
            _phoneController.text = fullPhoneNumber;
          }
        } else {
          _phoneController.text = fullPhoneNumber ?? '';
        }
        final languagesStr = data['languages_spoken'] as String?;
        if (languagesStr != null && languagesStr.isNotEmpty) {
          final languageNames = languagesStr.split(', ');
          _selectedLanguages.clear();
          for (var name in languageNames) {
            try {
              _selectedLanguages.add(Languages.defaultLanguages
                  .firstWhere((lang) => lang.name == name));
            } catch (e) {
              // Language not found, ignore
            }
          }
          _languagesController.text =
              _selectedLanguages.map((l) => l.name).join(', ');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(localizations.translate('error_fetch_profile'),
            isError: true);
        print('Error fetching profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
    );
    if (image != null) {
      setState(() {
        _imageFile = image;
      });
    }
  }

  Future<void> _updateProfileAndContinue() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = supabase.auth.currentUser!.id;
      String? imageUrl;
      if (_imageFile != null) {
        final bytes = await _imageFile!.readAsBytes();
        final fileExt = _imageFile!.path.split('.').last;
        final fileName = '${DateTime.now().toIso8601String()}.$fileExt';
        final filePath = '$userId/$fileName';
        await supabase.storage.from('profile-pictures').uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(contentType: _imageFile!.mimeType),
        );
        imageUrl =
            supabase.storage.from('profile-pictures').getPublicUrl(filePath);
      }

      final updates = {
        'id': userId,
        'name': _nameController.text.trim(),
        'location': _locationController.text.trim(),
        if (_detectedLatitude != null) 'latitude': _detectedLatitude,
        if (_detectedLongitude != null) 'longitude': _detectedLongitude,
        'phone_number':
        '+${_selectedCountry.phoneCode}${_phoneController.text.trim()}',
        'languages_spoken':
        _selectedLanguages.map((l) => l.name).join(', '),
        'updated_at': DateTime.now().toIso8601String(),
        'is_buddy': widget.isBuddy,
        'role': widget.isBuddy ? 'buddy' : 'client', // Set proper role
        'country': _country,
      };
      if (imageUrl != null) {
        updates['profile_picture'] = imageUrl;
      }
      await supabase.from('profiles').upsert(updates);
      if (mounted) {
        if (widget.isBuddy) {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (context) => const BuddyProfileSetupScreen()),
          );
        } else {
          _showSuccessDialog(localizations);
        }
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
            '${localizations.translate('error_update_profile')}: ${e.toString()}',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessDialog(AppLocalizations localizations) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.of(context).pop();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainScreen()),
                (Route<dynamic> route) => false,
          );
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
                    localizations.translate('setup_profile_success_title_1'),
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    localizations.translate('setup_profile_success_title_2'),
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

  Future<void> _handleAutoDetectLocation() async {
    final localizations = AppLocalizations.of(context)!;
    FocusScope.of(context).unfocus();
    setState(() {
      _isDetectingLocation = true;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          context.showSnackBar(
              localizations.translate('error_location_disabled'),
              isError: true);
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            context.showSnackBar(
                localizations.translate('error_location_denied'),
                isError: true);
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          context.showSnackBar(
              localizations.translate('error_location_denied_forever'),
              isError: true);
        }
        return;
      }
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks =
      await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = [
          place.street,
          place.locality,
          place.country,
        ].where((part) => part != null && part.isNotEmpty).join(', ');
        _locationController.text = address;
        setState(() {
          _country = place.country;
          _detectedLatitude = position.latitude;
          _detectedLongitude = position.longitude;
        });
      } else {
        if (mounted) {
          context.showSnackBar(
              localizations.translate('error_location_no_address'),
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
            '${localizations.translate('error_location_failed')}: ${e.toString()}',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDetectingLocation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF19638D);
    const Color accentColor = Color(0xFFF15808);
    const Color backgroundColor = Color(0xFFF8F8F8);
    final localizations = AppLocalizations.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    localizations.translate('setup_profile_title'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: primaryColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 30),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _imageFile != null
                              ? FileImage(File(_imageFile!.path))
                              : (_avatarUrl != null
                              ? NetworkImage(_avatarUrl!)
                              : null) as ImageProvider?,
                          child: _imageFile == null && _avatarUrl == null
                              ? Icon(
                            Icons.camera_alt,
                            color: Colors.grey[400],
                            size: 30,
                          )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.edit,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    localizations.translate('setup_profile_subtitle'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildProfileTextField(
                    controller: _nameController,
                    icon: Icons.person_outline,
                    label: localizations
                        .translate('setup_profile_fullname_label'),
                  ),
                  const SizedBox(height: 18),
                  _buildPhoneNumberField(localizations),
                  const SizedBox(height: 18),
                  _buildLocationField(localizations),
                  const SizedBox(height: 18),
                  _buildLanguagesField(localizations),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 260,
                    child: ElevatedButton(
                      onPressed: _updateProfileAndContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        padding:
                        const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        widget.isBuddy
                            ? localizations
                            .translate('button_save_continue')
                            : localizations.translate('button_save'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
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
              borderSide: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationField(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.location_on_outlined,
                color: Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(
              localizations.translate('setup_profile_location_label'),
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _locationController,
          style: GoogleFonts.poppins(
            color: const Color(0xFF292D32),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: localizations.translate('setup_profile_location_hint'),
            hintStyle:
            GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _isDetectingLocation
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Color(0xFF19638D)),
              )
                  : IconButton(
                icon: Icon(Icons.my_location, color: Colors.grey[600]),
                onPressed: _handleAutoDetectLocation,
              ),
            ),
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 4, 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneNumberField(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.phone_outlined, color: Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(
              localizations.translate('setup_profile_phone_label'),
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: GoogleFonts.poppins(
            color: const Color(0xFF292D32),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: localizations.translate('setup_profile_phone_hint'),
            hintStyle:
            GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            prefixIcon: GestureDetector(
              onTap: () => _showCountryPickerIOS(localizations),
              child: Padding(
                padding: const EdgeInsets.only(left: 15.0, right: 10.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedCountry.flagEmoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                  ],
                ),
              ),
            ),
            prefixText: '+${_selectedCountry.phoneCode} ',
            prefixStyle: GoogleFonts.poppins(
              color: const Color(0xFF292D32),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _showCountryPickerIOS(AppLocalizations localizations) {
    FocusScope.of(context).unfocus();
    const List<String> desiredCountryCodes = [
      'US',
      'CA',
      'GB',
      'ES',
      'DE',
      'FR',
      'IN'
    ];
    final List<Country> filteredCountries = CountryService()
        .getAll()
        .where((country) => desiredCountryCodes.contains(country.countryCode))
        .toList();
    filteredCountries.sort((a, b) => a.name.compareTo(b.name));
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return _CupertinoCountryPickerSheet(
          localizations: localizations,
          initialCountry: _selectedCountry,
          countries: filteredCountries,
          onCountrySelected: (country) {
            setState(() {
              _selectedCountry = country;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              FocusScope.of(context).unfocus();
            });
          },
        );
      },
    );
  }

  void _showLanguagePickerIOS(AppLocalizations localizations) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: _CupertinoLanguageSheet(
          localizations: localizations,
          initialLanguages: _selectedLanguages,
          onDone: (selected) {
            setState(() {
              _selectedLanguages.clear();
              _selectedLanguages.addAll(selected);
              _languagesController.text =
                  _selectedLanguages.map((l) => l.name).join(', ');
            });
          },
        ),
      ),
    );
  }

  Widget _buildLanguagesField(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.translate, color: Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(
              localizations.translate('setup_profile_languages_label'),
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showLanguagePickerIOS(localizations),
          child: AbsorbPointer(
            child: TextFormField(
              controller: _languagesController,
              maxLines: null,
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText:
                localizations.translate('setup_profile_languages_hint'),
                hintStyle:
                GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                suffixIcon:
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: Colors.grey.shade300, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: Colors.grey.shade300, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: Color(0xFF19638D), width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CupertinoLanguageSheet extends StatefulWidget {
  final List<Language> initialLanguages;
  final Function(List<Language>) onDone;
  final AppLocalizations localizations;

  const _CupertinoLanguageSheet({
    Key? key,
    required this.initialLanguages,
    required this.onDone,
    required this.localizations,
  }) : super(key: key);

  @override
  _CupertinoLanguageSheetState createState() => _CupertinoLanguageSheetState();
}

class _CupertinoLanguageSheetState extends State<_CupertinoLanguageSheet> {
  late List<Language> _tempSelectedLanguages;
  List<Language> _filteredLanguages = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tempSelectedLanguages = List.from(widget.initialLanguages);
    _filteredLanguages = Languages.defaultLanguages;
    _searchController.addListener(_filterLanguages);
  }

  void _filterLanguages() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredLanguages = query.isEmpty
          ? Languages.defaultLanguages
          : Languages.defaultLanguages
          .where((lang) =>
      lang.name.toLowerCase().contains(query) ||
          lang.isoCode.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredLanguages.length,
              itemBuilder: (context, index) {
                final language = _filteredLanguages[index];
                final isSelected = _tempSelectedLanguages
                    .any((l) => l.isoCode == language.isoCode);
                return _buildLanguageItem(language, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: CupertinoColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 60), // Spacer
          Text(
            widget.localizations.translate('picker_languages_title'),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 17,
              color: CupertinoColors.black,
            ),
          ),
          CupertinoButton(
            child: Text(widget.localizations.translate('picker_done'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              widget.onDone(_tempSelectedLanguages);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: CupertinoSearchTextField(
        controller: _searchController,
        placeholder: widget.localizations.translate('picker_search'),
      ),
    );
  }

  Widget _buildLanguageItem(Language language, bool isSelected) {
    return Material(
      color: CupertinoColors.white,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _tempSelectedLanguages
                  .removeWhere((l) => l.isoCode == language.isoCode);
            } else {
              _tempSelectedLanguages.add(language);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: CupertinoColors.separator, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              if (isSelected)
                const Icon(CupertinoIcons.check_mark,
                    color: CupertinoColors.activeBlue)
              else
                const SizedBox(width: 22), // To align text
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  language.name,
                  style: const TextStyle(
                    color: CupertinoColors.black,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CupertinoCountryPickerSheet extends StatefulWidget {
  final Country initialCountry;
  final List<Country> countries;
  final Function(Country) onCountrySelected;
  final AppLocalizations localizations;

  const _CupertinoCountryPickerSheet({
    Key? key,
    required this.initialCountry,
    required this.countries,
    required this.onCountrySelected,
    required this.localizations,
  }) : super(key: key);

  @override
  _CupertinoCountryPickerSheetState createState() =>
      _CupertinoCountryPickerSheetState();
}

class _CupertinoCountryPickerSheetState
    extends State<_CupertinoCountryPickerSheet> {
  late Country _tempSelectedCountry;

  @override
  void initState() {
    super.initState();
    int initialIndex = widget.countries
        .indexWhere((c) => c.countryCode == widget.initialCountry.countryCode);
    if (initialIndex == -1) {
      initialIndex =
          widget.countries.indexWhere((c) => c.countryCode == 'US');
    }
    if (initialIndex == -1) {
      initialIndex = 0;
    }
    _tempSelectedCountry = widget.countries[initialIndex];
  }

  @override
  Widget build(BuildContext context) {
    final double sheetHeight = (widget.countries.length * 45.0) + 100;
    final double maxHeight = MediaQuery.of(context).size.height * 0.5;
    return Container(
      height: sheetHeight < maxHeight ? sheetHeight : maxHeight,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              color: CupertinoColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text(widget.localizations.translate('picker_cancel')),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    widget.localizations.translate('picker_country_title'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                      color: CupertinoColors.black,
                    ),
                  ),
                  CupertinoButton(
                    child: Text(widget.localizations.translate('picker_done'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      widget.onCountrySelected(_tempSelectedCountry);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.countries.length,
                itemBuilder: (context, index) {
                  final country = widget.countries[index];
                  final isSelected =
                      country.countryCode == _tempSelectedCountry.countryCode;
                  return Material(
                    color: CupertinoColors.white,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _tempSelectedCountry = country;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: CupertinoColors.separator, width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (isSelected)
                              const Icon(CupertinoIcons.check_mark,
                                  color: CupertinoColors.activeBlue)
                            else
                              const SizedBox(width: 22),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                '${country.flagEmoji} ${country.name}',
                                style: const TextStyle(
                                  color: CupertinoColors.black,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            Text(
                              '+${country.phoneCode}',
                              style: const TextStyle(
                                color: CupertinoColors.secondaryLabel,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
