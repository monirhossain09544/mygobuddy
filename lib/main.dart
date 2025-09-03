import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:location/location.dart' as loc;
import 'package:mygobuddy/firebase_options.dart';
import 'package:mygobuddy/providers/dashboard_provider.dart';
import 'package:mygobuddy/providers/home_provider.dart';
import 'package:mygobuddy/providers/language_provider.dart';
import 'package:mygobuddy/providers/location_provider.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/providers/safety_location_provider.dart';
import 'package:mygobuddy/providers/trip_provider.dart';
import 'package:mygobuddy/screens/buddy_bookings_screen.dart';
import 'package:mygobuddy/screens/buddy_home_screen.dart';
import 'package:mygobuddy/screens/buddy_profile_screen.dart';
import 'package:mygobuddy/screens/home_screen.dart';
import 'package:mygobuddy/screens/messages_screen.dart';
import 'package:mygobuddy/screens/profile_screen.dart';
import 'package:mygobuddy/screens/safety_location_screen.dart';
import 'package:mygobuddy/screens/splash_screen.dart';
import 'package:mygobuddy/screens/trip_screen.dart';
import 'package:mygobuddy/services/notification_service.dart';
import 'package:mygobuddy/services/update_notification_service.dart';
import 'package:mygobuddy/utils/app_icons.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:supabase_flutter/supabase_flutter.dart';

// This is the new, unified background service entry point.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Ensure this only runs in background isolate
  if (service is! AndroidServiceInstance) {
    print('Background Service: Not running on Android, skipping initialization');
    return;
  }

  try {
    // Must be called for plugins to work in the background isolate.
    DartPluginRegistrant.ensureInitialized();
  } catch (e) {
    print('Background Service Error: Failed to initialize plugins: $e');
    return;
  }

  // Initialize Supabase within the background isolate.
  await Supabase.initialize(
    url: 'https://rbzgchesdmyychvpplgq.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJiemdjaGVzZG15eWNodnBwbGdxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2ODMzMDAsImV4cCI6MjA2NjI1OTMwMH0.M5z7Co0If6WO4SKJRv1_8Vcxbh5p615Er_Agebso9Gk',
  );
  Timer? tripTimer;
  Timer? keepAliveTimer;
  Timer? locationCountdownTimer;
  Timer? safetyCountdownTimer;
  StreamSubscription? bookingsSubscription;
  String? currentBuddyId;
  int bookedDurationMinutes = 0;
  DateTime? tripStartTime;
  Duration pausedDuration = Duration.zero;
  DateTime? pauseTime;
// Flags to indicate if location features are active
  bool isLiveLocationActive = false;
  String? liveLocationConversationId;
  bool isSafetyLocationActive = false;
  String? safetyShareToken;
// Function to start listening for new bookings for the buddy
  void startBookingListener(String buddyId) {
    bookingsSubscription?.cancel(); // Cancel any existing listener
    bookingsSubscription = Supabase.instance.client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('buddy_id', buddyId)
        .listen((bookings) {
      for (final booking in bookings) {
        if (booking['status'] == 'confirmed') {
          print('Background Service: New confirmed booking found with ID: ${booking['id']}');
        }
      }
    }, onError: (e) {
      print('Background Service Error: Bookings stream failed: $e');
    });
  }
// Get the current user's ID to know which buddy to listen for.
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser != null) {
    currentBuddyId = currentUser.id;
    startBookingListener(currentBuddyId!);
  } else {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null && currentBuddyId == null) {
        currentBuddyId = session.user.id;
        startBookingListener(currentBuddyId!);
      } else if (session == null) {
        bookingsSubscription?.cancel();
        currentBuddyId = null;
      }
    }, onError: (e) {
      print('Background Service Error: Auth state stream failed: $e');
    });
  }
