import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math'; // Added dart:math import for sqrt function
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:location/location.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:mygobuddy/providers/trip_provider.dart';
import 'package:mygobuddy/screens/chat_screen.dart';
import 'package:mygobuddy/screens/client_bookings_screen.dart';
import 'package:mygobuddy/screens/safety_location_screen.dart';
import 'package:mygobuddy/screens/trip_completion_popup.dart'; // Added import for TripCompletionPopup
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart' hide PermissionStatus;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // Added url_launcher import for emergency call functionality
import 'package:flutter_background_service/flutter_background_service.dart'; // Added import for FlutterBackgroundService

class TripScreen extends StatefulWidget {
  const TripScreen({super.key});
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  // State
  Map<String, dynamic>? _bookingDetails;
  bool _isLoading = true;
  StreamSubscription? _tripSubscription;

  bool _clientStyleImageAdded = false;
  bool _buddyStyleImageAdded = false;

  @override
  void initState() {
    super.initState();
    _listenForActiveTrip();
  }

  @override
  void dispose() {
    _tripSubscription?.cancel();
    super.dispose();
  }

  void _listenForActiveTrip() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    _tripSubscription = supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .listen((bookingList) {
      if (!mounted) return;

      // Filter the bookings list for current client and in_progress status
      final filteredBookings = bookingList.where((booking) =>
      booking['client_id'] == userId && booking['status'] == 'in_progress'
      ).toList();

      final completedBookings = bookingList.where((booking) =>
      booking['client_id'] == userId && booking['status'] == 'completed'
      ).toList();

      if (filteredBookings.isEmpty) {
        setState(() => _bookingDetails = null);

        if (completedBookings.isNotEmpty && _bookingDetails != null) {
          final completedBooking = completedBookings.first;
          if (completedBooking['id'] == _bookingDetails!['id']) {
            _showTripCompletionPopup(completedBooking);
          }
        }
      } else {
        final activeBooking = filteredBookings.first;
        if (_bookingDetails == null ||
            _bookingDetails!['id'] != activeBooking['id']) {
          _fetchFullTripDetails(activeBooking['id']);
        }
      }
      if (_isLoading) {
        setState(() => _isLoading = false);
      }
    }, onError: (e) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _showTripCompletionPopup(Map<String, dynamic> completedBooking) async {
    // Fetch full booking details with buddy info
    try {
      final response = await supabase
          .from('bookings')
          .select('*, profiles:buddy_id(*)')
          .eq('id', completedBooking['id'])
          .single();

      final buddyProfile = response['profiles'] as Map<String, dynamic>? ?? {};
      final buddyName = buddyProfile['name'] ?? 'Your Buddy';
      final buddyAvatar = buddyProfile['profile_picture'] ?? '';

      if (mounted) {
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => TripCompletionPopup(
            bookingId: completedBooking['id'],
            buddyName: buddyName,
            buddyImage: buddyAvatar,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error showing trip completion popup: $e');
    }
  }

  Future<void> _fetchFullTripDetails(String bookingId) async {
    try {
      final response = await supabase
          .from('bookings')
          .select('*, profiles:buddy_id(*)')
          .eq('id', bookingId)
          .single();
      if (mounted) {
        setState(() {
          _bookingDetails = response;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bookingDetails = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFF15808)));
    }
    if (_bookingDetails == null) {
      return const ClientBookingsScreen();
    }
    return ActiveTripView(
      key: ValueKey(_bookingDetails!['id']),
      bookingDetails: _bookingDetails!,
    );
  }
}

class ActiveTripView extends StatefulWidget {
  final Map<String, dynamic> bookingDetails;
  const ActiveTripView({super.key, required this.bookingDetails});
  @override
  State<ActiveTripView> createState() => _ActiveTripViewState();
}

class _ActiveTripViewState extends State<ActiveTripView> {
  MapboxMap? _mapboxMap;
  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription? _buddyLocationSubscription;
  StreamSubscription? _bookingStatusSubscription;
  Point? _clientLocation;
  Point? _buddyLocation;
  PointAnnotationManager? _pointAnnotationManager;
  List<PointAnnotation?> _annotations = [];

  Uint8List? _clientMarkerImage;
  Uint8List? _buddyMarkerImage;

  bool _clientStyleImageAdded = false;
  bool _buddyStyleImageAdded = false;

  bool _completionRequested = false;
  bool _buddyConfirmed = false;
  bool _clientConfirmed = false;

  static const Color primaryColor = Color(0xFFF15808);
  static const Color accentColor = Color(0xFF0D9488);
  static const Color backgroundColor = Color(0xFFF9FAFB);
  static const Color textColor = Color(0xFF111827);
  static const Color subtleTextColor = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _loadMarkerImages();
    _initLocationServices();
    _listenForBookingStatusChanges();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _buddyLocationSubscription?.cancel();
    _bookingStatusSubscription?.cancel();
    _stopLiveLocation();
    super.dispose();
  }

  void _listenForBookingStatusChanges() {
    _bookingStatusSubscription = supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', widget.bookingDetails['id'])
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

        // Show completion request dialog if buddy requested and client hasn't confirmed yet
        if (completionRequested && buddyConfirmed && !clientConfirmed) {
          _showCompletionRequestDialog();
        }

        // If both confirmed, the trip will be completed automatically by the database trigger
        if (bothConfirmed && booking['status'] == 'completed') {
          _handleTripCompleted();
        }
      }
    });
  }

  void _showCompletionRequestDialog() {
    final l10n = AppLocalizations.of(context);
    final buddyProfile = widget.bookingDetails['profiles'] as Map<String, dynamic>? ?? {};
    final buddyName = buddyProfile['name'] ?? l10n.translate('trip_screen_your_buddy');

    showDialog(
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
                l10n.translate('trip_screen_completion_request_title'),
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
                l10n.translate('trip_screen_completion_request_content', args: {'buddy_name': buddyName}),
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
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        backgroundColor: Colors.grey.shade50,
                      ),
                      child: Text(
                        l10n.translate('trip_screen_button_not_yet'),
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
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _confirmTripCompletion();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: primaryColor.withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        l10n.translate('trip_screen_button_confirm_completion'),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
  }

  Future<void> _confirmTripCompletion() async {
    final l10n = AppLocalizations.of(context);
    try {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final success = await tripProvider.confirmTripCompletion(
        widget.bookingDetails['id'],
        'client',
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.translate('trip_screen_completion_confirmed')),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to confirm trip completion');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('trip_screen_error_confirm_completion')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _requestTripCompletion() async {
    final l10n = AppLocalizations.of(context);

    // Show confirmation dialog
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
                l10n.translate('trip_screen_request_completion_title'),
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
                l10n.translate('trip_screen_request_completion_content'),
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
                        l10n.translate('button_cancel'),
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        l10n.translate('trip_screen_button_request_completion'),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
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

    // Request completion confirmation from buddy
    try {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final success = await tripProvider.requestTripCompletionConfirmation(widget.bookingDetails['id']);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.translate('trip_screen_completion_requested')),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to request completion confirmation');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('trip_screen_error_request_completion')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadMarkerImages() async {
    final clientAvatarUrl = supabase.auth.currentUser?.userMetadata?['avatar_url'];
    final buddyProfile = widget.bookingDetails['profiles'] as Map<String, dynamic>? ?? {};
    final buddyAvatarUrl = buddyProfile['profile_picture'];

    try {
      _clientMarkerImage = await _getMarkerImage(clientAvatarUrl);
      _buddyMarkerImage = await _getMarkerImage(buddyAvatarUrl);
      if (mounted) {
        setState(() {});
        // If the map is ready, update the markers now that images are loaded
        if (_mapboxMap != null) {
          _updateMarkersOnMap();
        }
      }
    } catch (e) {
      print("Error loading marker images: $e");
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('trip_screen_error_markers', args: {'error': e.toString()}))),
        );
      }
    }
  }

  Future<Uint8List> _getMarkerImage(String? url) async {
    Uint8List imageBytes;

    if (url != null && url.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          imageBytes = response.bodyBytes;
        } else {
          return await _createDefaultAvatar();
        }
      } catch (e) {
        print('Failed to load image from $url: $e');
        return await _createDefaultAvatar();
      }
    } else {
      return await _createDefaultAvatar();
    }

    return await _createCircularMarker(imageBytes);
  }

  Future<Uint8List> _createDefaultAvatar() async {
    const double size = 80.0;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    // Draw outer white border
    final Paint outerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      outerBorderPaint,
    );

    // Draw inner orange border
    final Paint innerBorderPaint = Paint()
      ..color = const Color(0xFFF15808)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      (size / 2) - 2,
      innerBorderPaint,
    );

    // Draw default avatar background
    final Paint avatarPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      (size / 2) - 4,
      avatarPaint,
    );

    // Draw person icon
    final Paint iconPaint = Paint()
      ..color = Colors.grey.shade600
      ..style = PaintingStyle.fill;

    // Draw head
    canvas.drawCircle(
      const Offset(size / 2, size / 2 - 8),
      8,
      iconPaint,
    );

    // Draw body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(size / 2 - 12, size / 2 + 4, 24, 20),
        const Radius.circular(12),
      ),
      iconPaint,
    );

    final ui.Picture picture = recorder.endRecording();
    final ui.Image markerImage = await picture.toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await markerImage.toByteData(format: ui.ImageByteFormat.png);

    markerImage.dispose();

    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createCircularMarker(Uint8List imageBytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ui.Image originalImage = frameInfo.image;

    const double size = 80.0;
    const double borderWidth = 4.0;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final Paint outerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      outerBorderPaint,
    );

    final Paint innerBorderPaint = Paint()
      ..color = const Color(0xFFF15808)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      (size / 2) - borderWidth / 2,
      innerBorderPaint,
    );

    final Path clipPath = Path()
      ..addOval(Rect.fromCircle(
        center: const Offset(size / 2, size / 2),
        radius: (size / 2) - borderWidth,
      ));
    canvas.clipPath(clipPath);

    final double imageSize = size - (borderWidth * 2);
    canvas.drawImageRect(
      originalImage,
      Rect.fromLTWH(0, 0, originalImage.width.toDouble(), originalImage.height.toDouble()),
      Rect.fromLTWH(borderWidth, borderWidth, imageSize, imageSize),
      Paint()..filterQuality = FilterQuality.high,
    );

    final ui.Picture picture = recorder.endRecording();
    final ui.Image markerImage = await picture.toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await markerImage.toByteData(format: ui.ImageByteFormat.png);

    originalImage.dispose();
    markerImage.dispose();

    return byteData!.buffer.asUint8List();
  }

  void _initLocationServices() async {
    final buddyId = widget.bookingDetails['buddy_id'];
    if (buddyId == null) return;
    final location = Location();
    await location.requestService();
    if (await location.hasPermission() == PermissionStatus.denied) {
      await location.requestPermission();
    }
    // Request background location permission
    if (await Permission.locationAlways.isDenied) {
      await Permission.locationAlways.request();
    }
    await location.changeSettings(interval: 5000, distanceFilter: 10);
    await location.enableBackgroundMode(enable: true);
    _locationSubscription =
        location.onLocationChanged.listen((LocationData currentLocation) {
          if (mounted &&
              currentLocation.latitude != null &&
              currentLocation.longitude != null) {
            final newClientLocation = Point(
                coordinates:
                Position(currentLocation.longitude!, currentLocation.latitude!));
            setState(() => _clientLocation = newClientLocation);
            _updateMarkersOnMap();
            _updateClientLocationInDb(currentLocation);
          }
        });

    _buddyLocationSubscription = supabase
        .from('live_locations')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', buddyId)
        .listen((locationDataList) {
      if (!mounted || locationDataList.isEmpty) return;

      final buddyLocationData = locationDataList.first;
      _parseBuddyLocation(buddyLocationData, buddyId);
    });
  }

  Future<void> _parseBuddyLocation(Map<String, dynamic> locationData, String buddyId) async {
    try {
      final response = await supabase.rpc('get_location_coordinates', params: {
        'user_id_param': buddyId,
      });

      if (response != null && response is List && response.isNotEmpty) {
        final coords = response.first;
        if (coords['latitude'] != null && coords['longitude'] != null) {
          final latitude = coords['latitude'].toDouble();
          final longitude = coords['longitude'].toDouble();
          final newBuddyLocation = Point(coordinates: Position(longitude, latitude));
          if (mounted) {
            setState(() => _buddyLocation = newBuddyLocation);
            _updateMarkersOnMap();
            print('[v0] Updated buddy location: lat=$latitude, lng=$longitude');
          }
        }
      }
    } catch (e) {
      print('[v0] Error parsing buddy location: $e');
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _mapboxMap?.annotations.createPointAnnotationManager().then((manager) {
      if (mounted) {
        _pointAnnotationManager = manager;
        // If location and images are already loaded, update the markers
        if (_clientLocation != null && _clientMarkerImage != null) _updateMarkersOnMap();
        if (_buddyLocation != null && _buddyMarkerImage != null) _updateMarkersOnMap();
      }
    });
  }

  Future<void> _updateMarkersOnMap() async {
    final map = _mapboxMap;
    if (map == null) {
      print('[v0] Map is null, cannot update markers');
      return;
    }

    print('[v0] Starting marker update - clientImage: ${_clientMarkerImage != null}, buddyImage: ${_buddyMarkerImage != null}');
    print('[v0] Client location: $_clientLocation, Buddy location: $_buddyLocation');

    try {
      if (!_clientStyleImageAdded && _clientMarkerImage != null) {
        await map.style.addStyleImage(
          'client-marker',
          1.0,
          MbxImage(width: 80, height: 80, data: _clientMarkerImage!),
          false,
          [],
          [],
          null,
        );
        _clientStyleImageAdded = true;
        print('[v0] Added client style image');
      }

      if (!_buddyStyleImageAdded && _buddyMarkerImage != null) {
        await map.style.addStyleImage(
          'buddy-marker',
          1.0,
          MbxImage(width: 80, height: 80, data: _buddyMarkerImage!),
          false,
          [],
          [],
          null,
        );
        _buddyStyleImageAdded = true;
        print('[v0] Added buddy style image');
      }

      // Clear existing annotations
      await _pointAnnotationManager?.deleteAll();

      List<PointAnnotationOptions> optionsList = [];

      double clientLatOffset = 0.0;
      double clientLngOffset = 0.0;
      double buddyLatOffset = 0.0;
      double buddyLngOffset = 0.0;

      // Check if markers are too close together and add offset
      if (_clientLocation != null && _buddyLocation != null) {
        final clientLat = _clientLocation!.coordinates.lat.toDouble();
        final clientLng = _clientLocation!.coordinates.lng.toDouble();
        final buddyLat = _buddyLocation!.coordinates.lat.toDouble();
        final buddyLng = _buddyLocation!.coordinates.lng.toDouble();
        final distance = _calculateDistance(clientLat, clientLng, buddyLat, buddyLng);

        print('[v0] Distance between markers: ${distance.toStringAsFixed(2)}m');

        // If markers are too close (less than 20 meters), add small offset
        if (distance < 20) {
          print('[v0] Markers too close, adding offset for visibility');
          // Offset client marker slightly north-east
          clientLatOffset = 0.0002; // ~22 meters north
          clientLngOffset = 0.0002; // ~22 meters east
          // Offset buddy marker slightly south-west
          buddyLatOffset = -0.0002; // ~22 meters south
          buddyLngOffset = -0.0002; // ~22 meters west
        }
      }

      // Add client marker if available
      if (_clientLocation != null && _clientStyleImageAdded) {
        final offsetLat = _clientLocation!.coordinates.lat.toDouble() + clientLatOffset;
        final offsetLng = _clientLocation!.coordinates.lng.toDouble() + clientLngOffset;
        print('[v0] Adding client marker at: lat=$offsetLat, lng=$offsetLng (offset: $clientLatOffset, $clientLngOffset)');
        optionsList.add(PointAnnotationOptions(
          geometry: Point(coordinates: Position(offsetLng, offsetLat)),
          iconImage: 'client-marker',
          iconSize: 0.6,
        ));
      }

      // Add buddy marker if available
      if (_buddyLocation != null && _buddyStyleImageAdded) {
        final offsetLat = _buddyLocation!.coordinates.lat.toDouble() + buddyLatOffset;
        final offsetLng = _buddyLocation!.coordinates.lng.toDouble() + buddyLngOffset;
        print('[v0] Adding buddy marker at: lat=$offsetLat, lng=$offsetLng (offset: $buddyLatOffset, $buddyLngOffset)');
        optionsList.add(PointAnnotationOptions(
          geometry: Point(coordinates: Position(offsetLng, offsetLat)),
          iconImage: 'buddy-marker',
          iconSize: 0.6,
        ));
      }

      print('[v0] Total markers to create: ${optionsList.length}');

      // Create all markers at once using createMulti
      if (optionsList.isNotEmpty) {
        _annotations = await _pointAnnotationManager?.createMulti(optionsList) ?? [];
        final validAnnotations = _annotations.where((annotation) => annotation != null).cast<PointAnnotation>().toList();
        print('[v0] Created ${validAnnotations.length} markers successfully');

        if (validAnnotations.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_clientLocation != null && _buddyLocation != null) {
            _adjustMapToShowBothMarkers();
          }
        }
      } else {
        print('[v0] No markers to create - missing locations or images');
      }
    } catch (e) {
      print('[v0] Error updating markers: $e');
    }
  }

  Future<void> _updateClientLocationInDb(LocationData locationData) async {
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
      debugPrint('Error updating client location in DB: $e');
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

  void _handleTripCompleted() async {
    await _stopLiveLocation();

    final service = FlutterBackgroundService();
    service.invoke('startTask', {'task': 'stopSafetyLocationSharing'});

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<String?> _getConversationId(String buddyId) async {
    final myUserId = supabase.auth.currentUser?.id;
    final l10n = AppLocalizations.of(context);
    if (myUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translate('trip_screen_not_logged_in'))));
      }
      return null;
    }
    try {
      final data = await supabase.rpc('get_or_create_conversation', params: {
        'p_user_id_one': myUserId,
        'p_user_id_two': buddyId,
      });
      return data as String;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.translate('trip_screen_chat_error', args: {'error': e.toString()}))));
      }
      return null;
    }
  }

  void _adjustMapToShowBothMarkers() {
    if (_mapboxMap == null || _clientLocation == null || _buddyLocation == null) return;

    try {
      final clientLat = _clientLocation!.coordinates.lat.toDouble(); // Cast to double
      final clientLng = _clientLocation!.coordinates.lng.toDouble(); // Cast to double
      final buddyLat = _buddyLocation!.coordinates.lat.toDouble(); // Cast to double
      final buddyLng = _buddyLocation!.coordinates.lng.toDouble(); // Cast to double

      // Calculate center point between both locations
      final centerLat = (clientLat + buddyLat) / 2;
      final centerLng = (clientLng + buddyLng) / 2;

      // Calculate appropriate zoom level based on distance
      final distance = _calculateDistance(clientLat, clientLng, buddyLat, buddyLng);
      double zoom = 15.0;
      if (distance > 1000) zoom = 12.0;
      else if (distance > 500) zoom = 13.0;
      else if (distance > 100) zoom = 14.0;

      _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(centerLng, centerLat)),
          zoom: zoom,
        ),
        null,
      );

      print('[v0] Adjusted map to show both markers - center: ($centerLat, $centerLng), zoom: $zoom, distance: ${distance}m');
    } catch (e) {
      print('[v0] Error adjusting map view: $e');
    }
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371000; // Earth radius in meters
    final double dLat = (lat2 - lat1) * (pi / 180); // Fixed type casting from num to double
    final double dLng = (lng2 - lng1) * (pi / 180); // Fixed type casting from num to double
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLng / 2) * sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(
          children: [
            _buildMap(),
            _buildHeader(),
            _buildMapControls(),
            _buildInfoSheet(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return MapWidget(
      onMapCreated: _onMapCreated,
      cameraOptions: CameraOptions(
        center:
        _clientLocation ?? Point(coordinates: Position(-0.128928, 51.509364)),
        zoom: 15.0,
      ),
      styleUri: MapboxStyles.MAPBOX_STREETS,
    );
  }

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(top: topPadding, left: 8.0, right: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Card(
            elevation: 4,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(l10n.translate('trip_screen_in_progress'),
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 240, right: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                onTap: () {
                  if (_clientLocation != null) {
                    _mapboxMap
                        ?.flyTo(CameraOptions(center: _clientLocation, zoom: 15.0), null);
                  }
                },
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(10.0),
                  child: Icon(Icons.gps_fixed, color: textColor),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildEmergencyButton(),
          ],
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
          child: Icon(Icons.sos_rounded,
              color: Colors.red.shade700),
        ),
      ),
    );
  }

  Future<void> _showEmergencyCallConfirmation() async {
    final l10n = AppLocalizations.of(context);
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
                Text(l10n.translate('trip_screen_emergency_dialog_title'),
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: textColor)),
                const SizedBox(height: 8),
                Text(
                    l10n.translate('trip_screen_emergency_dialog_content'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        color: subtleTextColor, fontSize: 14)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                        child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(l10n.translate('button_cancel'),
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
                        child: Text(l10n.translate('trip_screen_button_call_911'),
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

  Future<void> _callEmergencyServices() async {
    final Uri emergencyNumber = Uri.parse('tel:911');
    if (await canLaunchUrl(emergencyNumber)) {
      await launchUrl(emergencyNumber);
    } else if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('trip_screen_error_emergency_call'))),
      );
    }
  }

  Widget _buildInfoSheet() {
    final l10n = AppLocalizations.of(context);
    final buddyProfile =
        widget.bookingDetails['profiles'] as Map<String, dynamic>? ?? {};
    final buddyName = buddyProfile['name'] ?? l10n.translate('trip_screen_your_buddy');
    final buddyAvatar = buddyProfile['profile_picture'] as String?;
    final service = widget.bookingDetails['service'] ?? l10n.translate('trip_screen_service');
    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.28,
      maxChildSize: 0.6,
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
              _buildDurationDisplay(),
              const SizedBox(height: 16),

              if (_completionRequested) _buildCompletionStatusCard(l10n),
              if (_completionRequested) const SizedBox(height: 16),

              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: (buddyAvatar != null && buddyAvatar.isNotEmpty)
                      ? NetworkImage(buddyAvatar)
                      : null,
                ),
                title: Text(buddyName,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                subtitle:
                Text(service, style: GoogleFonts.poppins(color: subtleTextColor)),
                trailing: ElevatedButton.icon(
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: Text(l10n.translate('trip_screen_contact')),
                  onPressed: () async {
                    final buddyId = widget.bookingDetails['buddy_id'];
                    if (buddyId == null) return;
                    final conversationId = await _getConversationId(buddyId);
                    if (conversationId != null && mounted) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          conversationId: conversationId,
                          otherUserId: buddyId,
                          otherUserName: buddyName,
                          otherUserAvatar: buddyAvatar,
                        ),
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined, color: subtleTextColor),
                title: Text(l10n.translate('trip_screen_share_safety_location'),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                subtitle: Text(l10n.translate('trip_screen_share_location_subtitle'),
                    style: GoogleFonts.poppins()),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const SafetyLocationScreen(),
                  ));
                },
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 16, color: subtleTextColor),
              ),

              if (!_completionRequested) ...[
                const Divider(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(l10n.translate('trip_screen_button_end_trip')),
                    onPressed: _requestTripCompletion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: primaryColor.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompletionStatusCard(AppLocalizations l10n) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (_buddyConfirmed && _clientConfirmed) {
      statusText = l10n.translate('trip_screen_completion_both_confirmed');
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (_buddyConfirmed && !_clientConfirmed) {
      statusText = l10n.translate('trip_screen_completion_buddy_confirmed');
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_empty;
    } else if (!_buddyConfirmed && _clientConfirmed) {
      statusText = l10n.translate('trip_screen_completion_client_confirmed');
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_empty;
    } else {
      statusText = l10n.translate('trip_screen_completion_requested');
      statusColor = Colors.blue;
      statusIcon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              statusText,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: statusColor,
                fontSize: 14,
              ),
            ),
          ),
          if (_buddyConfirmed && !_clientConfirmed)
            ElevatedButton(
              onPressed: _confirmTripCompletion,
              style: ElevatedButton.styleFrom(
                backgroundColor: statusColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                l10n.translate('trip_screen_button_confirm'),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDurationDisplay() {
    final l10n = AppLocalizations.of(context);
    return Consumer<TripProvider>(
      builder: (context, tripProvider, child) {
        final duration = tripProvider.getTripDuration(widget.bookingDetails['id'] ?? '');
        final hours = duration.inHours.toString().padLeft(2, '0');
        final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
        final isPaused = tripProvider.isPaused;

        return Column(
          children: [
            Text(l10n.translate('trip_screen_duration'),
                style: GoogleFonts.poppins(
                    color: subtleTextColor, letterSpacing: 1.5, fontSize: 12)),
            const SizedBox(height: 8),
            Text(
              '$hours:$minutes:$seconds',
              style: GoogleFonts.poppins(
                fontSize: 36,
                color: isPaused ? Colors.amber.shade800 : textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isPaused)
              Text(
                l10n.translate('trip_screen_paused'),
                style: GoogleFonts.poppins(
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  fontSize: 12,
                ),
              ),
          ],
        );
      },
    );
  }
}
