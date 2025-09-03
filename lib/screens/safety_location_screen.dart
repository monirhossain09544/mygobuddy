import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:location/location.dart';
import 'package:mygobuddy/providers/safety_location_provider.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:supabase_flutter/supabase_flutter.dart';

class SafetyLocationScreen extends StatefulWidget {
  const SafetyLocationScreen({super.key});

  @override
  State<SafetyLocationScreen> createState() => _SafetyLocationScreenState();
}

class _SafetyLocationScreenState extends State<SafetyLocationScreen> with AutomaticKeepAliveClientMixin {
  final String _trackingPageBaseUrl = 'https://mygobuddy-location-tracking.vercel.app/';

  bool _isLoading = true;
  String? _errorMessage;
  final Location _location = Location();
  bool _isGettingLocation = false;
  StreamSubscription<Map<String, dynamic>?>? _serviceSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeLocationSharing();
        _listenToServiceUpdates();
      }
    });
  }

  @override
  void dispose() {
    _serviceSubscription?.cancel();
    super.dispose();
  }

  void _listenToServiceUpdates() {
    final service = FlutterBackgroundService();
    _serviceSubscription = service.on('updateSafetyLocationState').listen((data) {
      if (data != null && mounted) {
        final provider = Provider.of<SafetyLocationProvider>(context, listen: false);
        if (data.isEmpty) {
          provider.updateTokenAndExpiry(null, null);
          provider.updateLocation(null);
        } else {
          if (data.containsKey('expires_at')) {
            final expiresAt = DateTime.parse(data['expires_at']);
            provider.updateTokenAndExpiry(provider.shareToken, expiresAt);
          }
          if (data.containsKey('share_token')) {
            provider.updateTokenAndExpiry(data['share_token'], provider.expiresAt);
          }
          if (data.containsKey('lat') && data.containsKey('lng')) {
            provider.updateLocation(LocationData.fromMap({
              'latitude': data['lat'],
              'longitude': data['lng'],
            }));
          }
        }
      }
    });
  }

  Future<void> _initializeLocationSharing() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception("You must be logged in to share your location.");
      }

      await _checkExistingShare();

      final provider = Provider.of<SafetyLocationProvider>(context, listen: false);
      if (provider.shareToken != null) {
        provider.startListeningToLocation(userId);
        if (provider.currentLocation == null) {
          await _getCurrentLocationWithFallback();
        }
      }

      setState(() => _isLoading = false);

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error initializing: ${e.toString()}";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkExistingShare() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final result = await supabase
          .from('safety_shares')
          .select('share_token, expires_at')
          .eq('user_id', userId)
          .maybeSingle();

      final provider = Provider.of<SafetyLocationProvider>(context, listen: false);
      if (result != null) {
        final expiresAt = DateTime.parse(result['expires_at']);
        if (expiresAt.isAfter(DateTime.now())) {
          provider.updateTokenAndExpiry(result['share_token'], expiresAt);
          final service = FlutterBackgroundService();
          if (!(await service.isRunning())) {
            await service.startService();
          }
          service.invoke('startTask', {
            'task': 'startSafetyLocationSharing',
            'expires_at': expiresAt.toIso8601String(),
            'share_token': result['share_token'],
          });
        } else {
          await supabase.from('safety_shares').delete().eq('user_id', userId);
          provider.updateTokenAndExpiry(null, null);
        }
      }
    } catch (e) {
      // Ignore and proceed
    }
  }

  Future<void> _startSharingAndGetLocation() async {
    setState(() => _isLoading = true);
    try {
      await _getCurrentLocationWithFallback();
      await _createShareToken();

      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 3000,
        distanceFilter: 5,
      );
      await _location.enableBackgroundMode(enable: true);

      final service = FlutterBackgroundService();
      if (!(await service.isRunning())) {
        await service.startService();
      }
      final provider = Provider.of<SafetyLocationProvider>(context, listen: false);
      service.invoke('startTask', {
        'task': 'startSafetyLocationSharing',
        'expires_at': provider.expiresAt!.toIso8601String(),
        'share_token': provider.shareToken,
      });

      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        provider.startListeningToLocation(userId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Could not start sharing: ${e.toString()}";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _getCurrentLocationWithFallback() async {
    if (_isGettingLocation) return;
    setState(() => _isGettingLocation = true);

    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) throw Exception("Location service is required.");
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          throw Exception("Location permission is required.");
        }
      }

      if (await ph.Permission.locationAlways.isDenied) {
        await ph.Permission.locationAlways.request();
      }

      await _location.changeSettings(accuracy: LocationAccuracy.high);
      final locationData = await _location.getLocation().timeout(const Duration(seconds: 20));

      if (locationData.latitude != null && locationData.longitude != null) {
        if(mounted) {
          Provider.of<SafetyLocationProvider>(context, listen: false).updateLocation(locationData);
        }
      } else {
        throw Exception('Invalid location data received');
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: ${e.toString()}')),
        );
      }
    } finally {
      if(mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }

  Future<void> _createShareToken() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final newToken = const Uuid().v4();
      final expiresAt = DateTime.now().add(const Duration(hours: 24));

      final result = await supabase.from('safety_shares').upsert({
        'user_id': userId,
        'share_token': newToken,
        'expires_at': expiresAt.toIso8601String(),
      }, onConflict: 'user_id').select('share_token');

      if(mounted) {
        Provider.of<SafetyLocationProvider>(context, listen: false).updateTokenAndExpiry(result.isNotEmpty ? result.first['share_token'] : newToken, expiresAt);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error creating share link: ${e.toString()}";
        });
      }
    }
  }

  Future<void> _stopSharing() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Stop Sharing?',
          style: GoogleFonts.workSans(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF111827),
          ),
        ),
        content: Text(
          'This will permanently invalidate the tracking link.',
          style: GoogleFonts.workSans(
            color: const Color(0xFF6B7280),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.workSans(
                color: const Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Stop Sharing',
              style: GoogleFonts.workSans(
                color: Colors.red.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final service = FlutterBackgroundService();
      service.invoke('startTask', {'task': 'stopSafetyLocationSharing'});

      if(mounted) {
        final provider = Provider.of<SafetyLocationProvider>(context, listen: false);
        provider.updateTokenAndExpiry(null, null);
        provider.updateLocation(null);
        provider.stopListening();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location sharing has been stopped.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop sharing: ${e.toString()}')),
        );
      }
    }
  }

  void _shareLink() {
    final provider = Provider.of<SafetyLocationProvider>(context, listen: false);
    if (provider.shareToken != null) {
      final trackingLink = '$_trackingPageBaseUrl?token=${provider.shareToken}';
      Share.share(
        'I\'m sharing my live location for safety. You can track me in real-time here: $trackingLink\n\nThis link will be active for 24 hours.',
        subject: 'My Live Safety Location',
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please start sharing to get a link.')),
      );
    }
  }

  void _copyLink() {
    final provider = Provider.of<SafetyLocationProvider>(context, listen: false);
    if (provider.shareToken != null) {
      final trackingLink = '$_trackingPageBaseUrl?token=${provider.shareToken}';
      Clipboard.setData(ClipboardData(text: trackingLink));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking link copied to clipboard')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please start sharing to get a link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = Provider.of<SafetyLocationProvider>(context);
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color secondaryTextColor = Color(0xFF6B7280);
    const Color accentColor = Color(0xFFF15808);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: Text(
            'Location Sharing',
            style: GoogleFonts.workSans(
              color: primaryTextColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: backgroundColor,
          surfaceTintColor: backgroundColor,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: accentColor))
            : _errorMessage != null
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.workSans(color: Colors.red.shade700),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _initializeLocationSharing,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Retry', style: GoogleFonts.workSans(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        )
            : SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.08),
                      spreadRadius: 0,
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF19638D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        color: Color(0xFF19638D),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Share a private link with family or friends. They can track your live location on a web map.',
                        style: GoogleFonts.workSans(
                          color: primaryTextColor,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (provider.shareToken != null) ...[
                Text(
                  'Location Sharing Active',
                  style: GoogleFonts.workSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your private tracking link is active. Your location is being updated in the background.',
                  style: GoogleFonts.workSans(
                    color: secondaryTextColor,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                if (provider.currentLocation != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.08),
                          spreadRadius: 0,
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.location_on,
                            color: Colors.green.shade700,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last Known Location',
                                style: GoogleFonts.workSans(
                                  fontWeight: FontWeight.w600,
                                  color: primaryTextColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${provider.currentLocation!.latitude!.toStringAsFixed(6)}, ${provider.currentLocation!.longitude!.toStringAsFixed(6)}',
                                style: GoogleFonts.workSans(
                                  color: secondaryTextColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: IconButton(
                            onPressed: _isGettingLocation ? null : _getCurrentLocationWithFallback,
                            icon: _isGettingLocation
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Icon(Icons.refresh, size: 16),
                            tooltip: 'Refresh Location',
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accentColor,
                        accentColor.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.3),
                        spreadRadius: 0,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(
                      'Share Tracking Link',
                      style: GoogleFonts.workSans(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    onPressed: _shareLink,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(
                      'Copy Link',
                      style: GoogleFonts.workSans(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    onPressed: _copyLink,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryTextColor,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
                  label: Text(
                    'Stop Sharing',
                    style: GoogleFonts.workSans(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: _stopSharing,
                ),
              ] else ...[
                Text(
                  'Sharing is Inactive',
                  style: GoogleFonts.workSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start sharing to generate a private link for your family and friends.',
                  style: GoogleFonts.workSans(
                    color: secondaryTextColor,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.green.shade600,
                        Colors.green.shade500,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade600.withOpacity(0.3),
                        spreadRadius: 0,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_link, size: 18),
                    label: Text(
                      'Start Location Sharing',
                      style: GoogleFonts.workSans(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    onPressed: _startSharingAndGetLocation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.08),
                      spreadRadius: 0,
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.warning_amber_outlined,
                        color: Colors.amber.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Important Notes',
                            style: GoogleFonts.workSans(
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• Location updates roughly every 3-5 seconds.\n• The tracking link expires automatically after 24 hours.\n• Recipients do not need the app to view your location.\n• Keep the app open in the background for best results.\n• Frequent updates consume more battery.',
                            style: GoogleFonts.workSans(
                              color: secondaryTextColor,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
