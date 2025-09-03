import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/screens/chat_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:intl/intl.dart';
import 'package:mygobuddy/utils/localizations.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late Future<List<dynamic>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _fetchConversations();
  }

  Future<List<dynamic>> _fetchConversations() async {
    try {
      final data = await supabase.rpc('get_user_conversations');
      return data as List<dynamic>;
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        final errorMessage = localizations?.translate('messages_fetch_error') ?? 'Failed to load messages';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage)));
        debugPrint('Failed to load messages: ${e.toString()}');
      }
      throw Exception('Failed to load conversations: $e');
    }
  }

  Future<void> _refreshConversations() async {
    setState(() {
      _conversationsFuture = _fetchConversations();
    });
  }

  String _formatTimestamp(String? isoString, AppLocalizations localizations) {
    if (isoString == null) return '';
    final dateTime = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final date = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (date == today) {
      return DateFormat.jm().format(dateTime); // e.g., 5:08 PM
    } else if (date == yesterday) {
      return localizations.translate('messages_timestamp_yesterday');
    } else {
      return DateFormat('dd/MM/yyyy').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    final localizations = AppLocalizations.of(context)!;

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
          automaticallyImplyLeading: false, // Removes back button
          title: Text(
            localizations.translate('messages_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildSearchBar(localizations),
              const SizedBox(height: 24),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshConversations,
                  child: FutureBuilder<List<dynamic>>(
                    future: _conversationsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              localizations.translate('messages_load_error'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(color: Colors.grey.shade600),
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Text(
                            localizations.translate('messages_empty'),
                            style: GoogleFonts.poppins(color: Colors.grey.shade600),
                          ),
                        );
                      }
                      final conversations = snapshot.data!;
                      return ListView.separated(
                        itemCount: conversations.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 24),
                        itemBuilder: (context, index) {
                          final convo = conversations[index];
                          return _buildMessageItem(
                            context: context,
                            name: convo['other_participant_name'] ?? localizations.translate('messages_unknown_user'),
                            message: convo['last_message_content'] ?? '',
                            time: _formatTimestamp(convo['last_message_at'], localizations),
                            unreadCount: convo['unread_count'] ?? 0,
                            image: convo['other_participant_avatar'],
                            conversationId: convo['conversation_id'],
                            otherParticipantId: convo['other_participant_id'],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(AppLocalizations localizations) {
    return TextField(
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: localizations.translate('messages_search_hint'),
        hintStyle: GoogleFonts.poppins(color: Colors.grey.shade500),
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildMessageItem({
    required BuildContext context,
    required String name,
    required String message,
    required String time,
    required int unreadCount,
    required String? image,
    required String conversationId,
    required String otherParticipantId,
  }) {
    ImageProvider avatarImage;
    if (image != null && image.isNotEmpty && image.startsWith('http')) {
      avatarImage = NetworkImage(image);
    } else {
      avatarImage = const AssetImage('assets/images/sam_wilson.png');
    }
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherUserName: name,
              otherUserAvatar: image,
              otherUserId: otherParticipantId,
            ),
          ),
        ).then((_) => _refreshConversations());
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: avatarImage,
            backgroundColor: Colors.grey.shade200,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                time,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 8),
              if (unreadCount > 0)
                CircleAvatar(
                  radius: 10,
                  backgroundColor: const Color(0xFF19638D),
                  child: Text(
                    unreadCount.toString(),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
