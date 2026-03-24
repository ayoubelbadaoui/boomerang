import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:boomerang/features/chat/domain/message_entity.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final MessageEntity message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeText = DateFormat.Hm().format(message.createdAt);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 280.w),
        child: Container(
          margin: EdgeInsets.only(
            left: isMine ? 60.w : 16.w,
            right: isMine ? 16.w : 60.w,
            bottom: 8.h,
          ),
          padding: message.isImage
              ? EdgeInsets.all(4.w)
              : EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
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
          child: message.isImage
              ? _ImageContent(
                  url: message.text,
                  time: timeText,
                  isMine: isMine,
                  theme: theme,
                )
              : _TextContent(
                  text: message.text,
                  time: timeText,
                  isMine: isMine,
                  theme: theme,
                ),
        ),
      ),
    );
  }
}

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
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
              child: const Center(child: Icon(Icons.broken_image_outlined)),
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
