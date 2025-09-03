import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/screens/buddy_details_screen.dart';
import 'package:mygobuddy/utils/app_icons.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/constants.dart';

class SearchResultsScreen extends StatefulWidget {
  final String? initialService;
  const SearchResultsScreen({super.key, this.initialService});
  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  List<Map<String, dynamic>> _buddies = [];
  bool _isLoadingBuddies = true;
  List<Map<String, dynamic>> _services = [];
  bool _isLoadingServices = true;
  late String _selectedServiceKey;
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedServiceKey = widget.initialService ?? 'All';
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _fetchBuddies(
        serviceKey: _selectedServiceKey,
        searchText: _searchController.text,
      );
    });
  }

  Future<void> _loadData() async {
    await _fetchServices();
    await _fetchBuddies(serviceKey: _selectedServiceKey);
  }

  Future<void> _fetchServices() async {
    if (!mounted) return;
    setState(() => _isLoadingServices = true);
    try {
      final response =
      await supabase.from('services').select('name, name_key').order('id');
      if (mounted) {
        setState(() {
          _services = List<Map<String, dynamic>>.from(response as List);
          _isLoadingServices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(localizations.translate(
                  'search_results_error_fetching_services',
                  args: {'error': e.toString()}))),
        );
        setState(() => _isLoadingServices = false);
      }
    }
  }

  Future<void> _fetchBuddies(
      {required String serviceKey, String? searchText}) async {
    if (!mounted) return;

    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    final userCountry = profileProvider.profile?['country'] as String?;

    if (userCountry == null || userCountry.isEmpty) {
      if (mounted) {
        setState(() {
          _buddies = [];
          _isLoadingBuddies = false;
        });
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
            Text(localizations.translate('search_results_error_no_country')),
          ),
        );
      }
      return;
    }

    setState(() => _isLoadingBuddies = true);
    try {
      String? englishServiceName;
      if (serviceKey != 'All' && _services.isNotEmpty) {
        final serviceData = _services.firstWhere(
              (s) => s['name_key'] == serviceKey,
          orElse: () => <String, dynamic>{},
        );
        if (serviceData.isNotEmpty) {
          englishServiceName = serviceData['name'] as String?;
        }
      }

      final response = await supabase.rpc(
        'search_buddies_by_skill',
        params: {
          'p_skill': englishServiceName ?? 'All',
          'p_search_term': searchText ?? '',
          'p_country_code': userCountry,
        },
      );

      if (mounted) {
        setState(() {
          _buddies = List<Map<String, dynamic>>.from(response);
          _isLoadingBuddies = false;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('--- DETAILED FETCH BUDDIES ERROR ---');
        debugPrint('Error Type: ${e.runtimeType}');
        debugPrint('Error Message: $e');
        if (e is PostgrestException) {
          debugPrint('Postgrest Code: ${e.code}');
          debugPrint('Postgrest Details: ${e.details}');
          debugPrint('Postgrest Hint: ${e.hint}');
        }
        debugPrint('------------------------------------');

        final localizations = AppLocalizations.of(context)!;
        setState(() => _isLoadingBuddies = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(localizations.translate(
                  'search_results_error_fetching_buddies',
                  args: {'error': e.toString()}))),
        );
      }
    }
  }

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
      return buddy['title'] as String? ?? localizations.translate('search_results_default_buddy_title', fallback: 'Local Helper');
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryColor = Color(0xFF19638D);
    const Color accentColor = Color(0xFFF15808);
    final localizations = AppLocalizations.of(context)!;

    String resultText;
    if (_isLoadingBuddies) {
      resultText = localizations.translate('search_results_searching');
    } else {
      final count = _buddies.length;
      if (count == 0) {
        resultText = localizations.translate('search_results_found_none');
      } else if (count == 1) {
        resultText = localizations.translate('search_results_found_one');
      } else {
        resultText = localizations
            .translate('search_results_found_many', args: {'count': count.toString()});
      }
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, primaryColor, localizations),
              const SizedBox(height: 16),
              _buildSearchBar(localizations),
              const SizedBox(height: 16),
              _buildFilterChips(accentColor, localizations),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  resultText,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoadingBuddies
                    ? _buildBuddyListShimmer()
                    : _buddies.isEmpty
                    ? Center(
                  child: Text(
                    localizations.translate(
                        'search_results_no_buddies_for_service'),
                    style:
                    GoogleFonts.poppins(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                )
                    : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _buddies.length,
                  separatorBuilder: (context, index) =>
                  const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final buddy = _buddies[index];
                    return _buildBuddyResultCard(
                        buddy, accentColor, localizations);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, Color primaryColor, AppLocalizations localizations) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.black, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              localizations.translate('search_results_title'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          SizedBox(
            width: 48, // To balance the back button
            child: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: SvgPicture.string(
                  AppIcons.filter
                      .replaceAll('stroke="#19638D"', 'stroke="white"'),
                  height: 22,
                  width: 22,
                ),
                onPressed: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppLocalizations localizations) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          hintText: localizations.translate('search_results_search_hint'),
          hintStyle: GoogleFonts.poppins(color: Colors.grey.shade500),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12.0),
            child: SvgPicture.string(
              AppIcons.search,
              colorFilter:
              const ColorFilter.mode(Color(0xFF6B7280), BlendMode.srcIn),
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(Color accentColor, AppLocalizations localizations) {
    if (_isLoadingServices) {
      return _buildFilterChipsShimmer();
    }
    final List<String> filterKeys = [
      'All',
      ..._services.map((s) => s['name_key'] as String).toList()
    ];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: filterKeys.length,
        itemBuilder: (context, index) {
          final filterKey = filterKeys[index];
          final isSelected = filterKey == _selectedServiceKey;
          final filterText = filterKey == 'All'
              ? localizations.translate('search_results_all_filter')
              : localizations.translate(filterKey, fallback: filterKey);
          return Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: ChoiceChip(
              label: Text(filterText),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedServiceKey = filterKey;
                  });
                  _fetchBuddies(
                    serviceKey: _selectedServiceKey,
                    searchText: _searchController.text,
                  );
                }
              },
              backgroundColor: Colors.white,
              selectedColor: accentColor,
              labelStyle: GoogleFonts.poppins(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: Colors.grey.shade200,
                ),
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChipsShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 5,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(right: 10.0),
              child: Container(
                width: 80,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBuddyListShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 5,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildBuddyResultCardShimmer(),
    );
  }

  Widget _buildBuddyResultCardShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const CircleAvatar(radius: 30, backgroundColor: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      width: 120,
                      height: 18,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 8)),
                  Container(
                      width: 80,
                      height: 14,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 8)),
                  Container(width: 150, height: 12, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuddyResultCard(Map<String, dynamic> buddy, Color accentColor,
      AppLocalizations localizations) {
    final naText = localizations.translate('search_results_na');
    final name = buddy['name'] as String? ?? naText;
    final imageUrl = buddy['profile_picture'] as String? ?? '';
    final title = _getPrimaryService(buddy, localizations);
    final ratingValue = buddy['rating'];
    final rating = (ratingValue is num) ? ratingValue.toStringAsFixed(1) : naText;
    final reviewCount = buddy['review_count'] as int? ?? 0;
    String reviewsText;
    if (reviewCount == 1) {
      reviewsText = localizations.translate('search_results_review_one',
          args: {'count': reviewCount.toString()});
    } else {
      reviewsText = localizations.translate('search_results_review_many',
          args: {'count': reviewCount.toString()});
    }

    final rateValue = buddy['rate'];
    String priceDisplay;
    String priceSubtext;

    if (rateValue is Map<String, dynamic>) {
      // New system: service-specific pricing
      final rates = rateValue.values.where((rate) => rate is num).map((rate) => (rate as num).toDouble()).toList();
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
        priceDisplay = naText;
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
      priceDisplay = naText;
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
            CircleAvatar(
              radius: 30,
              backgroundImage: (imageUrl.isNotEmpty && imageUrl.startsWith('http'))
                  ? NetworkImage(imageUrl)
                  : const AssetImage('assets/images/sam_wilson.png')
              as ImageProvider,
              backgroundColor: Colors.grey.shade200,
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
                        '$rating $reviewsText',
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
                    color: accentColor,
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
