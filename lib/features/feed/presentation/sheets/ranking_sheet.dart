import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class RankingSheet extends StatefulWidget {
  const RankingSheet({super.key});
  @override
  State<RankingSheet> createState() => _RankingSheetState();
}

class _RankingSheetState extends State<RankingSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weekly = List.generate(
      5,
      (i) => _Rank(
        i + 1,
        'User ${i + 1}',
        '${(90 - i).toStringAsFixed(2)}M',
        'https://i.pravatar.cc/100?img=${i + 20}',
      ),
    );
    final rising = List.generate(
      5,
      (i) => _Rank(
        i + 1,
        'Rising ${i + 1}',
        '${(20 + i * 3).toStringAsFixed(2)}M',
        'https://i.pravatar.cc/100?img=${i + 30}',
      ),
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            SizedBox(height: 12.h),
            TabBar(
              controller: _tab,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.black38,
              indicatorColor: Colors.black,
              tabs: const [
                Tab(text: 'Weekly Ranking'),
                Tab(text: 'Rising Stars'),
              ],
            ),
            SizedBox(height: 12.h),
            SizedBox(
              height: 380.h,
              child: TabBarView(
                controller: _tab,
                children: [_RankList(items: weekly), _RankList(items: rising)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rank {
  final int index;
  final String name;
  final String metric;
  final String avatar;
  _Rank(this.index, this.name, this.metric, this.avatar);
}

class _RankList extends StatelessWidget {
  const _RankList({required this.items});
  final List<_Rank> items;
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => SizedBox(height: 6.h),
      itemBuilder: (context, i) {
        final r = items[i];
        return Row(
          children: [
            SizedBox(width: 12.w),
            Text(
              '${r.index}',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 16.w),
            CircleAvatar(radius: 24.r, backgroundImage: NetworkImage(r.avatar)),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(r.metric, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              child: const Text('Follow'),
            ),
          ],
        );
      },
    );
  }
}
