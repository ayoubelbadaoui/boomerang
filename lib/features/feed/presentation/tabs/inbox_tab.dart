import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class InboxTab extends StatelessWidget {
  const InboxTab({super.key});

  static const String routeName = '/inbox_tab';

  @override
  Widget build(BuildContext context) {
    final sections = [
      _Section('Today', [
        _Item(
          avatar: 'https://i.pravatar.cc/100?img=12',
          title: 'Charolette Hanlin',
          subtitle: 'Leave a comment on your video',
          trailingThumb: 'https://picsum.photos/seed/t1/100/100',
          actionLabel: null,
        ),
        _Item(
          avatar: 'https://i.pravatar.cc/100?img=22',
          title: 'Annabel Rohan',
          subtitle: 'Started following you',
          actionLabel: 'Follow Back',
        ),
        _Item(
          avatar: 'https://i.pravatar.cc/100?img=32',
          title: 'Sanjuanita Ordonez',
          subtitle: 'Liked your video',
          trailingThumb: 'https://picsum.photos/seed/t2/100/100',
        ),
      ]),
      _Section('Yesterday', [
        _Item(
          avatar: 'https://i.pravatar.cc/100?img=45',
          title: 'Clinton Mcclure',
          subtitle: 'Started following you',
          actionLabel: 'Follow Back',
        ),
        _Item(
          avatar: 'https://i.pravatar.cc/100?img=55',
          title: 'Thad Eddings',
          subtitle: 'Leave a comment on your video',
          trailingThumb: 'https://picsum.photos/seed/t3/100/100',
        ),
      ]),
      _Section('This Week', [
        _Item(
          avatar: 'https://i.pravatar.cc/100?img=66',
          title: 'Rayford Chenail',
          subtitle: 'Started following you',
          actionLabel: 'Follow Back',
        ),
        _Item(
          avatar: 'https://i.pravatar.cc/100?img=76',
          title: 'Rochel Foose',
          subtitle: 'Liked your video',
          trailingThumb: 'https://picsum.photos/seed/t4/100/100',
        ),
      ]),
    ];

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
      body: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        itemCount: sections.length,
        itemBuilder: (context, i) {
          final s = sections[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 12.h),
              Text(
                s.label,
                style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12.h),
              ...s.items.map((e) => _ActivityTile(item: e)),
            ],
          );
        },
      ),
    );
  }
}

class _Section {
  _Section(this.label, this.items);
  final String label;
  final List<_Item> items;
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
