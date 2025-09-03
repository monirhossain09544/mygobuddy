import 'dart:io';
import 'dart:ui';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:language_picker/languages.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _languagesController = TextEditingController();
  String? _avatarUrl;
  XFile? _imageFile;
  bool _isUpdating = false;
  bool _isDetectingLocation = false;
  bool _isInitialized = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final profileProvider = context.read<ProfileProvider>();
      if (profileProvider.profileData != null) {
        _initializeForm(profileProvider.profileData!);
        _isInitialized = true;
      }
    }
  }

  void _initializeForm(Map<String, dynamic> data) {
    // Use the correct field names from your database schema
    _nameController.text = data['name'] ?? '';
    _locationController.text = data['location'] ?? '';
    _avatarUrl = data['profile_picture'];

    // Parse phone number
    final fullPhoneNumber = data['phone_number'] as String?;
    if (fullPhoneNumber != null && fullPhoneNumber.startsWith('+')) {
      const List<String> desiredCountryCodes = [
        'US', 'CA', 'GB', 'ES', 'DE', 'FR', 'IN'
      ];
      final List<Country> availableCountries = CountryService()
          .getAll()
          .where((country) => desiredCountryCodes.contains(country.countryCode))
          .toList();

      availableCountries.sort((a, b) {
        final lengthCompare = b.phoneCode.length.compareTo(a.phoneCode.length);
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

    // Parse languages
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

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _languagesController.dispose();
    super.dispose();
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

  Future<void> _updateProfile() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _isUpdating = true;
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

      // Use the correct field names that match your database schema
      final updates = {
        'name': _nameController.text.trim(),
        'location': _locationController.text.trim(),
        if (_detectedLatitude != null) 'latitude': _detectedLatitude,
        if (_detectedLongitude != null) 'longitude': _detectedLongitude,
        'phone_number': '+${_selectedCountry.phoneCode}${_phoneController.text.trim()}',
        'languages_spoken': _selectedLanguages.map((l) => l.name).join(', '),
      };

      if (imageUrl != null) {
        updates['profile_picture'] = imageUrl;
      }

      // Use the ProfileProvider's updateProfile method
      await context.read<ProfileProvider>().updateProfile(updates);

      if (mounted) {
        context.showSnackBar(l.translate('editProfile.updateSuccess'));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('${l.translate('editProfile.updateError')}: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _handleAutoDetectLocation() async {
    final l = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _isDetectingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          context.showSnackBar(l.translate('editProfile.locationServicesDisabled'), isError: true);
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            context.showSnackBar(l.translate('editProfile.locationPermissionDenied'), isError: true);
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          context.showSnackBar(l.translate('editProfile.locationPermissionDeniedPermanently'),
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
        String address =
            '${place.street ?? ''}, ${place.locality ?? ''}, ${place.postalCode ?? ''}, ${place.country ?? ''}';
        _locationController.text = address.replaceAll(RegExp(r'^, | ,'), '');

        _detectedLatitude = position.latitude;
        _detectedLongitude = position.longitude;
      } else {
        if (mounted) {
          context.showSnackBar(l.translate('editProfile.addressNotFound'), isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('${l.translate('editProfile.locationError')}: ${e.toString()}',
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

  void _showCountryPickerIOS() {
    final l = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    const List<String> desiredCountryCodes = [
      'US', 'CA', 'GB', 'ES', 'DE', 'FR', 'IN'
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
          l: l,
        );
      },
    );
  }

  void _showLanguagePickerIOS() {
    final l = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: _CupertinoLanguageSheet(
          initialLanguages: _selectedLanguages,
          onDone: (selected) {
            setState(() {
              _selectedLanguages.clear();
              _selectedLanguages.addAll(selected);
              _languagesController.text =
                  _selectedLanguages.map((l) => l.name).join(', ');
            });
          },
          l: l,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color accentColor = Color(0xFFF15808);
    const Color primaryTextColor = Color(0xFF111827);

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
            icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            l.translate('editProfile.title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: !_isInitialized
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              _buildPhotoEditor(l),
              const SizedBox(height: 32),
              _buildProfileTextField(
                controller: _nameController,
                icon: Icons.person_outline,
                label: l.translate('editProfile.fullNameLabel'),
              ),
              const SizedBox(height: 24),
              _buildPhoneNumberField(l),
              const SizedBox(height: 24),
              _buildProfileTextField(
                controller: _locationController,
                icon: Icons.location_on_outlined,
                label: l.translate('editProfile.locationLabel'),
                suffixIcon: _isDetectingLocation
                    ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : IconButton(
                  icon: Icon(Icons.my_location,
                      color: Colors.grey[600]),
                  onPressed: _handleAutoDetectLocation,
                ),
              ),
              const SizedBox(height: 24),
              _buildLanguagesField(l),
              const SizedBox(height: 40),
              _buildUpdateButton(accentColor, l),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoEditor(AppLocalizations l) {
    return Column(
      children: [
        CircleAvatar(
          radius: 45,
          backgroundImage: _imageFile != null
              ? FileImage(File(_imageFile!.path))
              : (_avatarUrl != null && _avatarUrl!.isNotEmpty
              ? NetworkImage(_avatarUrl!)
              : const AssetImage('assets/images/leo_martinez.png'))
          as ImageProvider,
          backgroundColor: Colors.grey.shade200,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _pickImage,
          child: Text(
            l.translate('editProfile.editPhoto'),
            style: GoogleFonts.poppins(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTextField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.grey[700], size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller,
          style: GoogleFonts.poppins(
            color: const Color(0xFF292D32),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
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

  Widget _buildPhoneNumberField(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.phone_outlined, color: Colors.grey[700], size: 22),
            const SizedBox(width: 12),
            Text(
              l.translate('editProfile.phoneNumberLabel'),
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: GoogleFonts.poppins(
            color: const Color(0xFF292D32),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            prefixIcon: GestureDetector(
              onTap: _showCountryPickerIOS,
              child: Padding(
                padding: const EdgeInsets.only(left: 15.0, right: 10.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedCountry.flagEmoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            prefixText: '+${_selectedCountry.phoneCode} ',
            prefixStyle: GoogleFonts.poppins(
              color: const Color(0xFF292D32),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
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

  Widget _buildLanguagesField(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: Colors.grey[700], size: 22),
            const SizedBox(width: 12),
            Text(
              l.translate('editProfile.languagesSpokenLabel'),
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _showLanguagePickerIOS,
          child: AbsorbPointer(
            child: TextFormField(
              controller: _languagesController,
              maxLines: null,
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                hintText: l.translate('editProfile.selectLanguagesHint'),
                hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
                suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateButton(Color accentColor, AppLocalizations l) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isUpdating ? null : _updateProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: _isUpdating
            ? const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
        )
            : Text(
          l.translate('editProfile.updateProfileButton'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

// Custom iOS-style Language Selection Bottom Sheet
class _CupertinoLanguageSheet extends StatefulWidget {
  final List<Language> initialLanguages;
  final Function(List<Language>) onDone;
  final AppLocalizations l;

  const _CupertinoLanguageSheet({
    super.key,
    required this.initialLanguages,
    required this.onDone,
    required this.l,
  });

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
            widget.l.translate('picker.languagesTitle'),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 17,
              color: CupertinoColors.black,
            ),
          ),
          CupertinoButton(
            child: Text(widget.l.translate('picker.doneButton'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
        placeholder: widget.l.translate('picker.searchPlaceholder'),
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
                const Icon(CupertinoIcons.check_mark, color: CupertinoColors.activeBlue)
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

// Custom iOS-style Country Selection Bottom Sheet
class _CupertinoCountryPickerSheet extends StatefulWidget {
  final Country initialCountry;
  final List<Country> countries;
  final Function(Country) onCountrySelected;
  final AppLocalizations l;

  const _CupertinoCountryPickerSheet({
    super.key,
    required this.initialCountry,
    required this.countries,
    required this.onCountrySelected,
    required this.l,
  });

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
    int initialIndex = widget.countries.indexWhere(
            (c) => c.countryCode == widget.initialCountry.countryCode);
    if (initialIndex == -1) {
      initialIndex = widget.countries.indexWhere((c) => c.countryCode == 'US');
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
                    child: Text(widget.l.translate('picker.cancelButton')),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    widget.l.translate('picker.countryTitle'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                      color: CupertinoColors.black,
                    ),
                  ),
                  CupertinoButton(
                    child: Text(widget.l.translate('picker.doneButton'),
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
