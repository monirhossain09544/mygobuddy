import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart' as loc;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/providers/trip_provider.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/screens/chat_screen.dart';
import 'package:mygobuddy/screens/safety_location_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:permission_handler/permission_handler.dart' hide PermissionStatus;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class BuddyTripScreen extends StatefulWidget {
  final String bookingId;
  final String? clientProfileImageUrl;
  const BuddyTripScreen({super.key, required this.bookingId, this.clientProfileImageUrl});
  @override
  State<BuddyTripScreen> createState() => _BuddyTripScreenState();
}

class _BuddyTripScreenState extends State<BuddyTripScreen> with TickerProviderStateMixin {
  // State
  Map<String, dynamic>? _bookingDetails;
  String? _translatedService;
  bool _isLoading = true;
  String? _errorMessage;
  double _buttonBottomOffset = 0;

  bool _completionRequested = false;
  bool _buddyConfirmed = false;
  bool _clientConfirmed = false;
  StreamSubscription? _bookingStatusSubscription;

  // Map & Location
  MapboxMap? _mapboxMap;
  bool _isMapDisposed = false;
  PointAnnotationManager? _pointAnnotationManager;
  List<PointAnnotation?> _annotations = <PointAnnotation?>[];

  // The raw image data for the markers
  Uint8List? _buddyMarkerImage;
  Uint8List? _clientMarkerImage;

  StreamSubscription<loc.LocationData>? _locationSubscription;
  StreamSubscription? _clientLocationSubscription;
  Point? _buddyLocation;
  Point? _clientLocation;

  // Throttling and camera control variables
  DateTime _lastBuddyMapUpdate = DateTime.fromMicrosecondsSinceEpoch(0);
  DateTime _lastClientMapUpdate = DateTime.fromMicrosecondsSinceEpoch(0);
  final Duration _mapUpdateThrottle = const Duration(seconds: 5);
  bool _isMapCentered = false;

  // UI Constants
  static const Color primaryColor = Color(0xFFF15808);
  static const Color accentColor = Color(0xFF0D9488);
  static const Color backgroundColor = Color(0xFFF9FAFB);
  static const Color textColor = Color(0xFF111827);
  static const Color subtleTextColor = Color(0xFF6B7280);
  static const double _initialSheetSize = 0.35;

  // New variables for style images
  bool _buddyStyleImageAdded = false;
  bool _clientStyleImageAdded = false;

  @override
  void initState() {
    super.initState();
    // We need context for localizations, so we fetch details after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchBookingDetails().then((_) {
        if (_bookingDetails != null) {
          _loadMarkerImages();
          _initLocationServices();
          _listenForBookingStatusChanges();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_buttonBottomOffset == 0) {
      _buttonBottomOffset =
          MediaQuery.of(context).size.height * _initialSheetSize + 16;
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _clientLocationSubscription?.cancel();
    _bookingStatusSubscription?.cancel();
    _stopLiveLocation();

    // Dispose map with proper state checking
    if (_mapboxMap != null && !_isMapDisposed) {
      try {
        _mapboxMap!.dispose();
        _isMapDisposed = true;
        _mapboxMap = null;
      } catch (e) {
        debugPrint('Error disposing MapboxMap: $e');
      }
    }

    super.dispose();
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    if (!_isMapDisposed) {
      _mapboxMap = mapboxMap;
      _mapboxMap?.annotations.createPointAnnotationManager().then((manager) {
        if (!_isMapDisposed && mounted) {
          _pointAnnotationManager = manager;
          // If location and images are already loaded, update the markers
          if (_buddyLocation != null && _buddyMarkerImage != null) _updateMarkers();
          if (_clientLocation != null && _clientMarkerImage != null) _updateMarkers();
        }
      });
    }
  }

  Future<void> _loadMarkerImages() async {
    final buddyAvatarUrl = supabase.auth.currentUser?.userMetadata?['avatar_url'];
    final clientAvatarUrl = widget.clientProfileImageUrl;
    try {
      _buddyMarkerImage = await _getMarkerImage(buddyAvatarUrl);
      _clientMarkerImage = await _getMarkerImage(clientAvatarUrl);
      if (mounted) {
        setState(() {});
        // If the map is ready, update the markers now that images are loaded
        if (_mapboxMap != null) {
          _updateMarkers();
        }
      }
    } catch (e) {
      print("Error loading marker images: $e");
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        context.showSnackBar(
          localizations.translate('buddy_trip_error_markers', args: {'error': e.toString()}),
          isError: true,
        );
      }
    }
  }

