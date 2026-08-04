import 'package:boomerang/features/profile/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PrivacyPage extends ConsumerStatefulWidget {
  const PrivacyPage({super.key});

  @override
  ConsumerState<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends ConsumerState<PrivacyPage> {
  ProviderSubscription<PrivacyUpdateState>? _privacySub;

  @override
  void initState() {
    super.initState();
    _privacySub = ref.listenManual<PrivacyUpdateState>(
      privacyUpdateStateProvider,
      (prev, next) {
        if (!mounted) return;
        if (next.status != PrivacyUpdateStatus.failure) return;
        final message = next.message ?? 'Could not update privacy right now.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
        ref.read(settingsControllerProvider.notifier).clearPrivacyUpdateState();
      },
    );
  }

  @override
  void dispose() {
    _privacySub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsControllerProvider);
    final privacyUpdate = ref.watch(privacyUpdateStateProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          'Privacy',
          style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
        ),
      ),
      body: s.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Failed to load settings')),
        data:
            (st) => ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
              children: [
                Text(
                  'Discoverability',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Private Account'),
                  value: st.privateAccount,
                  subtitle:
                      privacyUpdate.isUpdating
                          ? const Text('Updating privacy...')
                          : null,
                  onChanged:
                      privacyUpdate.isUpdating
                          ? null
                          : (v) => ref
                              .read(settingsControllerProvider.notifier)
                              .setPrivateAccount(v),
                ),
              ],
            ),
      ),
    );
  }
}
