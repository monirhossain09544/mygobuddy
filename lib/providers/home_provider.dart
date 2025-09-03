import 'package:flutter/foundation.dart';
import 'package:mygobuddy/utils/constants.dart';

class HomeProvider with ChangeNotifier {
  bool _isLoading = true;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _homeScreenBuddies = [];
  Map<String, Map<String, dynamic>> _featuredBuddies = {};
  String? _errorMessage;

  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get services => _services;
  List<Map<String, dynamic>> get homeScreenBuddies => _homeScreenBuddies;
  Map<String, Map<String, dynamic>> get featuredBuddies => _featuredBuddies;
  String? get errorMessage => _errorMessage;

  Future<void> fetchHomeData({
    required double? latitude,
    required double? longitude,
    required String? country,
    bool force = false,
  }) async {
    if (_services.isNotEmpty && !force) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    if (force) {
      notifyListeners();
    }

    try {
      if (country == null || country.isEmpty) {
        _errorMessage = 'User country is not set. Cannot fetch local buddies.';
        debugPrint(_errorMessage);
        _isLoading = false;
        _homeScreenBuddies = [];
        _featuredBuddies = {};
        notifyListeners();
        return;
      }

      debugPrint('[v0] HOME PROVIDER: Fetching buddies for country: $country');
      debugPrint('[v0] HOME PROVIDER: User location - lat: $latitude, lng: $longitude');

      Future<dynamic> homeBuddiesFuture;
      if (latitude != null && longitude != null) {
        debugPrint('[v0] HOME PROVIDER: Using location-based buddy search');
        homeBuddiesFuture = supabase.rpc('get_buddies_within_radius', params: {
          'user_lat': latitude,
          'user_long': longitude,
          'radius_km': 25.0,
          'client_country': country,
        });
      } else {
        debugPrint('[v0] HOME PROVIDER: Using country-based buddy search');
        homeBuddiesFuture = supabase.rpc('get_top_rated_buddies_by_country', params: {
          'p_country_name': country,
        });
      }

      var topBuddiesQuery = supabase
          .from('buddies')
          .select(
          'id, name, profile_picture, rating, bio, review_count, country')
          .eq('country', country)
          .order('rating', ascending: false)
          .limit(50);

      final List<Future<dynamic>> futures = [
        supabase.from('services').select('name, icon_url, name_key').order('id'),
        topBuddiesQuery,
        homeBuddiesFuture,
      ];

      final results = await Future.wait(futures);

      _services = List<Map<String, dynamic>>.from(results[0] as List);
      final allTopBuddies =
      List<Map<String, dynamic>>.from(results[1] as List);
      _homeScreenBuddies =
      List<Map<String, dynamic>>.from(results[2] as List);

      debugPrint('[v0] HOME PROVIDER: Fetched ${_homeScreenBuddies.length} home screen buddies');
      for (int i = 0; i < _homeScreenBuddies.length && i < 3; i++) {
        final buddy = _homeScreenBuddies[i];
        debugPrint('[v0] HOME PROVIDER: Buddy ${buddy['name']} - is_available: ${buddy['is_available']}, id: ${buddy['id']}');
      }

      await _generateFeaturedBuddies(allTopBuddies);
    } catch (e) {
      _errorMessage = 'Failed to load home data: ${e.toString()}';
      debugPrint('[v0] HOME PROVIDER: Error fetching home data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _generateFeaturedBuddies(List<Map<String, dynamic>> topBuddies) async {
    debugPrint('[v0] Starting _generateFeaturedBuddies with ${topBuddies.length} buddies');
    _featuredBuddies = {};
    final Set<dynamic> usedBuddyIds = {};

    if (_services.isEmpty || topBuddies.isEmpty) {
      debugPrint('[v0] Early return: services=${_services.length}, topBuddies=${topBuddies.length}');
      return;
    }

    try {
      final buddyIds = topBuddies.map((b) => b['id']).toList();
      debugPrint('[v0] Querying buddy_services for ${buddyIds.length} buddy IDs: $buddyIds');

      final buddyServicesResponse = await supabase
          .from('buddy_services')
          .select('buddy_id, service_id, hourly_rate, is_active, services(id, name, name_key)')
          .inFilter('buddy_id', buddyIds)
          .eq('is_active', true);

      final buddyServices = List<Map<String, dynamic>>.from(buddyServicesResponse);
      debugPrint('[v0] Found ${buddyServices.length} buddy services');

      if (buddyServices.isEmpty) {
        debugPrint('[v0] No buddy services found - this is likely the issue!');
        return;
      }

      final Map<String, List<Map<String, dynamic>>> buddyServiceMap = {};
      for (final bs in buddyServices) {
        final buddyId = bs['buddy_id'].toString();
        final serviceData = bs['services'] as Map<String, dynamic>;
        final rate = bs['hourly_rate'] as num? ?? 0;

        if (!buddyServiceMap.containsKey(buddyId)) {
          buddyServiceMap[buddyId] = [];
        }
        buddyServiceMap[buddyId]!.add({
          ...serviceData,
          'rate': rate,
          'position': buddyServiceMap[buddyId]!.length,
        });
      }

      debugPrint('[v0] Built buddy service map for ${buddyServiceMap.length} buddies');

      final List<Map<String, dynamic>> serviceSelections = [];

      for (final buddy in topBuddies) {
        final buddyId = buddy['id']?.toString();
        if (buddyId == null) continue;

        final buddyServicesList = buddyServiceMap[buddyId] ?? [];
        if (buddyServicesList.isEmpty) continue;

        for (final service in buddyServicesList) {
          final serviceRate = service['rate'] as num? ?? 0;
          final servicePosition = service['position'] as int? ?? 0;

          final rateScore = serviceRate / 100.0;
          final primarySkillScore = servicePosition == 0 ? 1.0 : 0.0;
          final diversityScore = 1.0;
          final totalScore = (rateScore * 0.75) + (primarySkillScore * 0.15) + (diversityScore * 0.10);

          serviceSelections.add({
            'buddy': buddy,
            'service': service,
            'score': totalScore,
            'serviceId': service['id'],
            'serviceNameKey': service['name_key'],
          });
        }
      }

      debugPrint('[v0] Generated ${serviceSelections.length} service selections');

      serviceSelections.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      final Set<dynamic> usedServiceIds = {};

      for (final selection in serviceSelections) {
        final serviceId = selection['serviceId'];
        final serviceNameKey = selection['serviceNameKey'] as String?;
        final buddy = selection['buddy'] as Map<String, dynamic>;
        final buddyId = buddy['id']?.toString();

        if (serviceId == null ||
            serviceNameKey == null ||
            buddyId == null ||
            usedServiceIds.contains(serviceId) ||
            usedBuddyIds.contains(buddyId)) {
          continue;
        }

        debugPrint('[v0] SELECTED: Buddy ${buddy['name']} -> Service ID $serviceId (${selection['service']['name']}) with score ${selection['score'].toStringAsFixed(3)}');
        debugPrint('[v0] Service details: rate=${selection['service']['rate']}, position=${selection['service']['position']}, nameKey=$serviceNameKey');

        _featuredBuddies[serviceNameKey] = buddy;
        usedBuddyIds.add(buddyId);
        usedServiceIds.add(serviceId);

        debugPrint('[v0] Added featured buddy: ${buddy['name']} for service: $serviceNameKey');

        if (_featuredBuddies.length >= _services.length) {
          break;
        }
      }

      debugPrint('[v0] Final featured buddies count: ${_featuredBuddies.length}');

    } catch (e) {
      debugPrint('[v0] Error generating featured buddies: ${e.toString()}');
      debugPrint('[v0] Error details: $e');
      _featuredBuddies = {};
    }
  }

  void clearData() {
    _services = [];
    _homeScreenBuddies = [];
    _featuredBuddies = {};
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
  }
}
