import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mygobuddy/providers/location_provider.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:provider/provider.dart';

class LiveLocationViewerScreen extends StatefulWidget {
  final String conversationId;
  final String targetUserId;
  final String targetUserName;
  final String? targetUserAvatar;

  const LiveLocationViewerScreen({
    super.key,
    required this.conversationId,
    required this.targetUserId,
    required this.targetUserName,
    this.targetUserAvatar,
  });

  @override
  State<LiveLocationViewerScreen> createState() =>
      _LiveLocationViewerScreenState();
}

class _LiveLocationViewerScreenState extends State<LiveLocationViewerScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  PointAnnotation? _userAnnotation;
  // **FIX:** Declared as Uint8List? to hold raw image data, not a String.
  Uint8List? _markerImage;
  StreamSubscription? _locationSubscription;
  Point? _targetUserLocation;
  bool _isLoading = true;
  String? _statusMessage;
  bool _styleImageAdded = false;

  @override
  void initState() {
    super.initState();
    _loadMarkerImage();
    _listenToLocationUpdates();
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _mapboxMap?.annotations.createPointAnnotationManager().then((manager) {
      _pointAnnotationManager = manager;
      // If location data arrived before map was ready, update the marker now.
      if (_targetUserLocation != null) {
        _updateMarkerOnMap();
      }
    });
  }

  // **FIX:** Renamed and simplified image loading logic.
  Future<void> _loadMarkerImage() async {
    Uint8List? imageData;
    if (widget.targetUserAvatar != null && widget.targetUserAvatar!.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(widget.targetUserAvatar!));
        if (response.statusCode == 200) {
          imageData = response.bodyBytes;
        }
      } catch (e) {
        debugPrint('Failed to load marker image from URL: $e');
      }
    }

    // Fallback to local asset if network image fails or is not provided.
    if (imageData == null) {
      final ByteData byteData = await rootBundle.load('assets/images/default_marker.png');
      imageData = byteData.buffer.asUint8List();
    }

    if (mounted) {
      setState(() {
        _markerImage = imageData;
      });
    }
  }

  Future<void> _updateMarkerOnMap() async {
    final location = _targetUserLocation;
    final markerImg = _markerImage;
    final map = _mapboxMap;
    final manager = _pointAnnotationManager;

    if (location == null || markerImg == null || map == null || manager == null) {
      return;
    }

    // Add the image to the map's style only once.
    if (!_styleImageAdded) {
      await map.style.addStyleImage(
        'user-marker', // The String ID for the image
        1.0,
        // **FIX:** Pass the Uint8List data to MbxImage
        MbxImage(width: 80, height: 80, data: markerImg),
        false, [], [], null,
      );
      _styleImageAdded = true;
    }

    if (_userAnnotation == null) {
      final options = PointAnnotationOptions(
        geometry: location,
        iconImage: 'user-marker', // Reference the image by its String ID
        iconSize: 0.7,
      );
      _userAnnotation = await manager.create(options);
    } else {
      _userAnnotation!.geometry = location;
      await manager.update(_userAnnotation!);
    }
  }

  void _listenToLocationUpdates() {
    _locationSubscription = supabase
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('id', widget.conversationId)
        .listen((data) {
      if (!mounted) return;

      if (data.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Conversation not found or data is unavailable.';
          });
        }
        return;
      }

      final conversation = data.first;
      final user1Id = conversation['participant_one_id'];
      final user2Id = conversation['participant_two_id'];
      double? lat;
      double? lon;
      String? expiresAtStr;

      if (user1Id == widget.targetUserId) {
        lat = conversation['user1_live_latitude'] as double?;
        lon = conversation['user1_live_longitude'] as double?;
        expiresAtStr = conversation['user1_live_expires_at'] as String?;
      } else if (user2Id == widget.targetUserId) {
        lat = conversation['user2_live_latitude'] as double?;
        lon = conversation['user2_live_longitude'] as double?;
        expiresAtStr = conversation['user2_live_expires_at'] as String?;
      }

      final expiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;
      if (expiresAt == null || expiresAt.isBefore(DateTime.now().toUtc())) {
        setState(() {
          _isLoading = false;
          _targetUserLocation = null;
          _statusMessage = 'Live location sharing has ended.';
        });
        if (_userAnnotation != null) {
          _pointAnnotationManager?.delete(_userAnnotation!);
          _userAnnotation = null;
        }
        return;
      }

      if (lat != null && lon != null) {
        final newPosition = Point(coordinates: Position(lon, lat));
        setState(() {
          _targetUserLocation = newPosition;
          _isLoading = false;
          _statusMessage = null;
        });

        _mapboxMap?.flyTo(
          CameraOptions(center: newPosition, zoom: 16.0),
          MapAnimationOptions(duration: 1500, startDelay: 0),
        );
        _updateMarkerOnMap();
      } else if (_targetUserLocation == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Waiting for location data...';
        });
      }
    }, onError: (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error fetching location: ${error.toString()}';
        });
      }
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapboxMap?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = Provider.of<LocationProvider>(context);
    final currentUserId = supabase.auth.currentUser!.id;
    final isCurrentUserSharing = locationProvider.isSharingLocation &&
        locationProvider.activeConversationId == widget.conversationId &&
        widget.targetUserId == currentUserId;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black54, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.targetUserName,
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _buildBody(isCurrentUserSharing),
    );
  }

  Widget _buildBody(bool isCurrentUserSharing) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_targetUserLocation == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _statusMessage ?? 'Location not available.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 16),
          ),
        ),
      );
    }

    return Stack(
      children: [
        MapWidget(
          onMapCreated: _onMapCreated,
          cameraOptions: CameraOptions(
            center: _targetUserLocation,
            zoom: 16.0,
          ),
          styleUri: MapboxStyles.MAPBOX_STREETS,
        ),
        if (isCurrentUserSharing)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              color: Colors.white,
              child: SafeArea(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Provider.of<LocationProvider>(context, listen: false).stopSharing();
                    Navigator.of(context).pop();
                  },
                  child: Consumer<LocationProvider>(
                    builder: (context, provider, child) {
                      final remaining = provider.remainingTime;
                      return Text(
                        'Stop Sharing (${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')} remaining)',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
