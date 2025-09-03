import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:just_audio/just_audio.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/live_location_viewer_screen.dart';
import 'package:mygobuddy/screens/location_picker_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:mygobuddy/providers/location_provider.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:flutter/foundation.dart' as foundation;

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  Stream<List<Map<String, dynamic>>>? _messagesStream;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String _currentUserId = supabase.auth.currentUser!.id;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _plusButtonKey = GlobalKey();

  // State for optimistic UI and smart scrolling
  final List<Map<String, dynamic>> _pendingMessages = [];
  bool _isUserAtBottom = true;
  int _lastMessageCount = 0;

  // State for audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  late AnimationController _micIconAnimationController;
  late AnimationController _slideCancelAnimationController;

  Map<String, dynamic>? _selectedMessage;
  OverlayEntry? _reactionOverlay;
  OverlayEntry? _attachmentMenuOverlay;
  final Map<String, GlobalKey> _messageKeys = {};
  bool _isTyping = false;
  bool _showEmojiPicker = false;

  // New state for the location marker image
  Uint8List? _locationMarkerImage;

  @override
  void initState() {
    super.initState();
    _initializeStream();
    _markAsRead();
    _loadLocationMarkerImage(); // Load the marker image

    _micIconAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideCancelAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _textController.addListener(() {
      if (!mounted) return;
      setState(() {
        _isTyping = _textController.text.isNotEmpty;
      });
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        if (!mounted) return;
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });

    _scrollController.addListener(_scrollListener);
  }

  // New method to load the marker asset
  Future<void> _loadLocationMarkerImage() async {
    final ByteData byteData =
    await rootBundle.load('assets/images/location_pin.png');
    if (mounted) {
      setState(() {
        _locationMarkerImage = byteData.buffer.asUint8List();
      });
    }
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels <
        100;
    if (atBottom != _isUserAtBottom) {
      if (!mounted) return;
      setState(() {
        _isUserAtBottom = atBottom;
      });
    }
  }

  void _initializeStream() {
    if (!mounted) return;
    _messagesStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: true)
        .handleError((error) {
      debugPrint('##### Chat stream error: $error');
      if (mounted) {
        debugPrint('##### Attempting to restart chat stream...');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _initializeStream();
            setState(() {});
          }
        });
      }
    });
  }

  Future<void> _markAsRead() async {
    try {
      await supabase.rpc('mark_conversation_as_read',
          params: {'p_conversation_id': widget.conversationId});
    } catch (e) {
      debugPrint('Error marking conversation as read: $e');
    }
  }

  Future<void> _uploadAndSendMessage({
    required File file,
    required String messageType,
    required String tempId,
    Map<String, dynamic> extraMetadata = const {},
  }) async {
    final localizations = AppLocalizations.of(context);
    try {
      final fileName = '${const Uuid().v4()}.${file.path.split('.').last}';
      final filePath = '$_currentUserId/$fileName';

      await supabase.storage.from('chat_attachments').upload(filePath, file);
      final publicUrl =
      supabase.storage.from('chat_attachments').getPublicUrl(filePath);

      final metadata = {
        'type': messageType,
        'url': publicUrl,
        'fileName': file.path.split('/').last,
        'size': await file.length(),
        ...extraMetadata,
      };

      // These texts are fallbacks for notifications and should remain in a default language (English).
      // The UI renders based on metadata, not these texts.
      final text = messageType == 'image'
          ? 'Sent an image'
          : messageType == 'audio'
          ? 'Sent an audio message'
          : 'Sent a file';

      await supabase.rpc('send_message_and_update_conversation', params: {
        'p_conversation_id': widget.conversationId,
        'p_receiver_id': widget.otherUserId,
        'p_text': text,
        'p_metadata': metadata,
      });
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
            localizations
                .translate('chat_error_send_file', args: {'error': e.toString()}),
            isError: true);
        setState(() {
          final index =
          _pendingMessages.indexWhere((msg) => msg['id'] == tempId);
          if (index != -1) {
            _pendingMessages[index]['is_error'] = true;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((msg) => msg['id'] == tempId);
        });
      }
    }
  }

  void _addPendingMessage(File file, String messageType,
      {Map<String, dynamic> extraMetadata = const {}}) {
    final tempId = const Uuid().v4();
    final pendingMessage = {
      'id': tempId,
      'is_pending': true,
      'sender_id': _currentUserId,
      'created_at': DateTime.now().toIso8601String(),
      'text': '',
      'metadata': {
        'type': messageType,
        'local_path': file.path,
        'fileName': file.path.split('/').last,
        ...extraMetadata,
      },
    };
    setState(() {
      _pendingMessages.add(pendingMessage);
    });
    _uploadAndSendMessage(
        file: file,
        messageType: messageType,
        tempId: tempId,
        extraMetadata: extraMetadata);
  }

  Future<void> _handleImageSelection(picker.ImageSource source) async {
    final imagePicker = picker.ImagePicker();
    final pickedFile = await imagePicker.pickImage(source: source);
    if (pickedFile != null) {
      _addPendingMessage(File(pickedFile.path), 'image');
    }
  }

  Future<void> _handleFileSelection() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      _addPendingMessage(File(result.files.single.path!), 'file');
    }
  }

  Future<void> _handleLocationSelection() async {
    _deselectMessage();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          conversationId: widget.conversationId,
          receiverId: widget.otherUserId,
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    final localizations = AppLocalizations.of(context);

    try {
      await supabase.rpc('send_message_and_update_conversation', params: {
        'p_conversation_id': widget.conversationId,
        'p_receiver_id': widget.otherUserId,
        'p_text': text,
      });
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
            localizations.translate('chat_error_send_message',
                args: {'error': e.toString()}),
            isError: true);
      }
    }
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    final localizations = AppLocalizations.of(context);
    try {
      await supabase.rpc('toggle_reaction', params: {
        'message_id_in': messageId,
        'emoji_in': emoji,
        'user_id_in': _currentUserId,
      });
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
            localizations
                .translate('chat_error_react', args: {'error': e.toString()}),
            isError: true);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _onMessageLongPress(Map<String, dynamic> message) {
    if (message['is_deleted'] == true || message['is_pending'] == true) return;
    final messageId = message['id'] as String;
    final key = _messageKeys[messageId];
    if (key == null) return;

    _deselectMessage();
    setState(() {
      _selectedMessage = message;
    });
    _showReactionOverlay(context, key);
  }

  void _deselectMessage() {
    _reactionOverlay?.remove();
    _reactionOverlay = null;
    _attachmentMenuOverlay?.remove();
    _attachmentMenuOverlay = null;
    if (_selectedMessage != null) {
      setState(() {
        _selectedMessage = null;
      });
    }
  }

  void _showReactionOverlay(BuildContext context, GlobalKey messageKey) {
    final RenderBox renderBox =
    messageKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final isMe = _selectedMessage!['sender_id'] == _currentUserId;

    _reactionOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: offset.dy - 52,
        left: isMe ? null : offset.dx,
        right: isMe
            ? MediaQuery.of(context).size.width - offset.dx - size.width
            : null,
        child: Material(
          color: Colors.transparent,
          child: _FloatingReactionToolbar(
            onEmojiSelected: (emoji) {
              _toggleReaction(_selectedMessage!['id'], emoji);
              _deselectMessage();
            },
            onAddEmoji: () {
              _deselectMessage();
              setState(() => _showEmojiPicker = true);
            },
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_reactionOverlay!);
  }

  void _showAttachmentMenu() {
    _attachmentMenuOverlay?.remove();
    final RenderBox renderBox =
    _plusButtonKey.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final localizations = AppLocalizations.of(context);

    _attachmentMenuOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _deselectMessage,
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            bottom: screenHeight - offset.dy - keyboardHeight + 10,
            left: offset.dx - 10,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AttachmentMenuItem(
                      icon: Icons.my_location,
                      text: localizations.translate('chat_attach_live_location'),
                      onTap: () {
                        _deselectMessage();
                        _handleLocationSelection();
                      },
                    ),
                    const Divider(height: 1),
                    _AttachmentMenuItem(
                      icon: Icons.attach_file,
                      text: localizations.translate('chat_attach_files'),
                      onTap: () {
                        _deselectMessage();
                        _handleFileSelection();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_attachmentMenuOverlay!);
  }

  Future<void> _startRecording() async {
    final localizations = AppLocalizations.of(context);
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      context.showSnackBar(localizations.translate('chat_error_mic_permission'),
          isError: true);
      return;
    }
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/${const Uuid().v4()}.m4a';

    await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);

    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      _micIconAnimationController.forward();
      _slideCancelAnimationController.forward();
    }

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  Future<void> _stopRecording({bool cancelled = false}) async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    final path = await _audioRecorder.stop();

    if (mounted) {
      setState(() {
        _isRecording = false;
      });
      _micIconAnimationController.reverse();
      _slideCancelAnimationController.reverse();
    }

    if (!cancelled && path != null) {
      final file = File(path);
      if (await file.exists()) {
        _addPendingMessage(file, 'audio',
            extraMetadata: {'duration': _recordingDuration.inSeconds});
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _focusNode.dispose();
    _reactionOverlay?.remove();
    _attachmentMenuOverlay?.remove();
    _audioRecorder.dispose();
    _micIconAnimationController.dispose();
    _slideCancelAnimationController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = Provider.of<LocationProvider>(context);
    final isSharingInThisChat = locationProvider.isSharingLocation &&
        locationProvider.activeConversationId == widget.conversationId;
    final localizations = AppLocalizations.of(context);

    return WillPopScope(
      onWillPop: () async {
        if (_showEmojiPicker) {
          setState(() => _showEmojiPicker = false);
          return false;
        }
        if (_selectedMessage != null || _attachmentMenuOverlay != null) {
          _deselectMessage();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildDefaultAppBar(localizations),
        body: Column(
          children: [
            if (isSharingInThisChat)
              _buildLiveLocationBanner(locationProvider, localizations),
            Expanded(
              child: GestureDetector(
                onTap: _deselectMessage,
                behavior: HitTestBehavior.translucent,
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _lastMessageCount == 0) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _buildErrorState(localizations);
                    }

                    final streamMessages = snapshot.data ?? [];
                    final allMessages = [...streamMessages, ..._pendingMessages];

                    if (allMessages.isEmpty) {
                      return _buildEmptyState(localizations);
                    }

                    final currentMessageCount = allMessages.length;
                    if (currentMessageCount > _lastMessageCount) {
                      if (_isUserAtBottom) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _scrollToBottom());
                      }
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _lastMessageCount = currentMessageCount;
                      }
                    });

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 16.0),
                      itemCount: allMessages.length,
                      itemBuilder: (context, index) {
                        final message = allMessages[index];
                        final messageId = message['id'] as String;
                        _messageKeys.putIfAbsent(messageId, () => GlobalKey());

                        return GestureDetector(
                          key: _messageKeys[messageId],
                          onLongPress: () => _onMessageLongPress(message),
                          child: _MessageBubble(
                            message: message,
                            otherUserAvatar: widget.otherUserAvatar,
                            isSelected: _selectedMessage?['id'] == messageId,
                            locationMarkerImage: _locationMarkerImage,
                            onViewLocation: () {
                              final sharingUserId =
                              message['sender_id'] as String;
                              _navigateToLiveLocation(sharingUserId, localizations);
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            _buildMessageInputField(localizations),
            if (_showEmojiPicker) _buildEmojiPicker(),
          ],
        ),
      ),
    );
  }

  void _navigateToLiveLocation(String sharingUserId, AppLocalizations localizations) {
    final profileProvider =
    Provider.of<ProfileProvider>(context, listen: false);
    final currentProfile = profileProvider.profile;
    final isMeSharing = sharingUserId == _currentUserId;

    final targetUserName = isMeSharing
        ? (currentProfile?['full_name'] ?? localizations.translate('chat_user_you'))
        : widget.otherUserName;
    final String? targetUserAvatar = isMeSharing
        ? (currentProfile?['avatar_url'] as String?)
        : widget.otherUserAvatar;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveLocationViewerScreen(
          conversationId: widget.conversationId,
          targetUserId: sharingUserId,
          targetUserName: targetUserName,
          targetUserAvatar: targetUserAvatar,
        ),
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations localizations) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(localizations.translate('chat_error_connection'),
              style: GoogleFonts.poppins(color: Colors.grey[600])),
          Text(localizations.translate('chat_reconnecting'),
              style: GoogleFonts.poppins(color: Colors.grey[600])),
          const SizedBox(height: 10),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations localizations) {
    return Center(
      child: Text(
        localizations.translate('chat_empty_state'),
        style: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
    );
  }

  AppBar _buildDefaultAppBar(AppLocalizations localizations) {
    ImageProvider avatarImage;
    if (widget.otherUserAvatar != null &&
        widget.otherUserAvatar!.startsWith('http')) {
      avatarImage = NetworkImage(widget.otherUserAvatar!);
    } else {
      avatarImage = const AssetImage('assets/images/sam_wilson.png');
    }

    return AppBar(
      toolbarHeight: 70,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new,
            color: Colors.black54, size: 22),
        onPressed: () => Navigator.of(context).pop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          CircleAvatar(radius: 20, backgroundImage: avatarImage),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.otherUserName,
                style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                localizations.translate('chat_status_online'),
                style: GoogleFonts.poppins(
                  color: Colors.green.shade600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: const [],
    );
  }

  Widget _buildMessageInputField(AppLocalizations localizations) {
    String formatDuration(Duration d) {
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return "$minutes:$seconds";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
        Border(top: BorderSide(color: Colors.grey.shade200, width: 1.0)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!_isRecording) ...[
              _InputIconButton(
                key: _plusButtonKey,
                icon: Icons.add_circle_outline,
                onTap: _showAttachmentMenu,
              ),
              _InputIconButton(
                  icon: Icons.camera_alt_outlined,
                  onTap: () => _handleImageSelection(picker.ImageSource.camera)),
              _InputIconButton(
                  icon: Icons.photo_outlined,
                  onTap: () =>
                      _handleImageSelection(picker.ImageSource.gallery)),
            ],
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _isRecording
                    ? Row(
                  children: [
                    ScaleTransition(
                      scale: _micIconAnimationController,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 12.0),
                        child: Icon(Icons.mic, color: Colors.red),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatDuration(_recordingDuration),
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600),
                    ),
                    Expanded(
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.5, 0),
                          end: Offset.zero,
                        ).animate(_slideCancelAnimationController),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.arrow_back_ios,
                                size: 14, color: Colors.grey),
                            Text(
                              localizations.translate('chat_slide_to_cancel'),
                              style: GoogleFonts.poppins(
                                  color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
                    : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        style: GoogleFonts.poppins(fontSize: 16),
                        decoration: InputDecoration(
                          hintText: localizations.translate('chat_input_hint'),
                          hintStyle: GoogleFonts.poppins(
                              color: Colors.grey.shade500),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    _InputIconButton(
                      icon: Icons.sentiment_satisfied_alt_outlined,
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _showEmojiPicker = !_showEmojiPicker;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            _isTyping
                ? _InputIconButton(icon: Icons.send, onTap: _sendMessage)
                : GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
              onLongPressCancel: () => _stopRecording(cancelled: true),
              onLongPressMoveUpdate: (details) {
                if (details.localOffsetFromOrigin.dx < -50) {
                  _stopRecording(cancelled: true);
                  HapticFeedback.mediumImpact();
                }
              },
              child: _InputIconButton(
                  icon: Icons.mic_none_outlined, onTap: () {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return EmojiPicker(
      onEmojiSelected: (category, emoji) {
        _textController.text += emoji.emoji;
      },
      textEditingController: _textController,
      config: Config(
        height: 256,
        checkPlatformCompatibility: true,
        emojiViewConfig: EmojiViewConfig(
          emojiSizeMax: 28 *
              (foundation.defaultTargetPlatform == TargetPlatform.iOS
                  ? 1.20
                  : 1.0),
          columns: 8,
          backgroundColor: const Color(0xFFF2F2F2),
        ),
        skinToneConfig: const SkinToneConfig(),
        categoryViewConfig: const CategoryViewConfig(
          backgroundColor: Color(0xFFF2F2F2),
          indicatorColor: Color(0xFF007AFF),
          iconColorSelected: Color(0xFF007AFF),
        ),
        bottomActionBarConfig: const BottomActionBarConfig(
          showBackspaceButton: true,
          showSearchViewButton: false,
        ),
        searchViewConfig: const SearchViewConfig(),
      ),
    );
  }

  Widget _buildLiveLocationBanner(LocationProvider provider, AppLocalizations localizations) {
    final remaining = provider.remainingTime;
    return Material(
      color: Colors.blue.withOpacity(0.1),
      child: InkWell(
        onTap: () {
          _navigateToLiveLocation(_currentUserId, localizations);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.blue, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.translate('chat_banner_live_location'),
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800),
                    ),
                    Text(
                      localizations.translate('chat_banner_minutes_remaining', args: {'minutes': remaining.inMinutes.toString()}),
                      style: GoogleFonts.poppins(
                          color: Colors.blue.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.blue),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _InputIconButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, color: const Color(0xFF007AFF), size: 26),
      ),
    );
  }
}

class _FloatingReactionToolbar extends StatelessWidget {
  final Function(String) onEmojiSelected;
  final VoidCallback onAddEmoji;
  const _FloatingReactionToolbar(
      {required this.onEmojiSelected, required this.onAddEmoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...['❤️', '😆', '😮', '😢', '😠', '👍'].map((emoji) => InkWell(
            onTap: () => onEmojiSelected(emoji),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          )),
          InkWell(
            onTap: onAddEmoji,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child:
              Icon(Icons.add_circle_outline, color: Colors.grey, size: 24),
            ),
          )
        ],
      ),
    );
  }
}

class _AttachmentMenuItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _AttachmentMenuItem(
      {required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF007AFF)),
            const SizedBox(width: 16),
            Text(text, style: GoogleFonts.poppins(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final String? otherUserAvatar;
  final bool isSelected;
  final VoidCallback? onViewLocation;
  final Uint8List? locationMarkerImage;

  const _MessageBubble({
    super.key,
    required this.message,
    this.otherUserAvatar,
    this.isSelected = false,
    this.onViewLocation,
    this.locationMarkerImage,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser!.id;
    final isMe = message['sender_id'] == currentUserId;

    Widget content;

    final metadata = message['metadata'] as Map<String, dynamic>? ?? {};
    final isPending = message['is_pending'] as bool? ?? false;
    final messageType = metadata['type'] ?? 'text';

    if (isPending) {
      switch (messageType) {
        case 'image':
          content = _ImageMessage(message: message);
          break;
        case 'audio':
          content = _AudioMessage(message: message, isMe: isMe);
          break;
        default:
          content = _FileMessage(message: message);
      }
    } else {
      switch (messageType) {
        case 'image':
          content = _ImageMessage(message: message);
          break;
        case 'file':
          content = _FileMessage(message: message);
          break;
        case 'audio':
          content = _AudioMessage(message: message, isMe: isMe);
          break;
        case 'location':
          content = _LocationMessage(
            metadata: metadata,
            markerImage: locationMarkerImage,
          );
          break;
        case 'live_location_started':
          content = _LiveLocationStartedMessage(
            metadata: metadata,
            isMe: isMe,
            onViewLocation: onViewLocation,
          );
          break;
        default:
          content = _TextMessage(message: message, isSelected: isSelected);
      }
    }

    ImageProvider avatarImage;
    if (!isMe &&
        otherUserAvatar != null &&
        otherUserAvatar!.startsWith('http')) {
      avatarImage = NetworkImage(otherUserAvatar!);
    } else {
      avatarImage = const AssetImage('assets/images/sam_wilson.png');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment:
        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(radius: 14, backgroundImage: avatarImage),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: content,
          ),
        ],
      ),
    );
  }
}

