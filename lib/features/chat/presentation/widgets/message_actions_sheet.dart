import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:boomerang/features/chat/domain/message_entity.dart';

class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    required this.message,
    required this.isMine,
    required this.onReply,
    required this.onUnsend,
  });

  final MessageEntity message;
  final bool isMine;
  final VoidCallback onReply;
  final VoidCallback onUnsend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canUnsend = isMine &&
        !message.isUnsent &&
        DateTime.now().difference(message.createdAt).inHours < 1;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              margin: EdgeInsets.only(bottom: 16.h),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            _ActionTile(
              icon: Icons.reply_rounded,
              label: 'Reply',
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),
            if (message.type == MessageType.text && !message.isUnsent)
              _ActionTile(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            if (canUnsend)
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Unsend',
                color: theme.colorScheme.error,
                onTap: () {
                  Navigator.pop(context);
                  showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Unsend message?'),
                      content: const Text(
                        'This will remove the message for everyone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx, true);
                            onUnsend();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          child: const Text('Unsend'),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tileColor = color ?? theme.colorScheme.onSurface;

    return ListTile(
      leading: Icon(icon, color: tileColor, size: 22.sp),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(color: tileColor),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
      dense: true,
    );
  }
}