  Future<Uint8List> _getMarkerImage(String? url) async {
    if (url != null && url.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return await _processImageToCircularMarker(response.bodyBytes);
        }
      } catch (e) {
        print('Failed to load image from $url: $e');
      }
    }
    // Load default image if URL is null, empty, or fails to load.
    final byteData = await rootBundle.load('assets/images/default_marker.png');
    return await _processImageToCircularMarker(byteData.buffer.asUint8List());
  }

  Future<Uint8List> _processImageToCircularMarker(Uint8List imageBytes) async {
    try {
      // Import dart:ui for image processing
      final ui.Codec codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 80,
        targetHeight: 80,
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image originalImage = frameInfo.image;

      // Create a circular image with border
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      const double size = 80.0;
      const double radius = size / 2;

      // Draw outer border (orange)
      final Paint outerBorderPaint = Paint()
        ..color = const Color(0xFFF15808)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(radius, radius), radius, outerBorderPaint);

      // Draw inner border (white)
      final Paint innerBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(radius, radius), radius - 3, innerBorderPaint);

      // Clip to circle and draw the image
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: const Offset(radius, radius), radius: radius - 6)));
      canvas.drawImageRect(
        originalImage,
        Rect.fromLTWH(0, 0, originalImage.width.toDouble(), originalImage.height.toDouble()),
        Rect.fromCircle(center: const Offset(radius, radius), radius: radius - 6),
        Paint(),
      );

      final ui.Picture picture = recorder.endRecording();
      final ui.Image finalImage = await picture.toImage(size.toInt(), size.toInt());
      final ByteData? byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);

      originalImage.dispose();
      finalImage.dispose();

      return byteData!.buffer.asUint8List();
    } catch (e) {
      print('Error processing marker image: $e');
      // Return original bytes if processing fails
      return imageBytes;
    }
  }

  Future<void> _updateMarkers() async {
    if (_pointAnnotationManager == null) return;

    try {
      // Clear existing annotations
      if (_annotations.isNotEmpty) {
        await _pointAnnotationManager!.deleteAll();
        _annotations.clear();
      }

      if (_buddyMarkerImage == null) {
        final buddyProfile = Provider.of<ProfileProvider>(context, listen: false).profile;
        _buddyMarkerImage = await _getMarkerImage(buddyProfile?['profile_picture']);
      }

      if (_clientMarkerImage == null && widget.clientProfileImageUrl != null) {
        _clientMarkerImage = await _getMarkerImage(widget.clientProfileImageUrl);
      }

      if (!_buddyStyleImageAdded && _buddyMarkerImage != null) {
        await _mapboxMap?.style.addStyleImage(
          'buddy-marker',
          1.0,
          MbxImage(width: 80, height: 80, data: _buddyMarkerImage!),
          false, [], [], null,
        );
        _buddyStyleImageAdded = true;
      }

      if (!_clientStyleImageAdded && _clientMarkerImage != null) {
        await _mapboxMap?.style.addStyleImage(
          'client-marker',
          1.0,
          MbxImage(width: 80, height: 80, data: _clientMarkerImage!),
          false, [], [], null,
        );
        _clientStyleImageAdded = true;
      }

      List<PointAnnotationOptions> optionsList = [];

      double distance = 0.0;
      Point? adjustedBuddyLocation = _buddyLocation;
      Point? adjustedClientLocation = _clientLocation;

      if (_buddyLocation != null && _clientLocation != null) {
        distance = _calculateDistance(
          _buddyLocation!.coordinates.lat.toDouble(),
          _buddyLocation!.coordinates.lng.toDouble(),
          _clientLocation!.coordinates.lat.toDouble(),
          _clientLocation!.coordinates.lng.toDouble(),
        );

        print('[v0] Distance between markers: ${distance.toStringAsFixed(1)}m');

        // Apply offset if markers are too close (less than 20 meters apart)
        if (distance < 20) {
          const double offset = 0.0002; // About 22 meters
          adjustedBuddyLocation = Point(coordinates: Position(
            _buddyLocation!.coordinates.lng.toDouble() - offset,
            _buddyLocation!.coordinates.lat.toDouble() + offset,
          ));
          adjustedClientLocation = Point(coordinates: Position(
            _clientLocation!.coordinates.lng.toDouble() + offset,
            _clientLocation!.coordinates.lat.toDouble() - offset,
          ));
          print('[v0] Applied offset - Buddy: ${adjustedBuddyLocation!.coordinates.lat}, ${adjustedBuddyLocation!.coordinates.lng}');
          print('[v0] Applied offset - Client: ${adjustedClientLocation!.coordinates.lat}, ${adjustedClientLocation!.coordinates.lng}');
        }
      }

      // Add buddy marker if available
      if (adjustedBuddyLocation != null && _buddyStyleImageAdded) {
        print('[v0] Adding buddy marker at: lat=${adjustedBuddyLocation.coordinates.lat}, lng=${adjustedBuddyLocation.coordinates.lng}');
        optionsList.add(PointAnnotationOptions(
          geometry: adjustedBuddyLocation,
          iconImage: 'buddy-marker',
          iconSize: 0.6,
        ));
      }

      // Add client marker if available
      if (adjustedClientLocation != null && _clientStyleImageAdded) {
        print('[v0] Adding client marker at: lat=${adjustedClientLocation.coordinates.lat}, lng=${adjustedClientLocation.coordinates.lng}');
        optionsList.add(PointAnnotationOptions(
          geometry: adjustedClientLocation,
          iconImage: 'client-marker',
          iconSize: 0.6,
        ));
      }

      // Create all markers at once using createMulti
      if (optionsList.isNotEmpty) {
        final newAnnotations = await _pointAnnotationManager?.createMulti(optionsList) ?? <PointAnnotation?>[];
        _annotations = List<PointAnnotation?>.from(newAnnotations);

        final validAnnotations = _annotations.whereType<PointAnnotation>().toList();
        print('[v0] Created ${validAnnotations.length} markers successfully');

        if (_buddyLocation != null && _clientLocation != null) {
          final centerLat = (_buddyLocation!.coordinates.lat + _clientLocation!.coordinates.lat) / 2;
          final centerLng = (_buddyLocation!.coordinates.lng + _clientLocation!.coordinates.lng) / 2;

          await _mapboxMap?.flyTo(
            CameraOptions(
              center: Point(coordinates: Position(centerLng, centerLat)),
              zoom: distance < 50 ? 15.0 : 14.0,
            ),
            MapAnimationOptions(duration: 1000),
          );

          print('[v0] Adjusted map to show both markers - center: ($centerLat, $centerLng), zoom: ${distance < 50 ? 15.0 : 14.0}, distance: ${distance.toStringAsFixed(1)}m');
        }
      }
    } catch (e) {
      print('Error updating markers: $e');
    }
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLng = (lng2 - lng1) * (pi / 180);
    final double a = pow(sin(dLat / 2), 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) *
            pow(sin(dLng / 2), 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  Future<void> _fetchBookingDetails() async {
    try {
      final response = await supabase
          .from('bookings')
          .select('*, client:client_id(*)')
          .eq('id', widget.bookingId)
          .single();
      if (mounted) {
        setState(() => _bookingDetails = response);
        if (_bookingDetails?['service'] != null) {
          _fetchTranslatedService(_bookingDetails!['service']);
        }
      }
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        setState(() => _errorMessage = localizations.translate('buddy_trip_error_load_details'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTranslatedService(String serviceName) async {
    if (!mounted) return;
    final localizations = AppLocalizations.of(context);
    try {
      final response = await supabase
          .from('services')
          .select('name_key')
          .eq('name', serviceName)
          .single();
      final nameKey = response['name_key'] as String?;
      if (mounted) {
        setState(() {
          _translatedService = nameKey != null
              ? localizations.translate(nameKey, fallback: serviceName)
              : serviceName;
        });
      }
    } catch (e) {
      debugPrint('Error fetching translated service: $e');
      if (mounted) {
        setState(() {
          _translatedService = serviceName; // Fallback to original name
        });
      }
    }
  }

  Future<void> _updateBuddyLocationInDb(loc.LocationData locationData) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null ||
        locationData.latitude == null ||
        locationData.longitude == null) return;
    final point = 'POINT(${locationData.longitude} ${locationData.latitude})';
    try {
      await supabase.from('live_locations').upsert({
        'user_id': userId,
        'location': point,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error updating buddy location in DB: $e');
    }
  }

  Future<void> _stopLiveLocation() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await supabase.from('live_locations').delete().eq('user_id', userId);
    } catch (e) {
      debugPrint('Error deleting location: $e');
    }
  }

  void _initLocationServices() async {
    final clientId = _bookingDetails?['client_id'];
    if (clientId == null) return;
    final location = loc.Location();
    await location.requestService();
    if (await location.hasPermission() == loc.PermissionStatus.denied) {
      await location.requestPermission();
    }
    if (await Permission.locationAlways.isDenied) {
      await Permission.locationAlways.request();
    }
    await location.changeSettings(interval: 5000, distanceFilter: 10);
    await location.enableBackgroundMode(enable: true);
    _locationSubscription =
        location.onLocationChanged.listen((loc.LocationData currentLocation) {
          if (!mounted ||
              currentLocation.latitude == null ||
              currentLocation.longitude == null) return;
          if (DateTime.now().difference(_lastBuddyMapUpdate) < _mapUpdateThrottle) {
            return;
          }
          _lastBuddyMapUpdate = DateTime.now();
          final newLocation = Point(
              coordinates:
              Position(currentLocation.longitude!, currentLocation.latitude!));
          setState(() => _buddyLocation = newLocation);
          if (!_isMapCentered && _mapboxMap != null && !_isMapDisposed) {
            _mapboxMap?.flyTo(CameraOptions(center: newLocation, zoom: 15.0), null);
            _isMapCentered = true;
          }
          if (Provider.of<TripProvider>(context, listen: false)
              .isTripActive(widget.bookingId)) {
            _updateBuddyLocationInDb(currentLocation);
            _updateMarkers();
          }
        });

    _clientLocationSubscription = supabase
        .from('live_locations')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', clientId)
        .listen((locationDataList) {
      if (!mounted || locationDataList.isEmpty) return;

      if (DateTime.now().difference(_lastClientMapUpdate) < _mapUpdateThrottle) {
        return;
      }
      _lastClientMapUpdate = DateTime.now();

      final clientLocationData = locationDataList.first;
      _parseClientLocation(clientLocationData, clientId);
    });
  }

  void _listenForBookingStatusChanges() {
    _bookingStatusSubscription = supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', widget.bookingId)
        .listen((bookings) {
      if (bookings.isNotEmpty && mounted) {
        final booking = bookings.first;
        final completionRequested = booking['completion_requested_at'] != null;
        final buddyConfirmed = booking['buddy_completion_confirmed'] == true;
        final clientConfirmed = booking['client_completion_confirmed'] == true;
        final bothConfirmed = booking['both_completion_confirmed'] == true;

        setState(() {
          _completionRequested = completionRequested;
          _buddyConfirmed = buddyConfirmed;
          _clientConfirmed = clientConfirmed;
        });

        // If both confirmed, the trip will be completed automatically by the database trigger
        if (bothConfirmed && booking['status'] == 'completed') {
          _handleTripCompleted();
        }
      }
    });
  }

  void _handleTripCompleted() async {
    await _stopLiveLocation();

    final service = FlutterBackgroundService();
    service.invoke('startTask', {'task': 'stopSafetyLocationSharing'});

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _parseClientLocation(Map<String, dynamic> locationData, String clientId) async {
    try {
      final response = await supabase.rpc('get_location_coordinates', params: {
        'user_id_param': clientId,
      });

      if (response != null && response is List && response.isNotEmpty) {
        final coords = response.first;
        if (coords['latitude'] != null && coords['longitude'] != null) {
          final latitude = coords['latitude'].toDouble();
          final longitude = coords['longitude'].toDouble();
          final newClientLocation = Point(coordinates: Position(longitude, latitude));
          if (mounted) {
            setState(() => _clientLocation = newClientLocation);
            _updateMarkers();
            print('[v0] Updated client location: lat=$latitude, lng=$longitude');
          }
        }
      }
    } catch (e) {
      print('[v0] Error parsing client location: $e');
    }
  }

  Future<void> _markAsCompleted() async {
    final localizations = AppLocalizations.of(context);

    // If completion already requested, show different dialog
    if (_completionRequested) {
      _showCompletionStatusDialog(localizations);
      return;
    }

    // Show initial confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey.shade50,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryColor.withOpacity(0.1),
                      primaryColor.withOpacity(0.05),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  size: 40,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                localizations.translate('buddy_trip_request_completion_title'),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              Text(
                localizations.translate('buddy_trip_request_completion_content'),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: subtleTextColor,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        backgroundColor: Colors.grey.shade50,
                      ),
                      child: Text(
                        localizations.translate('button_cancel'),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: subtleTextColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: primaryColor.withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12), // Increased vertical padding and added horizontal padding
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        localizations.translate('buddy_trip_button_request_completion'),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14, // Reduced font size from 16 to 14 for better fit
                          height: 1.2, // Added line height for better text spacing
                        ),
                        textAlign: TextAlign.center, // Center align text
                        maxLines: 2, // Allow text to wrap to 2 lines if needed
                        overflow: TextOverflow.ellipsis, // Handle text overflow gracefully
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Request completion confirmation from client
    try {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final success = await tripProvider.requestTripCompletionConfirmation(widget.bookingId);

      if (success) {
        // Show waiting dialog
        _showWaitingForClientDialog(localizations);
      } else {
        throw Exception('Failed to request completion confirmation');
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
          localizations.translate('buddy_trip_error_request_completion'),
          isError: true,
        );
      }
    }
  }

  void _showCompletionStatusDialog(AppLocalizations localizations) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _clientConfirmed ? Icons.check_circle : Icons.hourglass_empty,
                size: 60,
                color: _clientConfirmed ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 16),

              Text(
                _clientConfirmed
                    ? localizations.translate('buddy_trip_completion_confirmed_title')
                    : localizations.translate('buddy_trip_waiting_client_title'),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              Text(
                _clientConfirmed
                    ? localizations.translate('buddy_trip_completion_confirmed_content')
                    : localizations.translate('buddy_trip_waiting_client_content'),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: subtleTextColor,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    localizations.translate('button_ok'),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWaitingForClientDialog(AppLocalizations localizations) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.shade50,
                ),
                child: Icon(
                  Icons.hourglass_empty,
                  size: 40,
                  color: Colors.orange.shade600,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                localizations.translate('buddy_trip_completion_requested_title'),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              Text(
                localizations.translate('buddy_trip_completion_requested_content'),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: subtleTextColor,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    localizations.translate('button_ok'),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _getConversationId(String clientId) async {
    try {
      final data = await supabase.rpc('get_or_create_conversation', params: {
        'p_other_participant_id': clientId,
      });
      return data as String;
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        context.showSnackBar(
          localizations.translate('buddy_trip_error_chat', args: {'error': e.toString()}),
          isError: true,
        );
      }
      return null;
    }
  }

  Future<void> _callEmergencyServices() async {
    final Uri emergencyNumber = Uri.parse('tel:911');
    if (await canLaunchUrl(emergencyNumber)) {
      await launchUrl(emergencyNumber);
    } else if (mounted) {
      final localizations = AppLocalizations.of(context);
      context.showSnackBar(localizations.translate('buddy_trip_error_emergency_call'));
    }
  }

  Future<void> _showEmergencyCallConfirmation() async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.red.shade100,
                  radius: 30,
                  child: Icon(Icons.sos_rounded,
                      color: Colors.red.shade700, size: 30),
                ),
                const SizedBox(height: 16),
                Text(localizations.translate('buddy_trip_emergency_dialog_title'),
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: textColor)),
                const SizedBox(height: 8),
                Text(
                    localizations.translate('buddy_trip_emergency_dialog_content'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        color: subtleTextColor, fontSize: 14)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                        child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(localizations.translate('button_cancel'),
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: subtleTextColor)))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(localizations.translate('buddy_trip_button_call_911'),
                            style:
                            GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
    if (confirmed == true) {
      await _callEmergencyServices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryColor))
            : _errorMessage != null
            ? Center(child: Text(_errorMessage!, style: GoogleFonts.poppins()))
            : Stack(
          children: [
            _buildMap(),
            _buildHeader(localizations),
            _buildMapControls(),
            _buildInfoSheet(localizations),
            _buildPrimaryControls(localizations),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return MapWidget(
      onMapCreated: _onMapCreated,
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(0, 0)),
        zoom: 1.0,
      ),
      styleUri: MapboxStyles.MAPBOX_STREETS,
    );
  }

  Widget _buildHeader(AppLocalizations localizations) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildMapButton(
              icon: Icons.arrow_back, onPressed: () => Navigator.of(context).pop()),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(localizations.translate('buddy_trip_title'),
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      bottom: _buttonBottomOffset,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMapButton(
            icon: Icons.gps_fixed,
            onPressed: () {
              if (_buddyLocation != null && !_isMapDisposed) {
                _mapboxMap?.flyTo(
                    CameraOptions(center: _buddyLocation, zoom: 15.0),
                    MapAnimationOptions(duration: 1000));
              }
            },
          ),
          const SizedBox(height: 8),
          _buildEmergencyButton(),
        ],
      ),
    );
  }

  Widget _buildMapButton({required IconData icon, required VoidCallback onPressed}) {
    return Card(
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(icon, color: textColor),
        ),
      ),
    );
  }

  Widget _buildEmergencyButton() {
    return Card(
      shape: const CircleBorder(),
      elevation: 4,
      color: Colors.red.shade50,
      child: InkWell(
        onTap: _showEmergencyCallConfirmation,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(Icons.sos_rounded, color: Colors.red.shade700),
        ),
      ),
    );
  }

  Widget _buildInfoSheet(AppLocalizations localizations) {
    final client = _bookingDetails?['client'] as Map<String, dynamic>? ?? {};
    final clientName = client['name'] ?? localizations.translate('client_fallback_name');
    final clientAvatar = client['profile_picture'] as String?;
    final service = _translatedService ?? localizations.translate('service_fallback_name');
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        setState(() {
          final screenHeight = MediaQuery.of(context).size.height;
          _buttonBottomOffset = notification.extent * screenHeight + 16;
        });
        return true;
      },
      child: DraggableScrollableSheet(
        initialChildSize: _initialSheetSize,
        minChildSize: _initialSheetSize,
        maxChildSize: 0.7,
        builder: (BuildContext context, ScrollController scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                _buildDurationDisplay(localizations),
                const SizedBox(height: 16),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: (clientAvatar != null &&
                        clientAvatar.isNotEmpty)
                        ? NetworkImage(clientAvatar)
                        : null,
                  ),
                  title: Text(clientName,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                  subtitle: Text(service,
                      style: GoogleFonts.poppins(color: subtleTextColor)),
                  trailing: IconButton(
                    icon: const Icon(Icons.chat_rounded, color: primaryColor),
                    onPressed: () async {
                      final clientId = _bookingDetails?['client_id'];
                      if (clientId == null) return;
                      final conversationId = await _getConversationId(clientId);
                      if (conversationId != null && mounted) {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            conversationId: conversationId,
                            otherUserId: clientId,
                            otherUserName: clientName,
                            otherUserAvatar: clientAvatar,
                          ),
                        ));
                      }
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shield_outlined, color: subtleTextColor),
                  title: Text(localizations.translate('buddy_trip_share_safety_location_title'),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  subtitle: Text(localizations.translate('buddy_trip_share_safety_location_subtitle'),
                      style: GoogleFonts.poppins()),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => const SafetyLocationScreen(),
                    ));
                  },
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 16, color: subtleTextColor),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDurationDisplay(AppLocalizations localizations) {
    return Consumer<TripProvider>(
      builder: (context, tripProvider, child) {
        final duration = tripProvider.getTripDuration(widget.bookingId);
        final hours = duration.inHours.toString().padLeft(2, '0');
        final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
        return Column(
          children: [
            Text(localizations.translate('buddy_trip_duration_label'),
                style: GoogleFonts.poppins(
                    color: subtleTextColor, letterSpacing: 1.5, fontSize: 12)),
            const SizedBox(height: 8),
            Text('$hours:$minutes:$seconds',
                style: GoogleFonts.poppins(
                    fontSize: 36,
                    color: textColor,
                    fontWeight: FontWeight.bold)),
          ],
        );
      },
    );
  }

  Widget _buildPrimaryControls(AppLocalizations localizations) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, bottomPadding > 0 ? bottomPadding : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                spreadRadius: 5)
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Consumer<TripProvider>(
          builder: (context, tripProvider, child) {
            String endButtonText;
            Color endButtonColor;
            IconData endButtonIcon;

            if (_completionRequested) {
              if (_clientConfirmed) {
                endButtonText = localizations.translate('buddy_trip_button_completing');
                endButtonColor = Colors.green;
                endButtonIcon = Icons.check_circle;
              } else {
                endButtonText = localizations.translate('buddy_trip_button_waiting_client');
                endButtonColor = Colors.orange;
                endButtonIcon = Icons.hourglass_empty;
              }
            } else {
              endButtonText = localizations.translate('buddy_trip_button_end');
              endButtonColor = primaryColor;
              endButtonIcon = Icons.stop_rounded;
            }

            return SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(endButtonIcon),
                label: Text(endButtonText),
                onPressed: _markAsCompleted,
                style: ElevatedButton.styleFrom(
                  backgroundColor: endButtonColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
