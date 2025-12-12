import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';

class InboxTab extends ConsumerWidget {
  const InboxTab({super.key});

  static const String routeName = '/inbox_tab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    final uid = me?.uid;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'All Activity',
              style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, color: Colors.black),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.send, color: Colors.black),
          ),
        ],
      ),
      body:
          uid == null
              ? const Center(child: Text('Sign in to see notifications'))
              : StreamBuilder(
                stream: ref.watch(notificationsRepoProvider).watch(uid),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(child: Text('No notifications yet'));
                  }
                  return ListView.separated(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 8.h,
                    ),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (context, i) {
                      final d = docs[i].data();
                      final type = (d['type'] ?? '') as String;
                      final title = (d['actorName'] ?? 'User') as String;
                      final avatar = d['actorAvatar'] as String?;
                      String subtitle = '';
                      String? thumb;
                      String? action;
                      if (type == 'follow') {
                        subtitle = 'Started following you';
                        action = 'Follow Back';
                      } else if (type == 'like') {
                        subtitle = 'Liked your video';
                        thumb = d['boomerangImage'] as String?;
                      } else {
                        subtitle = 'Activity';
                      }
                      final item = _Item(
                        avatar:
                            avatar ??
                            'https://picsum.photos/seed/a${i % 100}/100/100',
                        title: title,
                        subtitle: subtitle,
                        trailingThumb: thumb,
                        actionLabel: action,
                      );
                      return _ActivityTile(item: item);
                    },
                  );
                },
              ),
    );
  }
}

class _Item {
  _Item({
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.trailingThumb,
    this.actionLabel,
  });
  final String avatar;
  final String title;
  final String subtitle;
  final String? trailingThumb;
  final String? actionLabel;
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});
  final _Item item;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26.r,
            backgroundImage: NetworkImage(item.avatar),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  item.subtitle,
                  style: TextStyle(color: Colors.black54, fontSize: 14.sp),
                ),
              ],
            ),
          ),
          if (item.actionLabel != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: const Color(0xFFECECEC),
                borderRadius: BorderRadius.circular(24.r),
              ),
              child: Text(
                item.actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          else if (item.trailingThumb != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10.r),
              child: Image.network(
                item.trailingThumb!,
                width: 48.r,
                height: 48.r,
                fit: BoxFit.cover,
              ),
            ),
        ],
      ),
    );
  }
}
