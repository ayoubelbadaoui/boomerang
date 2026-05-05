import 'package:boomerang/core/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/chat/domain/conversation_entity.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';

class ConversationTile extends ConsumerWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.otherUser,
    required this.currentUserId,
    required this.onTap,
    this.isPinned = false,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  final ConversationEntity conversation;
  final UserProfile? otherUser;
  final String currentUserId;
  final VoidCallback onTap;
  final bool isPinned;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  String get _formattedTime {
    final now = DateTime.now();
    final date = conversation.lastMessageAt;
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(messageDay).inDays;

    if (diff == 0) return DateFormat.Hm().format(date);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.E().format(date);
    return DateFormat('MMM d, y').format(date);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pendingSeen = ref.watch(pendingSeenConversationIdsProvider);
    final rawUnread = conversation.unreadCountFor(currentUserId);
    final unread = pendingSeen.contains(conversation.id) ? 0 : rawUnread;
    final hasUnread = unread > 0;
    final otherId = otherUser?.uid ?? '';

    final iFollow = otherId.isNotEmpty
        ? (ref.watch(isFollowingStreamProvider(otherId)).value ?? false)
        : false;
    final theyFollowMe = otherId.isNotEmpty
        ? (ref.watch(isFollowedByProvider(otherId)).value ?? false)
        : false;
    final hasPendingOutgoing = otherId.isNotEmpty
        ? (ref.watch(outgoingFollowRequestProvider(otherId)).value?.isPending ??
            false)
        : false;
    // Pick the most accurate badge for the current relationship:
    //   - I sent a request → "Pending" (highest priority so the user knows
    //     their tap was registered, even if they also follow me).
    //   - They follow me, I don't follow back → "Follow back".
    //   - Otherwise → no badge.
    final String? relationshipBadge;
    if (iFollow) {
      relationshipBadge = null;
    } else if (hasPendingOutgoing) {
      relationshipBadge = 'Pending';
    } else if (theyFollowMe) {
      relationshipBadge = 'Follow back';
    } else {
      relationshipBadge = null;
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : null,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Row(
          children: [
            if (isSelectionMode) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24.w,
                height: 24.w,
                margin: EdgeInsets.only(right: 12.w),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 14.sp, color: Colors.white)
                    : null,
              ),
            ],
            AppAvatar(url: otherUser?.avatarUrl, size: 56.r),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          otherUser?.fullName ??
                              otherUser?.nickname ??
                              'Unknown',
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (relationshipBadge != null) ...[
                        SizedBox(width: 6.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            relationshipBadge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.sp,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    conversation.lastMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasUnread
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          hasUnread ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPinned)
                      Padding(
                        padding: EdgeInsets.only(right: 4.w),
                        child: Icon(
                          Icons.push_pin,
                          size: 12.sp,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      _formattedTime,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (hasUnread) ...[
                  SizedBox(height: 6.h),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 7.w,
                      vertical: 2.h,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
