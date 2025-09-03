import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/booking_summary_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

class BookBuddyScreen extends StatefulWidget {
  final Map<String, dynamic> buddyProfile;
  final String? initialService;

  const BookBuddyScreen({
    super.key,
    required this.buddyProfile,
    this.initialService,
  });
  @override
  State<BookBuddyScreen> createState() => _BookBuddyScreenState();
}

class _BookBuddyScreenState extends State<BookBuddyScreen> {
  // Form State
  String? _selectedService; // Stores the original English service name for backend
  int? _selectedDuration; // Duration in hours
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // UI State
  bool _isLoadingBookings = true;
  bool _isServicesLoading = true;
  bool _isCheckingAvailability = false;
  String? _noSlotsReason; // Can be 'past' or 'booked'

  // Data
  final List<Map<String, dynamic>> _bookings = [];
  List<TimeOfDay> _availableSlots = [];
  final _noteController = TextEditingController();
  final _dateController = TextEditingController();
  Map<String, String> _serviceTranslationMap = {}; // Maps English name to translated name

  // For custom dropdowns
  final LayerLink _serviceLayerLink = LayerLink();
  final LayerLink _durationLayerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isServiceDropdownOpen = false;
  bool _isDurationDropdownOpen = false;
  final GlobalKey _serviceDropdownKey = GlobalKey();
  final GlobalKey _durationDropdownKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedService = widget.initialService;
    _fetchBuddyBookings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadServiceTranslations();
      }
    });
  }

  Future<void> _loadServiceTranslations() async {
    if (!mounted) return;
    final localizations = AppLocalizations.of(context);
    setState(() {
      _isServicesLoading = true;
    });
    try {
      final response = await supabase.from('services').select('name, name_key');
      final Map<String, String> translationMap = {};
      for (var service in response) {
        final serviceName = service['name'] as String;
        final nameKey = service['name_key'] as String?;
        if (nameKey != null) {
          translationMap[serviceName] =
              localizations.translate(nameKey, fallback: serviceName);
        } else {
          translationMap[serviceName] = serviceName;
        }
      }
      if (mounted) {
        setState(() {
          _serviceTranslationMap = translationMap;
          _isServicesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isServicesLoading = false;
        });
      }
    }
  }

  Future<void> _fetchBuddyBookings() async {
    setState(() {
      _isLoadingBookings = true;
    });
    try {
      final buddyId = widget.buddyProfile['id'];
      if (buddyId == null) throw 'Buddy ID not found.';
      final response = await Supabase.instance.client
          .from('bookings')
          .select('date, time, duration')
          .eq('buddy_id', buddyId)
          .inFilter('status', ['confirmed', 'ongoing', 'pending'])
          .gte('date', DateFormat('yyyy-MM-dd').format(DateTime.now()));
      _bookings.clear();
      _bookings.addAll(List<Map<String, dynamic>>.from(response));
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        context.showSnackBar(
          localizations.translate('book_buddy_error_schedule_load',
              args: {'error': e.toString()}),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBookings = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _noteController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _closeOpenDropdown() {
    if (_isServiceDropdownOpen || _isDurationDropdownOpen) {
      _removeOverlay();
      setState(() {
        _isServiceDropdownOpen = false;
        _isDurationDropdownOpen = false;
      });
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _toggleServiceDropdown() {
    if (_isServiceDropdownOpen) {
      _closeOpenDropdown();
    } else {
      _closeOpenDropdown();
      _createOverlay(isService: true);
      setState(() {
        _isServiceDropdownOpen = true;
      });
    }
  }

  void _toggleDurationDropdown() {
    if (_isDurationDropdownOpen) {
      _closeOpenDropdown();
    } else {
      _closeOpenDropdown();
      _createOverlay(isService: false);
      setState(() {
        _isDurationDropdownOpen = true;
      });
    }
  }

  void _createOverlay({required bool isService}) {
    _removeOverlay();
    assert(_overlayEntry == null);
    final localizations = AppLocalizations.of(context);
    final key = isService ? _serviceDropdownKey : _durationDropdownKey;
    final link = isService ? _serviceLayerLink : _durationLayerLink;
    final renderBox = key.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    List<Widget> items;
    if (isService) {
      final List<String> services =
          (widget.buddyProfile['skills'] as List?)?.map((s) => s.toString()).toList() ?? [];
      items = services.map((service) {
        final bool isSelected = _selectedService == service;
        final translatedText = _serviceTranslationMap[service] ?? service;
        return _buildDropdownItem(
          text: translatedText,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedService = service;
              if (_selectedDate != null) _generateAvailableSlots();
            });
            _closeOpenDropdown();
          },
        );
      }).toList();
    } else {
      final List<int> durations = List.generate(4, (index) => index + 1);
      items = durations.map((duration) {
        final bool isSelected = _selectedDuration == duration;
        final durationText = duration == 1
            ? localizations.translate('book_buddy_hour_singular')
            : localizations.translate('book_buddy_hour_plural');
        return _buildDropdownItem(
          text: '$duration $durationText',
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedDuration = duration;
              if (_selectedDate != null) _generateAvailableSlots();
            });
            _closeOpenDropdown();
          },
        );
      }).toList();
    }
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: link,
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
                children: items,
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildDropdownItem(
      {required String text, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? const Color(0xFF19638D).withOpacity(0.1) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: isSelected ? const Color(0xFF19638D) : Colors.black87,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    _closeOpenDropdown();
    final localizations = AppLocalizations.of(context);
    final DateTime? pickedDate = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return CustomDatePickerDialog(
          cancelText: localizations.translate('datepicker_cancel'),
          selectText: localizations.translate('datepicker_select'),
        );
      },
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
        _dateController.text = DateFormat('dd MMMM, yyyy').format(pickedDate);
        _selectedTime = null; // Reset time
        _generateAvailableSlots();
      });
    }
  }

  void _generateAvailableSlots() {
    if (_selectedDate == null || _selectedDuration == null) {
      setState(() {
        _availableSlots = [];
        _noSlotsReason = null;
      });
      return;
    }
    final workingDayStart =
    DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 0);
    // **THE FIX**: Extend working day to midnight of the next day to include all slots of the current day.
    final workingDayEnd =
    DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day + 1);
    final List<TimeOfDay> potentialSlots = [];
    DateTime currentTime = workingDayStart;
    while (currentTime.isBefore(workingDayEnd)) {
      potentialSlots.add(TimeOfDay.fromDateTime(currentTime));
      currentTime = currentTime.add(const Duration(minutes: 30));
    }
    final List<TimeOfDay> available = [];
    bool allSlotsInPast = true;
    for (final slot in potentialSlots) {
      final slotStartDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        slot.hour,
        slot.minute,
      );
      final slotEndDateTime = slotStartDateTime.add(Duration(hours: _selectedDuration!));
      if (slotStartDateTime.isAfter(DateTime.now())) {
        allSlotsInPast = false;
      }
      if (isSameDay(_selectedDate, DateTime.now()) &&
          slotStartDateTime.isBefore(DateTime.now())) {
        continue;
      }
      bool isOverlapping = _bookings.any((booking) {
        try {
          final bookingDateStr = booking['date'] as String;
          final bookingTimeStr = booking['time'] as String;
          final dynamic durationValue = booking['duration'];
          int durationInMinutes;
          if (durationValue is num) {
            durationInMinutes = durationValue.toInt();
          } else if (durationValue is String) {
            durationInMinutes = int.tryParse(durationValue) ?? 0;
          } else {
            durationInMinutes = 0;
          }
          final bookingStart = DateTime.parse('$bookingDateStr $bookingTimeStr');
          final bookingEnd = bookingStart.add(Duration(minutes: durationInMinutes));
          return slotStartDateTime.isBefore(bookingEnd) &&
              slotEndDateTime.isAfter(bookingStart);
        } catch (e) {
          debugPrint("Error parsing booking for overlap check: $e");
          return false;
        }
      });
      if (!isOverlapping) {
        available.add(slot);
      }
    }
    String? reason;
    if (available.isEmpty) {
      if (isSameDay(_selectedDate, DateTime.now()) && allSlotsInPast) {
        reason = 'past';
      } else {
        reason = 'booked';
      }
    }
    setState(() {
      _availableSlots = available;
      _noSlotsReason = reason;
    });
  }

  Future<void> _onNextPressed() async {
    _closeOpenDropdown();
    final localizations = AppLocalizations.of(context);
    if (_selectedService == null ||
        _selectedDate == null ||
        _selectedTime == null ||
        _selectedDuration == null) {
      context.showSnackBar(
        localizations.translate('book_buddy_error_all_fields'),
        isError: true,
      );
      return;
    }
    setState(() {
      _isCheckingAvailability = true;
    });
    try {
      await _fetchBuddyBookings();
      _generateAvailableSlots();
      final isSlotStillAvailable = _availableSlots
          .any((slot) => slot.hour == _selectedTime!.hour && slot.minute == _selectedTime!.minute);
      if (!isSlotStillAvailable) {
        if (!mounted) return;
        context.showSnackBar(
          localizations.translate('book_buddy_error_slot_booked'),
          isError: true,
        );
        setState(() {
          _selectedTime = null;
        });
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookingSummaryScreen(
            buddy: widget.buddyProfile,
            service: _selectedService!,
            date: _selectedDate!,
            time: _selectedTime!,
            durationInHours: _selectedDuration!,
            note: _noteController.text.trim(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      context.showSnackBar(
        localizations.translate('book_buddy_error_generic', args: {'error': e.toString()}),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingAvailability = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color accentColor = Color(0xFFF15808);
    final bool canSelectDate = _selectedService != null && _selectedDuration != null;
    final bool canSelectTime = canSelectDate && _selectedDate != null;
    final localizations = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: GestureDetector(
        onTap: () {
          _closeOpenDropdown();
          FocusScope.of(context).unfocus();
        },
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
              localizations.translate('book_buddy_title'),
              style: GoogleFonts.poppins(
                color: primaryTextColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
          ),
          body: _isLoadingBookings || _isServicesLoading
              ? const Center(child: CircularProgressIndicator(color: accentColor))
              : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBuddyInfo(localizations),
                const SizedBox(height: 32),
                _buildServiceDropdown(localizations),
                const SizedBox(height: 24),
                _buildDurationDropdown(localizations),
                const SizedBox(height: 24),
                _buildFormField(
                  label: localizations.translate('book_buddy_date'),
                  hint: canSelectDate
                      ? localizations.translate('book_buddy_select_date')
                      : localizations
                      .translate('book_buddy_select_service_duration_first'),
                  icon: Icons.calendar_today_outlined,
                  controller: _dateController,
                  onTap: canSelectDate ? () => _selectDate(context) : null,
                ),
                const SizedBox(height: 24),
                if (canSelectTime) _buildTimeSlotGrid(localizations),
                const SizedBox(height: 24),
                _buildNoteField(localizations),
                const SizedBox(height: 40),
              ],
            ),
          ),
          bottomNavigationBar: _buildActionButtons(context, accentColor, localizations),
        ),
      ),
    );
  }

  Widget _buildTimeSlotGrid(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.translate('book_buddy_available_slots'),
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 16),
        _availableSlots.isEmpty
            ? _buildEmptyState(localizations)
            : GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 12.0,
            childAspectRatio: 2.5,
          ),
          itemCount: _availableSlots.length,
          itemBuilder: (context, index) {
            final time = _availableSlots[index];
            final isSelected = _selectedTime == time;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTime = isSelected ? null : time;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFF15808) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFF15808) : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (!isSelected)
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                  ],
                ),
                child: Center(
                  child: Text(
                    time.format(context),
                    style: GoogleFonts.poppins(
                      color: isSelected ? Colors.white : const Color(0xFF111827),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations localizations) {
    final String title;
    final String subtitle;
    final IconData icon;
    if (_noSlotsReason == 'past') {
      title = localizations.translate('book_buddy_no_slots_past_title');
      subtitle = localizations.translate('book_buddy_no_slots_past_subtitle');
      icon = Icons.update_outlined;
    } else {
      title = localizations.translate('book_buddy_no_slots_booked_title');
      subtitle = localizations.translate('book_buddy_no_slots_booked_subtitle');
      icon = Icons.event_busy_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200)),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuddyInfo(AppLocalizations localizations) {
    final String buddyName = widget.buddyProfile['name'] ?? 'No Name';
    final String? buddyImageUrl = widget.buddyProfile['profile_picture'];
    ImageProvider buddyAvatar;
    if (buddyImageUrl != null &&
        buddyImageUrl.isNotEmpty &&
        buddyImageUrl.startsWith('http')) {
      buddyAvatar = NetworkImage(buddyImageUrl);
    } else {
      buddyAvatar = const AssetImage('assets/images/sam_wilson.png');
    }
    return Row(
      children: [
        CircleAvatar(
          radius: 35,
          backgroundImage: buddyAvatar,
          backgroundColor: Colors.grey.shade200,
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  buddyName,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.verified, color: Colors.blue, size: 18),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              localizations.translate('book_buddy_verified'),
              style: GoogleFonts.poppins(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceDropdown(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.translate('book_buddy_service_type'),
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        CompositedTransformTarget(
          link: _serviceLayerLink,
          child: GestureDetector(
            key: _serviceDropdownKey,
            onTap: _toggleServiceDropdown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isServiceDropdownOpen
                      ? const Color(0xFF19638D)
                      : Colors.grey.shade200,
                  width: _isServiceDropdownOpen ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _serviceTranslationMap[_selectedService] ??
                          _selectedService ??
                          localizations.translate('book_buddy_select_service'),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: _selectedService == null
                            ? Colors.grey.shade400
                            : const Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _isServiceDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
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

  Widget _buildDurationDropdown(AppLocalizations localizations) {
    String durationText;
    if (_selectedDuration == null) {
      durationText = localizations.translate('book_buddy_select_duration');
    } else {
      final hourText = _selectedDuration == 1
          ? localizations.translate('book_buddy_hour_singular')
          : localizations.translate('book_buddy_hour_plural');
      durationText = '$_selectedDuration $hourText';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.translate('book_buddy_duration_hours'),
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        CompositedTransformTarget(
          link: _durationLayerLink,
          child: GestureDetector(
            key: _durationDropdownKey,
            onTap: _toggleDurationDropdown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDurationDropdownOpen
                      ? const Color(0xFF19638D)
                      : Colors.grey.shade200,
                  width: _isDurationDropdownOpen ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      durationText,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: _selectedDuration == null
                            ? Colors.grey.shade400
                            : const Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _isDurationDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
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

  Widget _buildFormField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          decoration: _inputDecoration(hint: hint).copyWith(
            suffixIcon: Icon(icon, color: Colors.grey.shade600),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
          ),
          enabled: onTap != null,
        ),
      ],
    );
  }

  Widget _buildNoteField(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.translate('book_buddy_additional_note'),
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          maxLines: 5,
          decoration: _inputDecoration(
              hint: localizations.translate('book_buddy_note_hint')),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
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
        borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
      ),
    );
  }

  Widget _buildActionButtons(
      BuildContext context, Color accentColor, AppLocalizations localizations) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.fromLTRB(24.0, 10.0, 24.0, 34.0),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: accentColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  localizations.translate('book_buddy_button_cancel'),
                  style: GoogleFonts.poppins(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _isCheckingAvailability ? null : _onNextPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: _isCheckingAvailability
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : Text(
                  localizations.translate('book_buddy_button_next'),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomDatePickerDialog extends StatefulWidget {
  final String cancelText;
  final String selectText;
  const CustomDatePickerDialog({
    super.key,
    required this.cancelText,
    required this.selectText,
  });
  @override
  State<CustomDatePickerDialog> createState() => _CustomDatePickerDialogState();
}

class _CustomDatePickerDialogState extends State<CustomDatePickerDialog> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    const Color accentColor = Color(0xFFF15808);
    const Color primaryColor = Color(0xFF111827);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: contentBox(context, accentColor, primaryColor),
      ),
    );
  }

  Widget contentBox(BuildContext context, Color accentColor, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 10),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TableCalendar(
            firstDay: DateTime.now(),
            lastDay: DateTime.now().add(const Duration(days: 60)),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarFormat: CalendarFormat.month,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: GoogleFonts.poppins(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
              leftChevronIcon: Icon(Icons.chevron_left, color: primaryColor),
              rightChevronIcon: Icon(Icons.chevron_right, color: primaryColor),
            ),
            calendarStyle: CalendarStyle(
              selectedDecoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              todayDecoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              todayTextStyle: GoogleFonts.poppins(
                color: accentColor,
                fontWeight: FontWeight.bold,
              ),
              defaultTextStyle: GoogleFonts.poppins(color: primaryColor),
              weekendTextStyle: GoogleFonts.poppins(color: primaryColor.withOpacity(0.7)),
              outsideDaysVisible: false,
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.poppins(
                color: primaryColor.withOpacity(0.8),
                fontWeight: FontWeight.w600,
              ),
              weekendStyle: GoogleFonts.poppins(
                color: primaryColor.withOpacity(0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  widget.cancelText,
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  Navigator.of(context).pop(_selectedDay);
                },
                child: Text(
                  widget.selectText,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
