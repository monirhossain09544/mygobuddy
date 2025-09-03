import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/book_buddy_screen.dart';
import 'package:mygobuddy/screens/chat_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';

class BuddyDetailsScreen extends StatefulWidget {
  final String buddyId;
  const BuddyDetailsScreen({super.key, required this.buddyId});

  @override
  State<BuddyDetailsScreen> createState() => _BuddyDetailsScreenState();
}

class _BuddyDetailsScreenState extends State<BuddyDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFavorited = false;

  Map<String, dynamic>? _buddyData;
  List<Map<String, dynamic>> _servicesWithPrices = [];
  List<String> _galleryImages = [];
  bool _isLoading = true;
  bool _isChatLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchBuddyDetails();
  }

  Future<void> _fetchBuddyDetails() async {
    try {
      print('[v0] Starting to fetch buddy details for ID: ${widget.buddyId}');

      final response = await supabase
          .from('buddies')
          .select()
          .eq('id', widget.buddyId)
          .single();

      print('[v0] Buddy data fetched: ${response.toString()}');

      // First, check if ANY buddy_services exist for this buddy (without filters)
      final allBuddyServicesResponse = await supabase
          .from('buddy_services')
          .select('*')
          .eq('buddy_id', widget.buddyId);

      print('[v0] ALL buddy_services for this buddy: ${allBuddyServicesResponse.toString()}');
      print('[v0] Total buddy_services count: ${allBuddyServicesResponse.length}');

      // Check active buddy_services only
      final activeBuddyServicesResponse = await supabase
          .from('buddy_services')
          .select('*')
          .eq('buddy_id', widget.buddyId)
          .eq('is_active', true);

      print('[v0] ACTIVE buddy_services for this buddy: ${activeBuddyServicesResponse.toString()}');
      print('[v0] Active buddy_services count: ${activeBuddyServicesResponse.length}');

      // Check if services table has data
      final allServicesResponse = await supabase
          .from('services')
          .select('id, name, name_key')
          .limit(5);

      print('[v0] Sample services from services table: ${allServicesResponse.toString()}');

      final servicesResponse = await supabase
          .from('buddy_services')
          .select('''
            hourly_rate,
            is_active,
            services(
              id,
              name,
              name_key,
              icon_url
            )
          ''')
          .eq('buddy_id', widget.buddyId)
          .eq('is_active', true);

      print('[v0] Services response: ${servicesResponse.toString()}');
      print('[v0] Services response length: ${servicesResponse.length}');

      List<Map<String, dynamic>> servicesWithPrices = [];
      for (final serviceData in servicesResponse) {
        print('[v0] Processing service data: ${serviceData.toString()}');
        final service = serviceData['services'] as Map<String, dynamic>;
        final hourlyRate = (serviceData['hourly_rate'] as num?)?.toDouble() ?? 0.0;

        final serviceWithPrice = {
          'name': service['name'],
          'name_key': service['name_key'],
          'icon_url': service['icon_url'],
          'price': hourlyRate,
        };

        print('[v0] Added service: ${serviceWithPrice.toString()}');
        servicesWithPrices.add(serviceWithPrice);
      }

      print('[v0] Final services with prices: ${servicesWithPrices.toString()}');

      final gallery = (response['gallery'] as List<dynamic>?)?.cast<String>() ?? [];

      if (mounted) {
        setState(() {
          _buddyData = response;
          _servicesWithPrices = servicesWithPrices;
          _galleryImages = gallery;
          _isLoading = false;
        });
        print('[v0] State updated with ${servicesWithPrices.length} services');
      }
    } catch (e) {
      print('[v0] Error fetching buddy details: $e');
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(localizations.translate('buddy_details_error_load',
                  args: {'error': e.toString()}))),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _startChat() async {
    if (_buddyData == null || _isChatLoading) return;
    final localizations = AppLocalizations.of(context);
    setState(() {
      _isChatLoading = true;
    });
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception(localizations.translate('buddy_details_error_chat_login'));
      }
      final currentUserId = currentUser.id;
      final buddyId = widget.buddyId;
      final dynamic response = await supabase.rpc('get_or_create_conversation',
          params: {
            'p_user_id_one': currentUserId,
            'p_user_id_two': buddyId,
          });
      final conversationId = response as String?;
      if (conversationId == null || conversationId.isEmpty) {
        throw Exception(localizations.translate('buddy_details_error_chat_start'));
      }
      _navigateToChat(conversationId, buddyId);
    } catch (e) {
      debugPrint('Error starting chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.translate('buddy_details_error_chat_generic')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChatLoading = false;
        });
      }
    }
  }

  void _navigateToChat(String conversationId, String otherUserId) {
    if (mounted) {
      final localizations = AppLocalizations.of(context);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversationId,
            otherUserName: _buddyData!['name'] ??
                localizations.translate('buddy_details_fallback_name'),
            otherUserAvatar: _buddyData!['profile_picture'],
            otherUserId: otherUserId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    final localizations = AppLocalizations.of(context);
    final consistentAppBar =
    _buildAppBar(context, backgroundColor, primaryTextColor, localizations);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: consistentAppBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_buddyData == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: consistentAppBar,
        body: Center(child: Text(localizations.translate('buddy_details_error_load_body'))),
      );
    }

    const Color secondaryTextColor = Color(0xFF6B7280);
    const Color accentColor = Color(0xFFF15808);
    const Color primaryColor = Color(0xFF19638D);
    final buddyName = _buddyData!['name'] as String? ??
        localizations.translate('buddy_details_fallback_name');
    final buddyImageUrl = _buddyData!['profile_picture'] as String? ?? '';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: consistentAppBar,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: _buildHeader(
                backgroundColor: backgroundColor,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                buddyName: buddyName,
                buddyImageUrl: buddyImageUrl,
                localizations: localizations,
              ),
            ),
            SliverPersistentHeader(
              delegate: _SliverAppBarDelegate(
                Container(
                  color: Colors.white,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(25.0),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(25.0),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: primaryColor,
                      unselectedLabelColor: secondaryTextColor,
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(text: localizations.translate('buddy_details_tab_about')),
                        Tab(text: localizations.translate('buddy_details_tab_services')),
                        Tab(text: localizations.translate('buddy_details_tab_reviews')),
                      ],
                    ),
                  ),
                ),
              ),
              pinned: true,
            ),
          ];
        },
        body: Container(
          color: Colors.white,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAboutTab(primaryTextColor, secondaryTextColor, localizations),
              _buildServicesTab(primaryTextColor, secondaryTextColor, accentColor, localizations),
              _buildReviewsTab(localizations),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        context: context,
        accentColor: accentColor,
        localizations: localizations,
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, Color backgroundColor,
      Color primaryTextColor, AppLocalizations localizations) {
    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        localizations.translate('buddy_details_title'),
        style: GoogleFonts.poppins(
          color: primaryTextColor,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: Icon(
            _isFavorited ? Icons.favorite : Icons.favorite_border,
            color: _isFavorited ? Colors.red : primaryTextColor,
          ),
          onPressed: () {
            if (!_isLoading && _buddyData != null) {
              setState(() {
                _isFavorited = !_isFavorited;
              });
            }
          },
        ),
      ],
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  Widget _buildHeader({
    required Color backgroundColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required String buddyName,
    required String buddyImageUrl,
    required AppLocalizations localizations,
  }) {
    final title = _buddyData!['title'] as String? ??
        localizations.translate('buddy_details_fallback_title');
    final location = _buddyData!['location'] as String? ??
        localizations.translate('buddy_details_fallback_location');
    final ratingValue = _buddyData!['rating'];
    final rating = (ratingValue is num)
        ? ratingValue.toStringAsFixed(1)
        : localizations.translate('buddy_details_not_applicable');
    final reviewCount = _buddyData!['review_count']?.toString() ?? '0';
    final buddyTier = _buddyData!['tier'] as String? ?? 'standard';

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 50, left: 20, right: 20),
            padding: const EdgeInsets.fromLTRB(20, 65, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      buddyName,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.verified, color: Colors.blue, size: 20),
                    if (buddyTier == 'pro')
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Chip(
                          label: Text(
                            localizations.translate('pro_badge', fallback: 'PRO'),
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: const Color(0xFFF59E0B),
                          padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                          labelPadding:
                          const EdgeInsets.symmetric(horizontal: 4.0),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on,
                        color: Color(0xFFF15808), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      location,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      rating,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      localizations.translate('buddy_details_reviews_count',
                          args: {'count': reviewCount}),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                  )
                ],
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundImage: (buddyImageUrl.isNotEmpty &&
                    buddyImageUrl.startsWith('http'))
                    ? NetworkImage(buddyImageUrl)
                    : const AssetImage('assets/images/sam_wilson.png')
                as ImageProvider,
                backgroundColor: Colors.grey.shade200,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab(Color primaryTextColor, Color secondaryTextColor, AppLocalizations localizations) {
    final bio = _buddyData!['bio'] as String? ?? localizations.translate('buddy_details_no_bio');
    final responseRate = _buddyData!['response_rate']?.toString() ?? localizations.translate('buddy_details_not_applicable');
    final experience = _buddyData!['experience_level'] as String? ?? localizations.translate('buddy_details_not_applicable');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.translate('buddy_details_section_about'),
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bio,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: secondaryTextColor,
              height: 1.6,
            ),
          ),
          _buildGallerySection(primaryTextColor, localizations),
          const SizedBox(height: 24),
          Text(
            localizations.translate('buddy_details_section_stats'),
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatItem(
            icon: Icons.flash_on,
            iconColor: Colors.green,
            title: localizations.translate('buddy_details_stat_response_rate'),
            value: '$responseRate%',
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
          ),
          const SizedBox(height: 16),
          _buildStatItem(
            icon: Icons.work_outline,
            iconColor: Colors.blue,
            title: localizations.translate('buddy_details_stat_experience'),
            value: experience,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
          ),
          const SizedBox(height: 16),
          _buildStatItem(
            icon: Icons.tour,
            iconColor: Colors.purple,
            title: localizations.translate('buddy_details_stat_completed_tours'),
            value: '50+',
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
          ),
          const SizedBox(height: 24),
          _buildLanguages(primaryTextColor, secondaryTextColor, localizations),
        ],
      ),
    );
  }

  Widget _buildGallerySection(Color primaryTextColor, AppLocalizations localizations) {
    if (_galleryImages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          localizations.translate('buddy_details_section_gallery', fallback: 'Gallery'),
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: primaryTextColor,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _galleryImages.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final imageUrl = _galleryImages[index];
              return AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Center(child: CircularProgressIndicator(color: Color(0xFFF15808))),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildServicesTab(Color primaryTextColor, Color secondaryTextColor, Color accentColor, AppLocalizations localizations) {
    print('[v0] Building services tab with ${_servicesWithPrices.length} services');
    print('[v0] Services data: $_servicesWithPrices');
    print('[v0] Is loading: $_isLoading');

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_servicesWithPrices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            localizations.translate('buddy_details_no_services_pricing', fallback: 'This buddy has not set up any services yet.'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: secondaryTextColor, fontSize: 16),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _servicesWithPrices.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final service = _servicesWithPrices[index];
        return _buildServiceCard(service, primaryTextColor, secondaryTextColor, accentColor, localizations);
      },
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, Color primaryTextColor, Color secondaryTextColor, Color accentColor, AppLocalizations localizations) {
    final translatedName = localizations.translate(service['name_key'], fallback: service['name']);
    final price = service['price'] as double;
    final iconUrl = service['icon_url'] as String?;

    String formattedPrice;
    if (price.truncateToDouble() == price) {
      formattedPrice = price.toInt().toString();
    } else {
      formattedPrice = price.toStringAsFixed(2);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (iconUrl != null && iconUrl.isNotEmpty)
            CircleAvatar(
              radius: 24,
              backgroundColor: accentColor.withOpacity(0.1),
              child: SvgPicture.network(
                iconUrl,
                height: 24,
                width: 24,
                colorFilter: ColorFilter.mode(accentColor, BlendMode.srcIn),
                placeholderBuilder: (_) => Icon(Icons.miscellaneous_services, size: 24, color: accentColor),
              ),
            ),
          if (iconUrl == null || iconUrl.isEmpty)
            CircleAvatar(
              radius: 24,
              backgroundColor: accentColor.withOpacity(0.1),
              child: Icon(Icons.miscellaneous_services, size: 24, color: accentColor),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translatedName,
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: primaryTextColor),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${formattedPrice} / session',
                  style: GoogleFonts.poppins(fontSize: 14, color: secondaryTextColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BookBuddyScreen(
                    buddyProfile: _buddyData!,
                    initialService: service['name'],
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(
              localizations.translate('buddy_details_book_button', fallback: 'Book'),
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguages(Color primaryTextColor, Color secondaryTextColor, AppLocalizations localizations) {
    final languages = _buddyData!['languages'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.translate('buddy_details_section_languages'),
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: primaryTextColor,
          ),
        ),
        const SizedBox(height: 16),
        if (languages.isEmpty)
          Text(localizations.translate('buddy_details_no_languages'), style: GoogleFonts.poppins(color: secondaryTextColor)),
        if (languages.isNotEmpty)
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            children: languages
                .map((lang) => _buildLanguageChip(lang.toString(), secondaryTextColor))
                .toList(),
          )
      ],
    );
  }

  Widget _buildLanguageChip(String label, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildReviewsTab(AppLocalizations localizations) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchBuddyReviews(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                localizations.translate('buddy_details_reviews_error'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF6B7280),
                  fontSize: 16,
                ),
              ),
            ),
          );
        }

        final reviews = snapshot.data ?? [];

        if (reviews.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.rate_review_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    localizations.translate('buddy_details_no_reviews'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF6B7280),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: reviews.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final review = reviews[index];
            return _buildReviewCard(review, localizations);
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchBuddyReviews() async {
    try {
      print('[v0] Starting to fetch buddy reviews for ID: ${widget.buddyId}');

      final response = await supabase
          .from('reviews')
          .select('''
            id,
            rating,
            review_text,
            review_images,
            created_at,
            profiles!reviews_client_id_fkey(
              name,
              profile_picture
            )
          ''')
          .eq('buddy_id', widget.buddyId)
          .order('created_at', ascending: false)
          .limit(20);

      print('[v0] Reviews response: ${response.toString()}');
      print('[v0] Reviews count: ${response.length}');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('[v0] Error fetching buddy reviews: $e');
      return [];
    }
  }

  Widget _buildReviewCard(Map<String, dynamic> review, AppLocalizations localizations) {
    final rating = review['rating'] as int;
    final reviewText = review['review_text'] as String?;
    final reviewImages = (review['review_images'] as List<dynamic>?)?.cast<String>() ?? [];
    final createdAt = DateTime.parse(review['created_at'] as String);
    final clientData = review['profiles'] as Map<String, dynamic>?;

    final clientName = clientData?['name'] as String? ?? localizations.translate('anonymous_user');
    final clientImage = clientData?['profile_picture'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
          // Client info and rating
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: clientImage != null && clientImage.isNotEmpty
                    ? NetworkImage(clientImage)
                    : null,
                backgroundColor: const Color(0xFFF1F5F9),
                child: clientImage == null || clientImage.isEmpty
                    ? Icon(
                  Icons.person,
                  color: const Color(0xFF475569),
                  size: 20,
                )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475569),
                      ),
                    ),
                    Text(
                      _formatReviewDate(createdAt, localizations),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              // Star rating
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: index < rating
                        ? const Color(0xFF10B981)
                        : const Color(0xFFE2E8F0),
                  );
                }),
              ),
            ],
          ),

          // Review text
          if (reviewText != null && reviewText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              reviewText,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: const Color(0xFF475569),
                height: 1.5,
              ),
            ),
          ],

          // Review images
          if (reviewImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: reviewImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == reviewImages.length - 1 ? 0 : 8,
                    ),
                    child: GestureDetector(
                      onTap: () => _showImageDialog(reviewImages[index]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          reviewImages[index],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 200,
                              color: Colors.black54,
                              child: const Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 200,
                              color: Colors.black54,
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatReviewDate(DateTime date, AppLocalizations localizations) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 30) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return localizations.translate('days_ago', args: {'count': difference.inDays.toString()});
    } else if (difference.inHours > 0) {
      return localizations.translate('hours_ago', args: {'count': difference.inHours.toString()});
    } else {
      return localizations.translate('just_now');
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    color: Colors.black54,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar({
    required BuildContext context,
    required Color accentColor,
    required AppLocalizations localizations,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 3,
            blurRadius: 10,
          ),
        ],
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton.icon(
          onPressed: _startChat,
          icon: _isChatLoading
              ? Container(
            width: 24,
            height: 24,
            padding: const EdgeInsets.all(2.0),
            child: const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          )
              : const Icon(Icons.chat_bubble_outline, color: Colors.white),
          label: Text(
            localizations.translate('buddy_details_chat_button'),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: secondaryTextColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: primaryTextColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this.child);
  final Widget child;
  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
