import 'package:boomerang/features/profile/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class LanguagePage extends ConsumerWidget {
  const LanguagePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          'Language',
          style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
        ),
      ),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Failed to load settings')),
        data: (s) {
          final value = s.languageCode;
          return ListView(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
            children: [
              Text(
                'Suggested',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18.sp),
              ),
              _LangTile(
                title: 'English (US)',
                value: 'en_US',
                group: value,
                onChanged: (v) {
                  ref.read(settingsControllerProvider.notifier).setLanguage(v!);
                },
              ),
              _LangTile(
                title: 'English (UK)',
                value: 'en_GB',
                group: value,
                onChanged: (v) {
                  ref.read(settingsControllerProvider.notifier).setLanguage(v!);
                },
              ),
              const Divider(),
              Text(
                'Language',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18.sp),
              ),
              ..._others.map(
                (e) => _LangTile(
                  title: e,
                  value: e,
                  group: value,
                  onChanged: (v) {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setLanguage(v!);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  const _LangTile({
    required this.title,
    required this.value,
    required this.group,
    required this.onChanged,
  });
  final String title;
  final String value;
  final String group;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      groupValue: group,
      onChanged: onChanged,
      activeColor: Colors.black,
    );
  }
}

const _others = <String>[
  'Mandarin',
  'Hindi',
  'Spanish',
  'French',
  'Arabic',
  'Bengali',
  'Russian',
  'Indonesia',
];








