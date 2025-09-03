import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/screens/notification_details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> notifications = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _autoDeleteOldNotifications();
  }

  Future<void> _autoDeleteOldNotifications() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      await supabase
          .from('notifications')
          .delete()
          .lt('created_at', thirtyDaysAgo.toIso8601String());
    } catch (e) {
      // Silently handle auto-delete errors
      print('Auto-delete error: $e');
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await supabase
          .from('notifications')
          .delete()
          .eq('id', notificationId);

      setState(() {
        notifications.removeWhere((n) => n['id'].toString() == notificationId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification deleted'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting notification: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _clearAllNotifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CustomDeleteDialog(
        title: 'Clear All Notifications',
        message: 'Are you sure you want to delete all notifications? This action cannot be undone.',
        confirmText: 'Clear All',
        isDestructive: true,
      ),
    );

    if (confirmed == true) {
      try {
        final currentUserId = supabase.auth.currentUser?.id;
        if (currentUserId == null) return;

        final userProfile = await supabase
            .from('profiles')
            .select('role')
            .eq('id', currentUserId)
            .single();

        final userRole = userProfile['role'] as String?;

        // Build audience filter for deletion
        String audienceFilter = 'audience.eq.all_users,audience.eq.specific_user:$currentUserId';

        if (userRole == 'buddy') {
          audienceFilter += ',audience.eq.all_buddies';
        }

        if (userRole == 'client') {
          audienceFilter += ',audience.eq.all_clients';
        }

        if (userRole == 'superadmin') {
          audienceFilter += ',audience.eq.all_clients,audience.eq.all_buddies,audience.eq.client_$currentUserId,audience.eq.buddy_$currentUserId';
        }

        await supabase
            .from('notifications')
            .delete()
            .or(audienceFilter);

        setState(() {
          notifications.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications cleared'),
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing notifications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchNotifications() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      print('[v0] Current user ID: $currentUserId');

      final userProfile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', currentUserId)
          .single();

      final userRole = userProfile['role'] as String?;

      print('[v0] User role: $userRole');

      String audienceFilter = 'audience.eq.all_users,audience.eq.specific_user:$currentUserId';

      // Add buddy-specific notifications if user is a buddy
      if (userRole == 'buddy') {
        audienceFilter += ',audience.eq.all_buddies,audience.eq.buddy_$currentUserId';
      }

      // Add client-specific notifications if user is a client
      if (userRole == 'client') {
        audienceFilter += ',audience.eq.all_clients,audience.eq.client_$currentUserId';
      }

      if (userRole == 'superadmin') {
        audienceFilter += ',audience.eq.all_clients,audience.eq.all_buddies,audience.eq.client_$currentUserId,audience.eq.buddy_$currentUserId';
      }

      print('[v0] Audience filter: $audienceFilter');

      final response = await supabase
          .from('notifications')
          .select('*')
          .or(audienceFilter)
          .order('created_at', ascending: false);

      print('[v0] Fetched ${response.length} notifications');
      for (var notification in response) {
        print('[v0] Notification: ${notification['title']} | Type: ${notification['type']} | Audience: ${notification['audience']}');
      }

      setState(() {
        notifications = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      print('[v0] Error fetching notifications: $e');
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _refreshNotifications() async {
    await _fetchNotifications();
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          surfaceTintColor: backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Notifications',
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: notifications.isNotEmpty ? [
            IconButton(
              icon: const Icon(Icons.clear_all, color: primaryTextColor),
              onPressed: _clearAllNotifications,
              tooltip: 'Clear all notifications',
            ),
          ] : null,
        ),
        body: RefreshIndicator(
          onRefresh: _refreshNotifications,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF19638D)),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading notifications',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _refreshNotifications,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF19638D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.notifications_none_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'No notifications yet',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ll see your notifications here when you receive them.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20.0),
      itemCount: notifications.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final notification = notifications[index];
        return _NotificationCard(
          notification: notification,
          onDelete: () => _deleteNotification(notification['id'].toString()),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onDelete;

  const _NotificationCard({
    required this.notification,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final String title = notification['title'] ?? 'Notification';
    final String message = notification['message'] ?? '';
    final String type = notification['type'] ?? 'general';
    final DateTime createdAt = DateTime.parse(notification['created_at']);
    final String timeAgo = _getTimeAgo(createdAt);

    IconData icon;
    Color iconColor;
    Color backgroundColor;

    switch (type) {
      case 'promotion':
        icon = Icons.local_offer_outlined;
        iconColor = Colors.orange.shade600;
        backgroundColor = Colors.orange.shade50;
        break;
      case 'booking':
      case 'booking_expired': // Added support for booking_expired type
        icon = Icons.calendar_today_outlined;
        iconColor = Colors.blue.shade600;
        backgroundColor = Colors.blue.shade50;
        break;
      case 'announcement':
        icon = Icons.campaign_outlined;
        iconColor = Colors.purple.shade600;
        backgroundColor = Colors.purple.shade50;
        break;
      case 'new_service':
        icon = Icons.add_business_outlined;
        iconColor = Colors.green.shade600;
        backgroundColor = Colors.green.shade50;
        break;
      default:
        icon = Icons.notifications_outlined;
        iconColor = Colors.grey.shade600;
        backgroundColor = Colors.grey.shade50;
    }

    return Dismissible(
      key: Key(notification['id'].toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: 28,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _CustomDeleteDialog(
            title: 'Delete Notification',
            message: 'Are you sure you want to delete this notification?',
            confirmText: 'Delete',
            isDestructive: true,
          ),
        );
      },
      onDismissed: (direction) => onDelete(),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => NotificationDetailsScreen(
                notification: notification,
              ),
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
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        Text(
                          timeAgo,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return '1 day ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return DateFormat('MMM dd').format(dateTime);
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class _CustomDeleteDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final bool isDestructive;

  const _CustomDeleteDialog({
    required this.title,
    required this.message,
    required this.confirmText,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              spreadRadius: 0,
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isDestructive ? Colors.red.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                isDestructive ? Icons.delete_outline : Icons.help_outline,
                size: 32,
                color: isDestructive ? Colors.red.shade600 : Colors.blue.shade600,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Message
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDestructive ? Colors.red.shade600 : const Color(0xFF19638D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      confirmText,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