// New listener to receive location data from the UI thread
  service.on('updateLocation').listen((data) {
    if (data == null) return;
    final lat = data['lat'] as double?;
    final lng = data['lng'] as double?;
    if (lat == null || lng == null) return;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;
    // Handle Safety Location Sharing
    if (isSafetyLocationActive) {
      final point = 'POINT($lng $lat)';
      Supabase.instance.client.from('live_locations').upsert({
        'user_id': currentUserId,
        'location': point,
        'updated_at': DateTime.now().toIso8601String(),
      }).catchError((e) {
        print('Safety Location Error: Failed to update location. $e');
      });
      // Also send location back to UI
      service.invoke('updateSafetyLocationState', {
        'share_token': safetyShareToken,
        'lat': lat,
        'lng': lng,
      });
    }
    // Handle Trip Live Location
    if (isLiveLocationActive && liveLocationConversationId != null) {
      Supabase.instance.client.from('conversations').update({
        'live_latitude': lat,
        'live_longitude': lng,
      }).eq('id', liveLocationConversationId!).catchError((e) {
        print('Live Location Error: Failed to update location. $e');
      });
    }
  }, onError: (e) {
    print('Background Service Error: "updateLocation" listener failed: $e');
  });
// This listener handles commands sent from the UI to the running service.
  service.on('startTask').listen((data) async {
    if (data == null) return;
    final String? task = data['task'];
    final bookingId = data['booking_id'];
    switch (task) {
      case 'startTrip':
        bookedDurationMinutes = data['booked_duration_minutes'] as int? ?? 0;
        tripStartTime = DateTime.parse(data['start_time']);
        pausedDuration = Duration.zero;
        pauseTime = null;
        tripTimer?.cancel();
        tripTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
          if (tripStartTime == null) return;
          final now = DateTime.now();
          final duration = now.difference(tripStartTime!) - pausedDuration;
          if (duration >= Duration(minutes: bookedDurationMinutes)) {
            try {
              await Supabase.instance.client.from('bookings').update({'status': 'completed'}).eq('id', bookingId);
              print('Background Service: Auto-completed trip $bookingId as duration exceeded.');
            } catch (e) {
              print('Background Service: Error auto-completing trip: $e');
            }
            tripTimer?.cancel();
            tripTimer = null;
            service.invoke('stop');
            if (keepAliveTimer == null || !keepAliveTimer!.isActive) {
              service.stopSelf();
            }
            return;
          }
          if (service is AndroidServiceInstance) {
            String twoDigits(int n) => n.toString().padLeft(2, '0');
            final hours = twoDigits(duration.inHours);
            final minutes = twoDigits(duration.inMinutes.remainder(60));
            final seconds = twoDigits(duration.inSeconds.remainder(60));
            final timeString = "$hours:$minutes:$seconds";
            service.setForegroundNotificationInfo(
              title: "Trip in Progress",
              content: "Duration: $timeString",
            );
          }
          service.invoke('updateTrip', {
            'duration': duration.inSeconds,
            'booking_id': bookingId,
          });
        });
        break;
      case 'pauseTrip':
        if (pauseTime == null) {
          tripTimer?.cancel();
          pauseTime = DateTime.now();
          service.invoke('tripPaused', {'booking_id': bookingId});
        }
        break;
      case 'resumeTrip':
        if (pauseTime != null) {
          pausedDuration += DateTime.now().difference(pauseTime!);
          pauseTime = null;
          tripTimer?.cancel();
          tripTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
            if (tripStartTime == null) return;
            final now = DateTime.now();
            final duration = now.difference(tripStartTime!) - pausedDuration;
            if (duration >= Duration(minutes: bookedDurationMinutes)) {
              try {
                await Supabase.instance.client.from('bookings').update({'status': 'completed'}).eq('id', bookingId);
                print('Background Service: Auto-completed trip $bookingId as duration exceeded.');
              } catch (e) {
                print('Background Service: Error auto-completing trip: $e');
              }
              tripTimer?.cancel();
              tripTimer = null;
              service.invoke('stop');
              if (keepAliveTimer == null || !keepAliveTimer!.isActive) {
                service.stopSelf();
              }
              return;
            }
            service.invoke('updateTrip', {
              'duration': duration.inSeconds,
              'booking_id': bookingId,
            });
          });
        }
        break;
      case 'startKeepAlive':
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "You are Online",
            content: "MyGoBuddy is running to maintain your status.",
          );
        }
        keepAliveTimer?.cancel();
        _pingServer();
        keepAliveTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
          _pingServer();
        });
        break;
      case 'endTrip':
        tripTimer?.cancel();
        tripTimer = null;
        if (keepAliveTimer != null && keepAliveTimer!.isActive) {
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "You are Online",
              content: "MyGoBuddy is running to maintain your status.",
            );
          }
        } else {
          service.stopSelf();
        }
        break;
      case 'startLiveLocation':
        liveLocationConversationId = data['conversation_id'] as String;
        final expiresAt = DateTime.parse(data['expires_at'] as String);
        isLiveLocationActive = true;
        locationCountdownTimer?.cancel();
        locationCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          final remaining = expiresAt.difference(DateTime.now());
          if (remaining.isNegative) {
            timer.cancel();
            service.invoke('startTask', {'task': 'stopLiveLocation', 'conversation_id': liveLocationConversationId});
            return;
          }
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Sharing Live Location",
              content: "${remaining.inMinutes} minutes remaining",
            );
          }
          service.invoke('updateLiveLocationState', {
            'conversation_id': liveLocationConversationId,
            'expires_at': expiresAt.toIso8601String(),
          });
        });
        break;
      case 'stopLiveLocation':
        locationCountdownTimer?.cancel();
        isLiveLocationActive = false;
        final conversationIdToStop = data['conversation_id'] as String;
        await Supabase.instance.client.from('conversations').update({
          'live_latitude': null,
          'live_longitude': null,
          'live_location_sender_id': null,
          'live_location_expires_at': null,
        }).eq('id', conversationIdToStop);
        if (keepAliveTimer != null && keepAliveTimer!.isActive) {
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "You are Online",
              content: "MyGoBuddy is running to maintain your status.",
            );
          }
        }
        service.invoke('updateLiveLocationState', {});
        break;
      case 'startSafetyLocationSharing':
        final expiresAt = DateTime.parse(data['expires_at'] as String);
        safetyShareToken = data['share_token'] as String?;
        isSafetyLocationActive = true;
        safetyCountdownTimer?.cancel();
        safetyCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          final remaining = expiresAt.difference(DateTime.now());
          if (remaining.isNegative) {
            timer.cancel();
            service.invoke('startTask', {'task': 'stopSafetyLocationSharing'});
            return;
          }
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Sharing Safety Location",
              content: "${remaining.inHours} hours ${remaining.inMinutes % 60} minutes remaining",
            );
          }
          service.invoke('updateSafetyLocationState', {
            'expires_at': expiresAt.toIso8601String(),
          });
        });
        break;
      case 'stopSafetyLocationSharing':
        safetyCountdownTimer?.cancel();
        isSafetyLocationActive = false;
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null) {
          await Supabase.instance.client.from('safety_shares').delete().eq('user_id', currentUserId);
          await Supabase.instance.client.from('live_locations').delete().eq('user_id', currentUserId);
        }
        if (keepAliveTimer != null && keepAliveTimer!.isActive) {
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "You are Online",
              content: "MyGoBuddy is running to maintain your status.",
            );
          }
        } else if (!isLiveLocationActive) {
          service.stopSelf();
        }
        service.invoke('updateSafetyLocationState', {});
        break;
    }
  }, onError: (e) {
    print('Background Service Error: "startTask" listener failed: $e');
  });
  service.on('stop').listen((data) {
    tripTimer?.cancel();
    keepAliveTimer?.cancel();
    locationCountdownTimer?.cancel();
    safetyCountdownTimer?.cancel();
    bookingsSubscription?.cancel();
    service.stopSelf();
  }, onError: (e) {
    print('Background Service Error: "stop" listener failed: $e');
  });
}
Future<void> _pingServer() async {
  try {
    await Supabase.instance.client.rpc('update_last_seen');
    print('Buddy Keep-Alive: Successfully pinged server.');
  } catch (e) {
    print('Buddy Keep-Alive Error: Failed to ping server. $e');
  }
}
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}
Future<void> initializeService() async {
  try {
    final service = FlutterBackgroundService();

    const channelId = 'my_gobuddy_trip_channel';

    final androidConfiguration = AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: false,
      autoStartOnBoot: false,
      notificationChannelId: channelId,
      initialNotificationTitle: 'MyGoBuddy Service',
      initialNotificationContent: 'Buddy service is running.',
      foregroundServiceNotificationId: 888,
    );

    final iosConfiguration = IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    );

    await service.configure(
      androidConfiguration: androidConfiguration,
      iosConfiguration: iosConfiguration,
    );

    print('Background service configured successfully');
  } catch (e) {
    print('Background service configuration failed: $e');
    // Don't rethrow - let the app continue without background service if needed
  }
}
void main() async {
  runZonedGuarded(() async {
    // Ensure that Flutter bindings are initialized before any async operations.
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      print('[v0] Flutter Error: ${details.exception}');
      print('[v0] Stack trace: ${details.stack}');
      // Don't crash the app, just log the error
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      print('[v0] Platform Error: $error');
      print('[v0] Stack trace: $stack');
      return true; // Handled, don't crash
    };

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 10));
      print('[v0] Firebase initialized successfully');
    } catch (e) {
      print('[v0] Firebase initialization failed: $e');
      // Continue app initialization even if Firebase fails
    }

    try {
      await NotificationService().init().timeout(const Duration(seconds: 5));
      print('[v0] NotificationService initialized successfully');
    } catch (e) {
      print('[v0] NotificationService initialization failed: $e');
      // Continue app initialization even if notifications fail
    }

    try {
      await Supabase.initialize(
        url: 'https://rbzgchesdmyychvpplgq.supabase.co',
        anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJiemdjaGVzZG15eWNodnBwbGdxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2ODMzMDAsImV4cCI6MjA2NjI1OTMwMH0.M5z7Co0If6WO4SKJRv1_8Vcxbh5p615Er_Agebso9Gk',
      ).timeout(const Duration(seconds: 10));
      print('[v0] Supabase initialized successfully');
    } catch (e) {
      print('[v0] Supabase initialization failed: $e');
      // Continue app initialization even if Supabase fails
    }

    try {
      Stripe.publishableKey =
      'pk_test_51RRevwGGyNfla3Xwqz0aCibiYJfXUi56g60oOf8MHDuuKFbaQP60VI8Hxdy17b9iOxxQp4Vb3FPTRmqw6L5jjdyp00R8sQ76ON';
      await Stripe.instance.applySettings().timeout(const Duration(seconds: 5));
      print('[v0] Stripe initialized successfully');
    } catch (e) {
      print('[v0] Stripe initialization failed: $e');
      // Continue app initialization even if Stripe fails
    }

    try {
      await initializeService();
      print('Background service initialization completed');
    } catch (e) {
      print('Background service initialization failed, continuing without it: $e');
      // Continue app initialization even if background service fails
    }

    try {
      // Now that all services are initialized, run the app.
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (context) => ProfileProvider()),
            ChangeNotifierProvider(create: (context) => TripProvider()),
            ChangeNotifierProvider(create: (context) => HomeProvider()),
            ChangeNotifierProvider(create: (context) => LocationProvider()),
            ChangeNotifierProvider(create: (context) => LanguageProvider()),
            ChangeNotifierProvider(create: (context) => DashboardProvider()),
            ChangeNotifierProvider(create: (context) => SafetyLocationProvider()),
          ],
          child: const MyApp(),
        ),
      );
    } catch (e) {
      print('[v0] Provider initialization failed: $e');
      runApp(
        MaterialApp(
          title: 'MyGoBuddy',
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Loading MyGoBuddy...'),
                  const SizedBox(height: 8),
                  Text('Initialization error: ${e.toString()}'),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }, (error, stack) {
    print('[v0] Unhandled async error: $error');
    print('[v0] Stack trace: $stack');
    // Don't crash the app
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
// Define the navigatorKey as a static variable to be accessible globally
// without needing to be initialized before the MaterialApp.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, child) {
        return MaterialApp(
          navigatorKey: MyApp.navigatorKey, // Use the static key
          title: 'MyGoBuddy',
          locale: languageProvider.appLocale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''),
            Locale('es', ''),
          ],
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFFF9FAFB),
            fontFamily: 'Poppins',
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF9FAFB),
              surfaceTintColor: Color(0xFFF9FAFB),
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Color(0xFFF9FAFB),
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
            ),
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          debugShowCheckedModeBanner: false,
          routes: {
            '/trip': (context) => const TripScreen(),
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
// Create a single, global instance of the Location plugin.
final loc.Location location = loc.Location();
class MainScreen extends StatefulWidget {
  final int initialIndex;
  const MainScreen({super.key, this.initialIndex = 0});
  @override
  State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late int _selectedIndex;
  StreamSubscription<loc.LocationData>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeUserData();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Check for updates when app comes to foreground
      _checkForUpdates();
    }
  }

  Future<void> _initializeUserData() async {
    if (!mounted) return;
    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);

    try {
      await profileProvider.fetchProfile().timeout(const Duration(seconds: 15));
      print('[v0] Profile fetched successfully');
    } catch (e) {
      print('[v0] Profile fetch failed: $e');
      // Continue with app initialization even if profile fetch fails
    }

    if (mounted) {
      _startLocationStream();

      try {
        await NotificationService().saveFCMToken().timeout(const Duration(seconds: 5));
        print('[v0] FCM token saved successfully');
      } catch (e) {
        print('[v0] FCM token save failed: $e');
        // Continue without FCM token if it fails
      }

      // Added check for updates after app initialization
      _checkForUpdates();
    }
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) return;
    try {
      await UpdateNotificationService().checkAndShowUpdateDialog(context);
    } catch (e) {
      // Silently handle update check errors to avoid disrupting user experience
      print('[v0] Update check failed: $e');
    }
  }

  void _startLocationStream() async {
    _locationSubscription?.cancel();
    try {
      location.changeSettings(
        accuracy: loc.LocationAccuracy.high,
        interval: 5000, // 5 seconds
        distanceFilter: 5, // 5 meters
      );
      final hasAlwaysPermission = await ph.Permission.locationAlways.isGranted;
      if (hasAlwaysPermission) {
        try {
          await location.enableBackgroundMode(enable: true);
          print("Background location mode enabled successfully.");
        } on PlatformException catch (e) {
          print("Could not enable background location mode: ${e.message}");
        }
      } else {
        print("Background location not enabled: 'Allow all the time' permission not granted.");
      }
      _locationSubscription = location.onLocationChanged.listen((locationData) {
        final service = FlutterBackgroundService();
        service.isRunning().then((running) {
          if (running) {
            service.invoke('updateLocation', {
              'lat': locationData.latitude,
              'lng': locationData.longitude,
            });
          }
        });
      }, onError: (e) {
        print('Location Stream Error: $e');
      });
    } catch (e) {
      print("Failed to start location stream: $e");
    }
  }
  @override
  void dispose() {
    _locationSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  Widget _buildNavItem(String iconAsset, String label, int index) {
    bool isActive = _selectedIndex == index;
    final Color activeColor = const Color(0xFF3B82F6); // A modern, vibrant blue
    final Color inactiveColor = Colors.grey.shade500;
    return Expanded(
      child: InkWell(
        onTap: () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 4,
              width: isActive ? 28 : 0,
              decoration: BoxDecoration(
                color: activeColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            SvgPicture.string(
              iconAsset,
              height: 24,
              width: 24,
              colorFilter: ColorFilter.mode(
                isActive ? activeColor : inactiveColor,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: isActive ? activeColor : inactiveColor,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildCustomBottomNav(List<Map<String, dynamic>> navItems) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              spreadRadius: 2,
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(navItems.length, (index) {
              final item = navItems[index];
              return _buildNavItem(item['icon'], item['label'], index);
            }),
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final profileProvider = Provider.of<ProfileProvider>(context);
    final localizations = AppLocalizations.of(context);
    if (profileProvider.isLoading && profileProvider.profileData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFFF15808))),
      );
    }
    final List<Widget> pages;
    final List<Map<String, dynamic>> navItems;
    if (profileProvider.isBuddy) {
      pages = [
        const BuddyHomeScreen(),
        const BuddyBookingsScreen(),
        const MessagesScreen(),
        const BuddyProfileScreen(),
      ];
      navItems = [
        {'icon': AppIcons.home, 'label': localizations.translate('nav_home', fallback: 'Home')},
        {'icon': AppIcons.bookings, 'label': localizations.translate('nav_bookings', fallback: 'Bookings')},
        {'icon': AppIcons.messages, 'label': localizations.translate('nav_messages', fallback: 'Messages')},
        {'icon': AppIcons.profile, 'label': localizations.translate('nav_profile', fallback: 'Profile')},
      ];
    } else {
      pages = [
        const HomeScreen(),
        const TripScreen(),
        const MessagesScreen(),
        const ProfileScreen(),
      ];
      navItems = [
        {'icon': AppIcons.home, 'label': localizations.translate('nav_home', fallback: 'Home')},
        {'icon': AppIcons.bookings, 'label': localizations.translate('nav_bookings', fallback: 'Bookings')},
        {'icon': AppIcons.messages, 'label': localizations.translate('nav_messages', fallback: 'Messages')},
        {'icon': AppIcons.profile, 'label': localizations.translate('nav_profile', fallback: 'Profile')},
      ];
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFF9FAFB),
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: pages.elementAt(_selectedIndex),
        bottomNavigationBar: _buildCustomBottomNav(navItems),
      ),
    );
  }
}
