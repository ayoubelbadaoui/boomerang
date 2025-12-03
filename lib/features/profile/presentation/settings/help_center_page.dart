import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});
  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          'Help Center',
          style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(44.h),
          child: TabBar(
            controller: _tab,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black38,
            indicatorColor: Colors.black,
            tabs: const [Tab(text: 'FAQ'), Tab(text: 'Contact us')],
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16.w),
            child: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [_FaqTab(search: _search), const _ContactTab()],
      ),
    );
  }
}

class _FaqTab extends StatelessWidget {
  const _FaqTab({required this.search});
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    final chips = ['General', 'Account', 'Service', 'Bmg.'];
    final faqs = [
      'What is Boomerang?',
      'How to use Boomerang?',
      'How do I delete a video?',
      'Is Boomerang free to use?',
      'How to upload video on Boomerang?',
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
      children: [
        Row(
          children:
              chips
                  .map(
                    (c) => Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: ChoiceChip(
                        selected: c == 'General',
                        onSelected: (_) {},
                        selectedColor: Colors.black,
                        labelStyle: TextStyle(
                          color: c == 'General' ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                        label: Text(c),
                        backgroundColor: Colors.transparent,
                        shape: StadiumBorder(
                          side: BorderSide(
                            color:
                                c == 'General'
                                    ? Colors.transparent
                                    : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
        SizedBox(height: 12.h),
        TextField(
          controller: search,
          decoration: InputDecoration(
            hintText: 'Search',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: const Icon(Icons.tune),
            filled: true,
            fillColor: const Color(0xFFF6F6F6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.r),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        SizedBox(height: 16.h),
        ...faqs.map(
          (q) => _FaqItem(
            title: q,
            content:
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
          ),
        ),
      ],
    );
  }
}

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.title, required this.content});
  final String title;
  final String content;
  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ExpansionTile(
        title: Text(
          widget.title,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16.sp),
        ),
        trailing: Icon(
          open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        ),
        onExpansionChanged: (v) => setState(() => open = v),
        children: [
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(16.r),
            child: Text(
              widget.content,
              style: TextStyle(color: Colors.black54, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactTab extends StatelessWidget {
  const _ContactTab();
  @override
  Widget build(BuildContext context) {
    final items = const [
      _ContactItem(Icons.headset_mic, 'Customer Service'),
      _ContactItem(Icons.chat, 'WhatsApp'),
      _ContactItem(Icons.language, 'Website'),
      _ContactItem(Icons.facebook, 'Facebook'),
      _ContactItem(Icons.alternate_email, 'Twitter'),
      _ContactItem(Icons.camera_alt, 'Instagram'),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
      children:
          items
              .map(
                (e) => Container(
                  margin: EdgeInsets.only(bottom: 12.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 20.r,
                      backgroundColor: const Color(0xFFF2F2F2),
                      child: Icon(e.icon, color: Colors.black),
                    ),
                    title: Text(e.title),
                    onTap: () {},
                  ),
                ),
              )
              .toList(),
    );
  }
}

class _ContactItem {
  final IconData icon;
  final String title;
  const _ContactItem(this.icon, this.title);
}