class _TextMessage extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isSelected;
  const _TextMessage({required this.message, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser!.id;
    final isMe = message['sender_id'] == currentUserId;
    final isDeleted = message['is_deleted'] as bool? ?? false;
    final localizations = AppLocalizations.of(context);
    final text = isDeleted
        ? localizations.translate('chat_message_deleted')
        : (message['text'] as String? ?? '');
    final reactionsData = message['reactions'];
    Map<String, List<dynamic>> reactions = {};
    if (reactionsData is Map<String, dynamic>) {
      reactions = reactionsData.map((k, v) => MapEntry(k, v as List<dynamic>));
    }
    final hasReactions = reactions.isNotEmpty;

    return Column(
      crossAxisAlignment:
      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: isSelected
                ? (isMe ? const Color(0xFF0055D4) : const Color(0xFFD0D1D5))
                : (isMe ? const Color(0xFF007AFF) : const Color(0xFFE4E6EB)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: isMe ? Colors.white : Colors.black87,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
        if (hasReactions)
          Padding(
            padding: EdgeInsets.only(
                top: 4, right: isMe ? 8 : 0, left: !isMe ? 8 : 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 3,
                        offset: const Offset(0, 1))
                  ]),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: reactions.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Text(
                      '${entry.key}${entry.value.length > 1 ? entry.value.length : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
              ),
            ),
          )
      ],
    );
  }
}

