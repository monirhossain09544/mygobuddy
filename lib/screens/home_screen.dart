import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/providers/home_provider.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/screens/all_buddies_screen.dart';
import 'package:mygobuddy/screens/all_services_screen.dart';
import 'package:mygobuddy/screens/buddy_details_screen.dart';
import 'package:mygobuddy/screens/notifications_screen.dart';
import 'package:mygobuddy/utils/app_icons.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';
import 'package:mygobuddy/screens/search_results_screen.dart';
import 'package:shimmer/shimmer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Use a post-frame callback to ensure the context is available for providers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  Future<void> _refreshData({bool force = false}) async {
    // Ensure the widget is still in the tree.
    if (!mounted) return;

    final profileProvider = context.read<ProfileProvider>();
    final homeProvider = context.read<HomeProvider>();

    // Fetch profile data. The provider will notify listeners, and `context.watch`
    // in the build method will trigger a rebuild.
    await profileProvider.fetchProfile(force: force);

    // After profile is fetched, if the widget is still mounted and we have data,
    // fetch the home data.
    if (mounted && profileProvider.profileData != null) {
      final String? country = profileProvider.profileData?['country'];
      // This call will update the homeProvider and notify its listeners.
      homeProvider.fetchHomeData(
        latitude: profileProvider.latitude,
        longitude: profileProvider.longitude,
        country: country,
        force: force,
      );
    }
  }

  static const Map<String, IconData> _iconMap = {
    'tour': Icons.tour_outlined,
    'move_to_inbox': Icons.move_to_inbox_outlined,
    'directions_run': Icons.directions_run_outlined,
    'pets': Icons.pets_outlined,
    'shopping_cart': Icons.shopping_cart_outlined,
    'translate': Icons.translate_outlined,
    'household': Icons.home_work_outlined,
    'transportation': Icons.directions_car_outlined,
    'pet_care': Icons.pets_outlined,
    'errands': Icons.shopping_bag_outlined,
    'handyman': Icons.build_outlined,
    'default': Icons.miscellaneous_services_outlined,
  };

  static const List<List<Color>> _popularServiceGradients = [
    [Color(0xFF10B981), Color(0xFF34D399)],
    [Color(0xFF3B82F6), Color(0xFF60A5FA)],
    [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    [Color(0xFFEF4444), Color(0xFFF87171)],
    [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
  ];
  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color secondaryTextColor = Color(0xFF6B7280);
    final profileProvider = context.watch<ProfileProvider>();
    final homeProvider = context.watch<HomeProvider>();
    final localizations = AppLocalizations.of(context);
    final profileData = profileProvider.profileData;
    final isLoadingProfile = profileProvider.isLoading;
    final String name =
        profileData?['name'] ?? localizations.translate('home_no_name');
    final String? avatarUrl = profileData?['profile_picture'];
    final String firstName = name.split(' ').first;
    // UPDATED: Get country from the dedicated 'country' column
    final String? country = profileData?['country'];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          toolbarHeight: 70,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: backgroundColor,
            statusBarIconBrightness: Brightness.dark,
          ),
          backgroundColor: backgroundColor,
          elevation: 0,
          surfaceTintColor: backgroundColor,
          title: (isLoadingProfile && profileData == null)
              ? _buildAppBarShimmer()
              : Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
                backgroundColor: Colors.grey[200],
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? const Icon(Icons.person_outline, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.hiUser(firstName),
                    style: GoogleFonts.poppins(
                      color: secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    localizations.welcomeBack,
                    style: GoogleFonts.poppins(
                      color: primaryTextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: SvgPicture.string(AppIcons.notification),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                  );
                },
              ),
            ),
          ],
        ),
        body: CustomScrollView(
          physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async => _refreshData(force: true),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _buildSearchBar(context),
                  ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child:
                    _buildSectionHeader(localizations.availableBuddies, () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AllBuddiesScreen(
                            userLatitude: profileProvider.latitude,
                            userLongitude: profileProvider.longitude,
                            userCountry: country,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  homeProvider.isLoading
                      ? _buildHomeScreenBuddiesListShimmer()
                      : _buildHomeScreenBuddiesList(context,
                      homeProvider.homeScreenBuddies, localizations),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: _buildSectionHeader(localizations.popularServices,
                            () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const AllServicesScreen()),
                          );
                        }),
                  ),
                  const SizedBox(height: 20),
                  homeProvider.isLoading
                      ? _buildPopularServicesListShimmer()
                      : _buildPopularServicesList(
                      context, homeProvider.services, localizations),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: _buildSectionHeader(localizations.expertsForYou,
                            () {},
                        showViewAll: false),
                  ),
                  const SizedBox(height: 20),
                  homeProvider.isLoading
                      ? _buildFeaturedBuddiesListShimmer(context)
                      : _buildFeaturedBuddiesList(context,
                      homeProvider.featuredBuddies, localizations),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScreenBuddiesList(BuildContext context,
      List<Map<String, dynamic>> buddies, AppLocalizations localizations) {
    final homeProvider = context.watch<HomeProvider>();
    if (buddies.isEmpty && !homeProvider.isLoading) {
      return SizedBox(
        height: 210,
        child: Center(child: Text(AppLocalizations.of(context).noBuddiesFound)),
      );
    }
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        clipBehavior: Clip.none,
        itemCount: buddies.length,
        itemBuilder: (context, index) {
          final buddy = buddies[index];
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: BuddyCard(
              buddyId: buddy['id'],
              buddy: buddy,
              localizations: localizations,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHomeScreenBuddiesListShimmer() {
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        clipBehavior: Clip.none,
        itemCount: 3,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Container(
                width: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppBarShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 120,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPopularServicesListShimmer() {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Container(
                width: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedBuddiesListShimmer(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 2,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const SearchResultsScreen(initialService: null)),
        );
      },
      child: Container(
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
        child: AbsorbPointer(
          child: TextField(
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).searchForServices,
              hintStyle: GoogleFonts.poppins(color: const Color(0xFF9CA3AF)),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12.0),
                child: SvgPicture.string(
                  AppIcons.search,
                  colorFilter:
                  const ColorFilter.mode(Color(0xFF6B7280), BlendMode.srcIn),
                ),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 15.0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopularServicesList(BuildContext context,
      List<Map<String, dynamic>> services, AppLocalizations localizations) {
    if (services.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: min(services.length, 6),
        itemBuilder: (context, index) {
          final service = services[index];
          final iconUrl = service['icon_url'] as String?;
          final gradient =
          _popularServiceGradients[index % _popularServiceGradients.length];
          final buddyCount = Random().nextInt(50) + 5;
          final subtitle = localizations
              .translate('home_buddies_count', fallback: '{count} Buddies')
              .replaceAll('{count}', buddyCount.toString());

          final serviceNameKey = service['name_key'] as String? ?? '';
          final englishName = service['name'] as String? ?? 'Service';
          final translatedServiceName =
          localizations.translate(serviceNameKey, fallback: englishName);

          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: PopularServiceCard(
              iconUrl: iconUrl,
              fallbackIcon: _iconMap['default']!,
              title: translatedServiceName,
              subtitle: subtitle,
              gradientColors: gradient,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        SearchResultsScreen(initialService: translatedServiceName),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback onViewAll,
      {bool showViewAll = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
          ),
        ),
        if (showViewAll)
          TextButton(
            onPressed: onViewAll,
            child: Text(
              AppLocalizations.of(context).viewAll,
              style: GoogleFonts.poppins(
                color: const Color(0xFFF15808),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNoFeaturedBuddiesCard(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.manage_search_rounded,
            size: 40,
            color: Colors.grey.shade400,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.findingExperts,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localizations.searchingForBuddies,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedBuddiesList(
      BuildContext context,
      Map<String, Map<String, dynamic>> featuredBuddies,
      AppLocalizations localizations) {
    if (featuredBuddies.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: _buildNoFeaturedBuddiesCard(context),
        ),
      );
    }
    final serviceNameKeys = featuredBuddies.keys.toList();
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        clipBehavior: Clip.none,
        itemCount: serviceNameKeys.length,
        itemBuilder: (context, index) {
          final serviceNameKey = serviceNameKeys[index];
          final buddy = featuredBuddies[serviceNameKey]!;
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FeaturedServiceBuddyCard(
              buddy: buddy,
              serviceNameKey: serviceNameKey,
              localizations: localizations,
            ),
          );
        },
      ),
    );
  }
}

class PopularServiceCard extends StatelessWidget {
  final String? iconUrl;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  const PopularServiceCard({
    super.key,
    this.iconUrl,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        height: 110,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -10,
              right: -10,
              child: (iconUrl != null && iconUrl!.isNotEmpty)
                  ? Image.network(
                iconUrl!,
                width: 80,
                height: 80,
                fit: BoxFit.contain,
                color: Colors.white.withOpacity(0.15),
                colorBlendMode: BlendMode.modulate,
                errorBuilder: (context, error, stackTrace) => Icon(
                  fallbackIcon,
                  size: 80,
                  color: Colors.white.withOpacity(0.15),
                ),
              )
                  : Icon(
                fallbackIcon,
                size: 80,
                color: Colors.white.withOpacity(0.15),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BuddyCard extends StatelessWidget {
  final String buddyId;
  final Map<String, dynamic> buddy;
  final AppLocalizations localizations;

  const BuddyCard({
    super.key,
    required this.buddyId,
    required this.buddy,
    required this.localizations,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => BuddyDetailsScreen(buddyId: buddyId)),
        );
      },
      child: Container(
        width: 160,
        height: 210,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackgroundImage(),
            _buildGradientOverlay(),
            _buildCardContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundImage() {
    final imageUrl = buddy['profile_picture'] as String? ?? '';
    return (imageUrl.isNotEmpty && imageUrl.startsWith('http'))
        ? Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey.shade300,
        child: Icon(Icons.person, size: 50, color: Colors.grey.shade500),
      ),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2.0, color: Colors.white));
      },
    )
        : Image.asset(
      'assets/images/sam_wilson.png', // Fallback
      fit: BoxFit.cover,
    );
  }

  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.4, 1.0],
        ),
      ),
    );
  }

  Widget _buildCardContent(BuildContext context) {
    final name = buddy['name'] ?? localizations.translate('home_no_name');

    String service;
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

      service = primaryService.isNotEmpty ? primaryService : localizations.translate('home_general_help');
    } else {
      service = localizations.translate('home_general_help');
    }

    final ratingValue = buddy['rating'];
    final rating = (ratingValue is num)
        ? ratingValue.toStringAsFixed(1)
        : localizations.translate('home_not_applicable');
    final isOnline = buddy['is_online'] ?? false;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            name,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [const Shadow(blurRadius: 1, color: Colors.black54)],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            service,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.white.withOpacity(0.9),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.star_rounded,
                  color: Color(0xFFFFC700), size: 16),
              const SizedBox(width: 4),
              Text(
                rating,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              _OnlineStatusPill(isOnline: isOnline, localizations: localizations),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnlineStatusPill extends StatelessWidget {
  final bool isOnline;
  final AppLocalizations localizations;

  const _OnlineStatusPill({required this.isOnline, required this.localizations});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color:
        isOnline ? const Color(0xFF10B981) : Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            color: isOnline ? Colors.white : Colors.grey.shade400,
            size: 7,
          ),
          const SizedBox(width: 4),
          Text(
            isOnline
                ? localizations.translate('home_online')
                : localizations.translate('home_offline'),
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class FeaturedServiceBuddyCard extends StatelessWidget {
  final Map<String, dynamic> buddy;
  final String serviceNameKey;
  final AppLocalizations localizations;

  const FeaturedServiceBuddyCard({
    super.key,
    required this.buddy,
    required this.serviceNameKey,
    required this.localizations,
  });
  @override
  Widget build(BuildContext context) {
    final name = buddy['name'] ?? localizations.translate('home_no_name');
    final imageUrl = buddy['profile_picture'] as String? ?? '';
    final rating = (buddy['rating'] as num?)?.toStringAsFixed(1) ??
        localizations.translate('home_not_applicable');
    final reviewCount = buddy['review_count']?.toString() ?? '0';

    final homeProvider = Provider.of<HomeProvider>(context, listen: false);
    final service = homeProvider.services.firstWhere(
          (s) => s['name_key'] == serviceNameKey,
      orElse: () => {'name': serviceNameKey},
    );
    final englishName = service['name'] as String;
    final translatedServiceName =
    localizations.translate(serviceNameKey, fallback: englishName);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => BuddyDetailsScreen(buddyId: buddy['id'])),
        );
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: 180,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF4A2A0B).withOpacity(0.95),
              const Color(0xFF252525),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A2A0B).withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -20,
              right: -20,
              child: Icon(
                Icons.verified_user_outlined,
                size: 120,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.expertIn,
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              translatedServiceName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        backgroundImage:
                        (imageUrl.isNotEmpty && imageUrl.startsWith('http'))
                            ? NetworkImage(imageUrl)
                            : null,
                        child: (imageUrl.isEmpty)
                            ? const Icon(Icons.person_outline,
                            size: 28, color: Colors.white70)
                            : null,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '$rating ($reviewCount ${localizations.reviews})',
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF15808),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          localizations.viewProfile,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
