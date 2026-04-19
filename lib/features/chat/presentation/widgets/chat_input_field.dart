import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import 'package:boomerang/features/chat/domain/message_entity.dart';
import 'package:boomerang/features/chat/presentation/widgets/gif_picker_sheet.dart';

class ChatInputField extends StatefulWidget {
  const ChatInputField({
    super.key,
    required this.onSendText,
    required this.onSendImage,
    required this.onSendGif,
    required this.onSendAudio,
    this.isSending = false,
    this.emojiOpen = false,
    required this.onToggleEmoji,
    this.replyingTo,
    this.replyToSenderName,
    this.onClearReply,
  });

  final ValueChanged<String> onSendText;
  final ValueChanged<String> onSendImage;
  final ValueChanged<String> onSendGif;
  final void Function(String path, int durationMs) onSendAudio;
  final bool isSending;
  final bool emojiOpen;
  final VoidCallback onToggleEmoji;
  final MessageEntity? replyingTo;
  final String? replyToSenderName;
  final VoidCallback? onClearReply;

  @override
  State<ChatInputField> createState() => ChatInputFieldState();
}

class ChatInputFieldState extends State<ChatInputField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  // Audio recording state
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  double _dragOffset = 0;
  static const _cancelThreshold = -80.0;

  TextEditingController get controller => _controller;
  FocusNode get focusNode => _focusNode;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 70);
    if (file == null) return;
    widget.onSendImage(file.path);
  }

  Future<void> _openGifPicker() async {
    final gifUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GifPickerSheet(),
    );
    if (gifUrl != null && gifUrl.isNotEmpty) {
      widget.onSendGif(gifUrl);
    }
  }

  // ── Audio recording ──────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
      _dragOffset = 0;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  Future<void> _stopRecording({bool cancelled = false}) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final path = await _recorder.stop();

    if (!cancelled && path != null && _recordingDuration.inSeconds >= 1) {
      widget.onSendAudio(path, _recordingDuration.inMilliseconds);
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
        _dragOffset = 0;
      });
    }
  }

  String _formatTimer(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyingTo != null) _buildReplyPreview(theme),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16.w,
              12.h,
              16.w,
              12.h + (bottomSafe > 0 ? bottomSafe : 8.h),
            ),
            child: _isRecording
                ? _buildRecordingRow(theme)
                : _buildInputRow(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(ThemeData theme) {
    final reply = widget.replyingTo!;
    String previewText;
    switch (reply.type) {
      case MessageType.image:
        previewText = '📷 Photo';
        break;
      case MessageType.gif:
        previewText = 'GIF';
        break;
      case MessageType.audio:
        previewText = '🎤 Voice message';
        break;
      case MessageType.sharedPost:
        previewText = '📫 Shared a post';
        break;
      case MessageType.text:
        previewText = reply.text;
        break;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 8.w, 0),
      child: Row(
        children: [
          Container(
            width: 3.w,
            height: 36.h,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${widget.replyToSenderName ?? ''}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  previewText,
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18.sp, color: Colors.grey),
            onPressed: widget.onClearReply,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(maxWidth: 32.w, maxHeight: 32.w),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingRow(ThemeData theme) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() => _dragOffset += details.delta.dx);
        if (_dragOffset < _cancelThreshold) {
          _stopRecording(cancelled: true);
        }
      },
      child: Row(
        children: [
          Container(
            width: 10.w,
            height: 10.w,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 10.w),
          Text(
            _formatTimer(_recordingDuration),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '< Slide to cancel',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _stopRecording(),
            child: Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.stop_rounded, color: Colors.white, size: 22.sp),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(24.r),
            ),
            child: Row(
              children: [
                _IconBtn(
                  icon: widget.emojiOpen
                      ? Icons.keyboard_outlined
                      : Icons.emoji_emotions_outlined,
                  onTap: widget.onToggleEmoji,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10.h),
                    ),
                    style: theme.textTheme.bodyMedium,
                    onSubmitted: (_) => _send(),
                    onTap: () {
                      if (widget.emojiOpen) widget.onToggleEmoji();
                    },
                  ),
                ),
                _IconBtn(
                  icon: Icons.gif_box_outlined,
                  onTap: _openGifPicker,
                ),
                _IconBtn(
                  icon: Icons.photo_outlined,
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                _IconBtn(
                  icon: Icons.camera_alt_outlined,
                  onTap: () => _pickImage(ImageSource.camera),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 8.w),
        GestureDetector(
          onTap: widget.isSending
              ? null
              : (_hasText ? _send : null),
          onLongPressStart: _hasText || widget.isSending
              ? null
              : (_) => _startRecording(),
          onLongPressEnd: _hasText || widget.isSending
              ? null
              : (_) {
                  if (_isRecording) _stopRecording();
                },
          child: Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: widget.isSending
                ? Padding(
                    padding: EdgeInsets.all(12.w),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.w,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _hasText ? Icons.send_rounded : Icons.mic,
                    color: Colors.white,
                    size: 22.sp,
                  ),
          ),
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(10.w),
        child: Icon(
          icon,
          size: 22.sp,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