class _ImageMessage extends StatelessWidget {
  final Map<String, dynamic> message;
  const _ImageMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final metadata = message['metadata'] as Map<String, dynamic>;
    final isPending = message['is_pending'] as bool? ?? false;
    final isError = message['is_error'] as bool? ?? false;

    Widget content;
    if (isPending) {
      final localPath = metadata['local_path'] as String?;
      if (localPath == null) return const SizedBox.shrink();
      content = Stack(
        alignment: Alignment.center,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Image.file(
              File(localPath),
              fit: BoxFit.cover,
            ),
          ),
          if (isError)
            const Icon(Icons.error, color: Colors.white, size: 40)
          else
            const CircularProgressIndicator(color: Colors.white),
        ],
      );
    } else {
      final imageUrl = metadata['url'] as String?;
      if (imageUrl == null) return const SizedBox.shrink();
      content = GestureDetector(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => FullScreenImageViewer(imageUrl: imageUrl))),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220, maxHeight: 280),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            color: Colors.grey[200],
            child: content,
          ),
        ),
      ),
    );
  }
}

class _FileMessage extends StatelessWidget {
  final Map<String, dynamic> message;
  const _FileMessage({required this.message});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final metadata = message['metadata'] as Map<String, dynamic>;
    final isPending = message['is_pending'] as bool? ?? false;
    final isError = message['is_error'] as bool? ?? false;
    final localizations = AppLocalizations.of(context);

