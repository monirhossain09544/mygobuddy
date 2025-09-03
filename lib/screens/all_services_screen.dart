import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/search_results_screen.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:shimmer/shimmer.dart';

import '../utils/constants.dart';

class AllServicesScreen extends StatefulWidget {
  const AllServicesScreen({super.key});

  @override
  State<AllServicesScreen> createState() => _AllServicesScreenState();
}

class _AllServicesScreenState extends State<AllServicesScreen> {
  List<Map<String, dynamic>> _services = [];
  bool _isLoading = true;
  final List<List<Color>> _serviceGradients = [
    [const Color(0xFF667eea), const Color(0xFF764ba2)],
    [const Color(0xFFf093fb), const Color(0xFFf5576c)],
    [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
    [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
    [const Color(0xFFfa709a), const Color(0xFFfee140)],
    [const Color(0xFFa8edea), const Color(0xFFfed6e3)],
    [const Color(0xFFffecd2), const Color(0xFFfcb69f)],
    [const Color(0xFFd299c2), const Color(0xFFfef9d7)],
  ];

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    try {
      final response = await supabase
          .from('services')
          .select('name, name_key, icon_url')
          .order('name');
      if (mounted) {
        setState(() {
          _services = List<Map<String, dynamic>>.from(response as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(localizations.translate(
                  'all_services_fetch_error',
                  args: {'error': e.toString()}))),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    final localizations = AppLocalizations.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          elevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: backgroundColor,
            statusBarIconBrightness: Brightness.dark,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.black, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            localizations.translate('all_services_title'),
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _isLoading
              ? _buildShimmerGrid()
              : _services.isEmpty
              ? Center(
            child: Text(
              localizations.translate('all_services_none_found'),
              style:
              GoogleFonts.poppins(color: Colors.grey.shade600),
            ),
          )
              : RefreshIndicator(
            onRefresh: _fetchServices,
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: _services.length,
              itemBuilder: (context, index) {
                final service = _services[index];
                final serviceNameKey =
                    service['name_key'] as String? ?? service['name'];
                final englishServiceName = service['name'] as String;
                final iconUrl = service['icon_url'] as String?;
                final gradientColors = _serviceGradients[index % _serviceGradients.length];

                return ServiceGridCard(
                  serviceNameKey: serviceNameKey,
                  iconUrl: iconUrl,
                  gradientColors: gradientColors,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SearchResultsScreen(
                            initialService: englishServiceName),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.1,
        ),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          );
        },
      ),
    );
  }
}

class ServiceGridCard extends StatelessWidget {
  final String serviceNameKey;
  final String? iconUrl;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const ServiceGridCard({
    super.key,
    required this.serviceNameKey,
    required this.iconUrl,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final translatedServiceName =
    localizations.translate(serviceNameKey, fallback: serviceNameKey);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withOpacity(0.3),
              spreadRadius: 1,
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
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Positioned(
              bottom: -10,
              left: -10,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: _buildServiceIcon(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    translatedServiceName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIcon() {
    if (iconUrl != null && iconUrl!.isNotEmpty) {
      if (iconUrl!.endsWith('.svg')) {
        return SvgPicture.network(
          iconUrl!,
          height: 32,
          width: 32,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          placeholderBuilder: (_) => _buildFallbackIcon(),
        );
      } else {
        return Image.network(
          iconUrl!,
          height: 32,
          width: 32,
          color: Colors.white,
          errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildFallbackIcon();
          },
        );
      }
    }
    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    IconData iconData;

    final serviceName = serviceNameKey.toLowerCase();
    if (serviceName.contains('pet') || serviceName.contains('care')) {
      iconData = Icons.pets;
    } else if (serviceName.contains('shopping') || serviceName.contains('assistance')) {
      iconData = Icons.shopping_bag;
    } else if (serviceName.contains('moving') || serviceName.contains('help')) {
      iconData = Icons.local_shipping;
    } else if (serviceName.contains('laundry')) {
      iconData = Icons.local_laundry_service;
    } else if (serviceName.contains('language') || serviceName.contains('support')) {
      iconData = Icons.translate;
    } else if (serviceName.contains('city') || serviceName.contains('tour')) {
      iconData = Icons.tour;
    } else {
      iconData = Icons.miscellaneous_services;
    }

    return Icon(
      iconData,
      size: 32,
      color: Colors.white,
    );
  }
}
