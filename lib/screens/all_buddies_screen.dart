import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/screens/buddy_details_screen.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/constants.dart';

// Enum to manage the filter state for clarity
enum FilterMode { nearby, all }

class AllBuddiesScreen extends StatefulWidget {
  final double? userLatitude;
  final double? userLongitude;
  final String? userCountry;

  const AllBuddiesScreen({
    super.key,
    this.userLatitude,
    this.userLongitude,
    this.userCountry,
  });

  @override
  State<AllBuddiesScreen> createState() => _AllBuddiesScreenState();
}

class _AllBuddiesScreenState extends State<AllBuddiesScreen> {
  List<Map<String, dynamic>> _buddies = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _hasInitialized = false;

  // Filter state
  FilterMode _filterMode = FilterMode.nearby;
  double _searchRadius = 25.0; // Default search radius in km

  @override
  void initState() {
    super.initState();
    // Default to 'nearby' if location is available, otherwise switch to 'all'
    if (widget.userLatitude == null || widget.userLongitude == null) {
      _filterMode = FilterMode.all;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only fetch buddies once when dependencies are ready
    if (!_hasInitialized) {
      _hasInitialized = true;
      _fetchBuddies();
    }
  }

  Future<void> _fetchBuddies() async {
    if (!mounted) return;

    print('Fetching buddies with mode: $_filterMode');
    print('User location: ${widget.userLatitude}, ${widget.userLongitude}');
    print('User country: ${widget.userCountry}');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      dynamic response;
      if (_filterMode == FilterMode.nearby) {
        if (widget.userLatitude == null || widget.userLongitude == null) {
          throw Exception('Location unavailable for nearby search');
        }
        if (widget.userCountry == null || widget.userCountry!.isEmpty) {
          throw Exception('Country unavailable for nearby search');
        }
        print('Calling get_buddies_within_radius with params: lat=${widget.userLatitude}, lng=${widget.userLongitude}, radius=$_searchRadius, country=${widget.userCountry}');
        response = await supabase.rpc('get_buddies_within_radius', params: {
          'user_lat': widget.userLatitude,
          'user_long': widget.userLongitude,
          'radius_km': _searchRadius,
          'client_country': widget.userCountry, // The fix
        });
      } else { // FilterMode.all
        if (widget.userCountry == null || widget.userCountry!.isEmpty) {
          throw Exception('Country unavailable for search');
        }
        print('Calling get_buddies_by_country with country: ${widget.userCountry}');
        response = await supabase.rpc('get_buddies_by_country', params: {
          'p_country_name': widget.userCountry,
        });
      }

      print('Response received: $response');
      print('Response type: ${response.runtimeType}');
      print('Response length: ${response is List ? response.length : 'Not a list'}');

      if (mounted) {
        setState(() {
          _buddies = List<Map<String, dynamic>>.from(response as List);
          print('Buddies loaded: ${_buddies.length}');
        });
      }
    } catch (e) {
      print('Error fetching buddies: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading buddies: ${e.toString()}';
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

  void _openFilterModal() {
    final localizations = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Important for responsiveness
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _FilterBottomSheet(
          initialFilterMode: _filterMode,
          initialSearchRadius: _searchRadius,
          onApplyFilters: (newMode, newRadius) {
            setState(() {
              _filterMode = newMode;
              _searchRadius = newRadius;
            });
            _fetchBuddies();
          },
          localizations: localizations,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          localizations.translate('all_buddies_title', fallback: 'All Buddies'),
          style: GoogleFonts.poppins(
            color: primaryTextColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openFilterModal,
            icon: const Icon(CupertinoIcons.slider_horizontal_3, color: primaryTextColor),
            tooltip: localizations.translate('all_buddies_filter_tooltip', fallback: 'Filter'),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildActiveFilterIndicator(),
          Expanded(child: _buildBodyContent()),
        ],
      ),
    );
  }

  Widget _buildActiveFilterIndicator() {
    final localizations = AppLocalizations.of(context);
    String label = _filterMode == FilterMode.all
        ? localizations.translate('all_buddies_filter_chip_all', fallback: 'All in ${widget.userCountry ?? 'your country'}', args: {'country': widget.userCountry ?? localizations.translate('all_buddies_your_country', fallback: 'your country')})
        : localizations.translate('all_buddies_filter_chip_nearby', fallback: 'Within ${_searchRadius.toInt()} km', args: {'radius': _searchRadius.toInt().toString()});

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          label: Text(
            label,
            style: GoogleFonts.poppins(
                color: const Color(0xFFF15808),
                fontWeight: FontWeight.w500
            ),
          ),
          backgroundColor: const Color(0xFFF15808).withOpacity(0.1),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildBodyContent() {
    final localizations = AppLocalizations.of(context);
    if (_isLoading) {
      return _buildShimmerList();
    }

    if (_errorMessage != null) {
      // Use localized error message if available, otherwise use the stored error
      String displayError = _errorMessage!;
      if (_errorMessage!.contains('Location unavailable')) {
        displayError = localizations.translate('all_buddies_error_location_unavailable', fallback: 'Location unavailable for nearby search');
      } else if (_errorMessage!.contains('Country unavailable')) {
        displayError = localizations.translate('all_buddies_error_country_unavailable', fallback: 'Country unavailable for search');
      } else {
        displayError = localizations.translate('all_buddies_error_generic', fallback: 'Error loading buddies: $_errorMessage', args: {'error': _errorMessage!});
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(
                  displayError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchBuddies,
                child: Text(localizations.translate('retry', fallback: 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (_buddies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              localizations.translate('all_buddies_empty_title', fallback: 'No buddies found'),
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Text(
                _filterMode == FilterMode.nearby
                    ? localizations.translate('all_buddies_empty_nearby_hint', fallback: 'Try expanding your search radius or switch to view all buddies.')
                    : localizations.translate('all_buddies_empty_all_hint', fallback: 'No buddies available in your country yet.'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _openFilterModal,
              child: Text(localizations.translate('adjust_filters', fallback: 'Adjust Filters')),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchBuddies,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: _buddies.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final buddy = _buddies[index];
          return _BuddyListCard(buddy: buddy, localizations: localizations);
        },
      ),
    );
  }

  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 8,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) => Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _FilterBottomSheet extends StatefulWidget {
  final FilterMode initialFilterMode;
  final double initialSearchRadius;
  final Function(FilterMode, double) onApplyFilters;
  final AppLocalizations localizations;

  const _FilterBottomSheet({
    required this.initialFilterMode,
    required this.initialSearchRadius,
    required this.onApplyFilters,
    required this.localizations,
  });

  @override
  State<_FilterBottomSheet> createState() => __FilterBottomSheetState();
}

class __FilterBottomSheetState extends State<_FilterBottomSheet> {
  late FilterMode _currentMode;
  late double _currentRadius;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialFilterMode;
    _currentRadius = widget.initialSearchRadius;
  }

  @override
  Widget build(BuildContext context) {
    bool isNearbyMode = _currentMode == FilterMode.nearby;
    final localizations = widget.localizations;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              localizations.translate('filter_buddies_title', fallback: 'Filter Buddies'),
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(localizations.translate('filter_buddies_show_all', fallback: 'Show all buddies'), style: GoogleFonts.poppins(fontSize: 15)),
                CupertinoSwitch(
                  value: !isNearbyMode,
                  onChanged: (value) {
                    setState(() {
                      _currentMode = value ? FilterMode.all : FilterMode.nearby;
                    });
                  },
                  activeColor: const Color(0xFFF15808),
                ),
              ],
            ),
            const Divider(height: 28),
            Text(
              localizations.translate('filter_buddies_distance', fallback: 'Distance'),
              style: GoogleFonts.poppins(fontSize: 15, color: isNearbyMode ? Colors.black : Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _currentRadius,
                    min: 1,
                    max: 100,
                    divisions: 99,
                    activeColor: const Color(0xFFF15808),
                    inactiveColor: const Color(0xFFF15808).withOpacity(0.2),
                    onChanged: isNearbyMode ? (value) {
                      setState(() {
                        _currentRadius = value;
                      });
                    } : null,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${_currentRadius.toInt()} km',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: isNearbyMode ? Colors.black : Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: const Color(0xFFF15808),
                onPressed: () {
                  widget.onApplyFilters(_currentMode, _currentRadius);
                  Navigator.pop(context);
                },
                child: Text(
                  localizations.translate('filter_buddies_apply', fallback: 'Apply Filters'),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuddyListCard extends StatelessWidget {
  final Map<String, dynamic> buddy;
  final AppLocalizations localizations;
  const _BuddyListCard({required this.buddy, required this.localizations});

  String _getPrimaryService(Map<String, dynamic> buddy, AppLocalizations localizations) {
    final rateData = buddy['rate'];

    if (rateData != null && rateData is Map<String, dynamic> && rateData.isNotEmpty) {
      // Find the service with the highest rate (primary expertise)
      String primaryService = '';
      double highestRate = 0.0;

      rateData.forEach((serviceName, rateValue) {
        double rate = 0.0;
        if (rateValue is String) {
          rate = double.tryParse(rateValue) ?? 0.0;
        } else if (rateValue is num) {
          rate = rateValue.toDouble();
        }

        if (rate > highestRate) {
          highestRate = rate;
          primaryService = serviceName;
        }
      });

      return primaryService.isNotEmpty ? primaryService : localizations.translate('home_general_help', fallback: 'General Help');
    } else {
      // Fallback to title field or default
      return buddy['title'] as String? ?? localizations.translate('all_buddies_default_title', fallback: 'Travel Buddy');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notApplicable = localizations.translate('search_results_na', fallback: 'N/A');
    final name = buddy['name'] as String? ?? notApplicable;
    final imageUrl = buddy['profile_picture'] as String? ?? '';
    final title = _getPrimaryService(buddy, localizations);
    final ratingValue = buddy['rating'];
    final rating = (ratingValue is num) ? ratingValue.toStringAsFixed(1) : notApplicable;
    final reviewCount = buddy['review_count']?.toString() ?? '0';
    final isOnline = buddy['is_online'] as bool? ?? false;

    final rateValue = buddy['rate'];
    String priceDisplay;
    String priceSubtext;

    if (rateValue is Map<String, dynamic>) {
      // New system: service-specific pricing
      final rates = <double>[];
      for (final rate in rateValue.values) {
        if (rate is num) {
          rates.add(rate.toDouble());
        } else if (rate is String) {
          final parsedRate = double.tryParse(rate);
          if (parsedRate != null) {
            rates.add(parsedRate);
          }
        }
      }

      if (rates.isNotEmpty) {
        rates.sort();
        final minRate = rates.first;
        final maxRate = rates.last;
        if (minRate == maxRate) {
          priceDisplay = '\$${minRate.toInt()}';
        } else {
          priceDisplay = '\$${minRate.toInt()}-\$${maxRate.toInt()}';
        }
        priceSubtext = localizations.translate('search_results_multiple_services', fallback: 'multiple services');
      } else {
        priceDisplay = notApplicable;
        priceSubtext = localizations.translate('search_results_per_session', fallback: 'per session');
      }
    } else if (rateValue is num) {
      // Old system: single rate (fallback)
      if (rateValue.truncateToDouble() == rateValue) {
        priceDisplay = '\$${rateValue.toInt()}';
      } else {
        priceDisplay = '\$${rateValue.toStringAsFixed(2)}';
      }
      priceSubtext = localizations.translate('search_results_per_session', fallback: 'per session');
    } else {
      priceDisplay = notApplicable;
      priceSubtext = localizations.translate('search_results_per_session', fallback: 'per session');
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BuddyDetailsScreen(buddyId: buddy['id']),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              spreadRadius: 1,
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: (imageUrl.isNotEmpty && imageUrl.startsWith('http'))
                      ? NetworkImage(imageUrl)
                      : const AssetImage('assets/images/sam_wilson.png') as ImageProvider,
                  backgroundColor: Colors.grey.shade200,
                ),
                if (isOnline)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$rating ($reviewCount ${localizations.translate("all_buddies_reviews", fallback: "reviews")})',
                        style: GoogleFonts.poppins(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  priceDisplay,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFF15808),
                  ),
                ),
                Text(
                  priceSubtext,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