    final fileName = metadata['fileName'] as String? ?? localizations.translate('chat_file_name_default');
    final url = metadata['url'] as String?;

    Widget statusWidget;

    if (isPending) {
      statusWidget = Text(
        isError ? localizations.translate('chat_upload_failed') : localizations.translate('chat_uploading'),
        style: GoogleFonts.poppins(
            color: isError ? Colors.red : Colors.grey.shade600),
      );
    } else {
      final size = metadata['size'] as int?;
      statusWidget = Text(
        size != null ? _formatBytes(size) : '',
        style: GoogleFonts.poppins(color: Colors.grey.shade600),
      );
    }

    return ConstrainedBox(
      constraints:
      BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      child: GestureDetector(
        onTap: (isPending || url == null)
            ? null
            : () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(localizations.translate('chat_error_open_file'))));
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE4E6EB),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file,
                  color: Color(0xFF007AFF), size: 30),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, color: Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    statusWidget,
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioMessage extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  const _AudioMessage({required this.message, required this.isMe});

  @override
  State<_AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<_AudioMessage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final metadata = widget.message['metadata'] as Map<String, dynamic>;
      final isPending = widget.message['is_pending'] as bool? ?? false;
      AudioSource source;

      if (isPending) {
        final localPath = metadata['local_path'] as String?;
        if (localPath != null) {
          source = AudioSource.uri(Uri.file(localPath));
        } else {
          return;
        }
      } else {
        final url = metadata['url'] as String?;
        if (url != null) {
          source = AudioSource.uri(Uri.parse(url));
        } else {
          return;
        }
      }
      await _audioPlayer.setAudioSource(source);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Error initializing audio player: $e");
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? d) {
    if (d == null) return "00:00";
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.message['is_pending'] as bool? ?? false;
    final isError = widget.message['is_error'] as bool? ?? false;
    final fgColor = widget.isMe ? Colors.white : Colors.black87;
    final localizations = AppLocalizations.of(context);

    if (isPending) {
      return Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isMe
              ? const Color(0xFF007AFF)
              : const Color(0xFFE4E6EB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            isError
                ? Icon(Icons.error_outline, color: fgColor)
                : SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: fgColor)),
            const SizedBox(width: 12),
            Text(
              isError ? localizations.translate('chat_upload_failed') : localizations.translate('chat_uploading'),
              style: GoogleFonts.poppins(color: fgColor),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
          width: 200,
          height: 50,
          alignment: Alignment.center,
          child: const CircularProgressIndicator());
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color:
        widget.isMe ? const Color(0xFF007AFF) : const Color(0xFFE4E6EB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: _audioPlayer.playerStateStream,
            builder: (context, snapshot) {
              final playerState = snapshot.data;
              final processingState = playerState?.processingState;
              final isPlaying = playerState?.playing ?? false;

              if (processingState == ProcessingState.loading ||
                  processingState == ProcessingState.buffering) {
                return IconButton(
                  icon: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white)),
                  onPressed: null,
                );
              } else if (!isPlaying) {
                return IconButton(
                  icon: Icon(Icons.play_arrow, color: fgColor),
                  onPressed: () {
                    if (_audioPlayer.processingState ==
                        ProcessingState.completed) {
                      _audioPlayer.seek(Duration.zero);
                    }
                    _audioPlayer.play();
                  },
                );
              } else {
                return IconButton(
                  icon: Icon(Icons.pause, color: fgColor),
                  onPressed: _audioPlayer.pause,
                );
              }
            },
          ),
          Expanded(
            child: StreamBuilder<Duration?>(
              stream: _audioPlayer.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final duration = _audioPlayer.duration ?? Duration.zero;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                        trackHeight: 2,
                      ),
                      child: Slider(
                        value: position.inMilliseconds
                            .toDouble()
                            .clamp(0.0, duration.inMilliseconds.toDouble()),
                        max: duration.inMilliseconds.toDouble(),
                        onChanged: (value) {
                          _audioPlayer
                              .seek(Duration(milliseconds: value.toInt()));
                        },
                        activeColor: fgColor,
                        inactiveColor: fgColor.withOpacity(0.4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        _formatDuration(duration - position),
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: fgColor.withOpacity(0.8)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationMessage extends StatefulWidget {
  final Map<String, dynamic> metadata;
  final Uint8List? markerImage;

  const _LocationMessage({required this.metadata, this.markerImage});

  @override
  State<_LocationMessage> createState() => _LocationMessageState();
}

class _LocationMessageState extends State<_LocationMessage> {
  MapboxMap? _mapboxMap;
  bool _styleImageAdded = false;

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    // Make map non-interactive
    _mapboxMap?.gestures.updateSettings(GesturesSettings(
      rotateEnabled: false,
      scrollEnabled: false,
      pinchToZoomEnabled: false,
      pitchEnabled: false,
    ));
    _addMarkerToMap();
  }

  void _addMarkerToMap() async {
    final map = _mapboxMap;
    final markerImg = widget.markerImage;
    if (map == null || markerImg == null) return;

    final lat = widget.metadata['latitude'] as double?;
    final lon = widget.metadata['longitude'] as double?;
    if (lat == null || lon == null) return;

    final point = Point(coordinates: Position(lon, lat));

    if (!_styleImageAdded) {
      await map.style.addStyleImage(
        'location-pin-marker',
        1.0,
        MbxImage(width: 60, height: 80, data: markerImg),
        false,
        [],
        [],
        null,
      );
      _styleImageAdded = true;
    }

    final pointAnnotationManager =
    await map.annotations.createPointAnnotationManager();
    pointAnnotationManager.create(PointAnnotationOptions(
      geometry: point,
      iconImage: 'location-pin-marker',
      iconSize: 0.8,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.metadata['latitude'] as double?;
    final lon = widget.metadata['longitude'] as double?;

    if (lat == null || lon == null) return const SizedBox.shrink();

    final point = Point(coordinates: Position(lon, lat));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 150,
        width: 250,
        color: Colors.grey[300],
        child: widget.markerImage == null
            ? const Center(child: CircularProgressIndicator())
            : MapWidget(
          onMapCreated: _onMapCreated,
          cameraOptions: CameraOptions(
            center: point,
            zoom: 14.0,
          ),
          styleUri: MapboxStyles.MAPBOX_STREETS,
        ),
      ),
    );
  }
}

class _LiveLocationStartedMessage extends StatelessWidget {
  final Map<String, dynamic> metadata;
  final bool isMe;
  final VoidCallback? onViewLocation;

  const _LiveLocationStartedMessage({
    required this.metadata,
    required this.isMe,
    this.onViewLocation,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF007AFF) : const Color(0xFFE4E6EB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on,
                  color: isMe ? Colors.white : Colors.black87, size: 20),
              const SizedBox(width: 8),
              Text(
                localizations.translate('chat_live_location_started'),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            localizations.translate('chat_live_location_started', args: {'minutes': '60'}),
            style: GoogleFonts.poppins(
              color: isMe ? Colors.white70 : Colors.black54,
              fontSize: 13,
            ),
          ),
          const Divider(height: 20),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onViewLocation,
              child: Text(
                localizations.translate('chat_view_location'),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: isMe ? Colors.white : const Color(0xFF007AFF),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const FullScreenImageViewer({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(imageUrl),
        ),
      ),
    );
  }
}
