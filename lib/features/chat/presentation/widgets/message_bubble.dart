import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:boomerang/features/chat/domain/message_entity.dart';
import 'package:boomerang/features/chat/presentation/widgets/audio_message_player.dart';
import 'package:boomerang/features/chat/presentation/widgets/fullscreen_image_viewer.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onLongPress,
    this.onReplyTap,
    this.replyToSenderName,
    this.onSharedPostTap,
    this.highlighted = false,
  });

  final MessageEntity message;
  final bool isMine;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;
  final String? replyToSenderName;
  final VoidCallback? onSharedPostTap;

  /// Briefly tinted when the user has just navigated to this message
  /// (mention/reply tap, deep link). Controlled by the parent page.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeText = DateFormat.Hm().format(message.createdAt);

    final Widget child;
    if (message.isUnsent) {
      child = _UnsentBubble(isMine: isMine, theme: theme);
    } else {
      child = Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 280.w),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  margin: EdgeInsets.only(
                    left: isMine ? 60.w : 16.w,
                    right: isMine ? 16.w : 60.w,
                    bottom: 8.h,
                  ),
                  padding: _isMediaType
                      ? EdgeInsets.all(4.w)
                      : EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 10.h,
                        ),
                  decoration: BoxDecoration(
                    color: isMine
                        ? theme.colorScheme.primary
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16.r),
                      topRight: Radius.circular(16.r),
                      bottomLeft: Radius.circular(isMine ? 16.r : 4.r),
                      bottomRight: Radius.circular(isMine ? 4.r : 16.r),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.hasReply) _buildReplyPreview(theme),
                      _buildContent(theme, timeText),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      color: highlighted
          ? theme.colorScheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      child: child,
    );
  }

  bool get _isMediaType =>
      message.isImage || message.isGif || message.isSharedPost;

  Widget _buildReplyPreview(ThemeData theme) {
    final replyBg = isMine
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.grey.withValues(alpha: 0.15);
    final replyTextColor = isMine ? Colors.white70 : Colors.black54;
    final senderColor = isMine ? Colors.white : Colors.black87;

    String previewText;
    switch (message.replyToType) {
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
      default:
        previewText = message.replyToText ?? '';
    }

    return GestureDetector(
      onTap: onReplyTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 6.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: replyBg,
          borderRadius: BorderRadius.circular(8.r),
          border: Border(
            left: BorderSide(
              color: isMine ? Colors.white70 : theme.colorScheme.primary,
              width: 3.w,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              replyToSenderName ?? '',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: senderColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 2.h),
            Text(
              previewText,
              style: TextStyle(fontSize: 11.sp, color: replyTextColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, String timeText) {
    switch (message.type) {
      case MessageType.image:
        return _ImageContent(
          url: message.text,
          time: timeText,
          isMine: isMine,
          theme: theme,
        );
      case MessageType.gif:
        return _GifContent(
          url: message.text,
          time: timeText,
          isMine: isMine,
          theme: theme,
        );
      case MessageType.audio:
        return _AudioContent(
          message: message,
          time: timeText,
          isMine: isMine,
          theme: theme,
        );
      case MessageType.sharedPost:
        return _SharedPostContent(
          message: message,
          time: timeText,
          isMine: isMine,
          theme: theme,
          onTap: onSharedPostTap,
        );
      case MessageType.text:
        return _TextContent(
          text: message.text,
          time: timeText,
          isMine: isMine,
          theme: theme,
        );
    }
  }
}

// ── Unsent placeholder ─────────────────────────────────────────────────

class _UnsentBubble extends StatelessWidget {
  const _UnsentBubble({required this.isMine, required this.theme});

  final bool isMine;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMine ? 60.w : 16.w,
          right: isMine ? 16.w : 60.w,
          bottom: 8.h,
        ),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14.sp, color: Colors.grey),
            SizedBox(width: 6.w),
            Text(
              isMine
                  ? 'You unsent a message'
                  : 'This message was unsent',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Text content ───────────────────────────────────────────────────────

class _TextContent extends StatelessWidget {
  const _TextContent({
    required this.text,
    required this.time,
    required this.isMine,
    required this.theme,
  });

  final String text;
  final String time;
  final bool isMine;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final textColor = isMine ? Colors.white : theme.colorScheme.onSurface;
    final timeColor = isMine
        ? Colors.white.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
        ),
        SizedBox(height: 4.h),
        Align(
          alignment: Alignment.bottomRight,
          child: Text(
            time,
            style: theme.textTheme.labelSmall?.copyWith(
              color: timeColor,
              fontSize: 10.sp,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Image content ──────────────────────────────────────────────────────

class _ImageContent extends StatelessWidget {
  const _ImageContent({
    required this.url,
    required this.time,
    required this.isMine,
    required this.theme,
  });

  final String url;
  final String time;
  final bool isMine;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final heroTag = 'chat_image_$url';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => FullscreenImageViewer.open(
            context,
            imageUrl: url,
            heroTag: heroTag,
          ),
          child: Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: Image.network(
                url,
                width: 200.w,
                height: 200.w,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return SizedBox(
                    width: 200.w,
                    height: 200.w,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (_, __, ___) => SizedBox(
                  width: 200.w,
                  height: 200.w,
                  child:
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          time,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isMine
                ? Colors.white.withValues(alpha: 0.7)
                : theme.colorScheme.onSurfaceVariant,
            fontSize: 10.sp,
          ),
        ),
      ],
    );
  }
}

// ── GIF content ────────────────────────────────────────────────────────

class _GifContent extends StatelessWidget {
  const _GifContent({
    required this.url,
    required this.time,
    required this.isMine,
    required this.theme,
  });

  final String url;
  final String time;
  final bool isMine;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final heroTag = 'chat_gif_$url';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => FullscreenImageViewer.open(
            context,
            imageUrl: url,
            heroTag: heroTag,
          ),
          child: Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: Image.network(
                url,
                width: 200.w,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return SizedBox(
                    width: 200.w,
                    height: 120.w,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (_, __, ___) => SizedBox(
                  width: 200.w,
                  height: 120.w,
                  child:
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4.h),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GIF',
              style: TextStyle(
                fontSize: 9.sp,
                fontWeight: FontWeight.w700,
                color: isMine
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.grey,
              ),
            ),
            SizedBox(width: 6.w),
            Text(
              time,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.7)
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 10.sp,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Shared post content ────────────────────────────────────────────────

class _SharedPostContent extends StatelessWidget {
  const _SharedPostContent({
    required this.message,
    required this.time,
    required this.isMine,
    required this.theme,
    this.onTap,
  });

  final MessageEntity message;
  final String time;
  final bool isMine;
  final ThemeData theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = message.sharedPostImageUrl;
    final userName = message.sharedPostUserName ?? '';
    final caption = message.sharedPostCaption ?? '';
    final timeColor = isMine
        ? Colors.white.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 220.w,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10.r),
                child: Image.network(
                  imageUrl,
                  width: 220.w,
                  height: 180.w,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return SizedBox(
                      width: 220.w,
                      height: 180.w,
                      child:
                          const Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (_, __, ___) => SizedBox(
                    width: 220.w,
                    height: 180.w,
                    child: const Center(
                        child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_outline_rounded,
                    size: 16.sp,
                    color: isMine ? Colors.white70 : Colors.black54,
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      userName,
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                        color: isMine ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (caption.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 0, 8.w, 4.h),
                child: Text(
                  caption,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: isMine ? Colors.white70 : Colors.black54,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 2.h, 8.w, 6.h),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  time,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: timeColor,
                    fontSize: 10.sp,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Audio content ──────────────────────────────────────────────────────

class _AudioContent extends StatelessWidget {
  const _AudioContent({
    required this.message,
    required this.time,
    required this.isMine,
    required this.theme,
  });

  final MessageEntity message;
  final String time;
  final bool isMine;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final timeColor = isMine
        ? Colors.white.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      width: 200.w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          AudioMessagePlayer(
            key: ValueKey('audio-${message.id}'),
            url: message.text,
            durationMs: message.audioDurationMs ?? 0,
            isMine: isMine,
            messageId: message.id,
          ),
          SizedBox(height: 4.h),
          Text(
            time,
            style: theme.textTheme.labelSmall?.copyWith(
              color: timeColor,
              fontSize: 10.sp,
            ),
          ),
        ],
      ),
    );
  }
}
