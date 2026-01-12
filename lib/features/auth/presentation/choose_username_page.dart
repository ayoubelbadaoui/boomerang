import 'package:boomerang/features/auth/domain/username_validation.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/core/widgets/ui.dart';
import 'package:boomerang/core/widgets/input_filled.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

class ChooseUsernamePage extends ConsumerStatefulWidget {
  const ChooseUsernamePage({super.key});
  static const routeName = '/choose-username';

  @override
  ConsumerState<ChooseUsernamePage> createState() => _ChooseUsernamePageState();
}

class _ChooseUsernamePageState extends ConsumerState<ChooseUsernamePage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final validation = validateUsername(_username.text);
    if (!validation.isValid) {
      setState(() => _error = validation.error);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final candidate = _username.text.trim().toLowerCase();
    debugPrint('username: attempt claim "$candidate"');
    try {
      await ref.read(usernameRepoProvider).claimUsername(candidate);
      // Force-refresh username gate before navigating.
      final _ = await ref.refresh(userHasUsernameProvider.future);
      if (!mounted) return;
      debugPrint('username: claimed "$candidate", navigating home');
      context.go(HomeShell.routeName);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final dup = e.code == 'already-exists';
      setState(() {
        _error = dup ? 'That username is taken' : (e.message ?? 'Failed to save username');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to save username';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose username'),
        leading: Container(), // prevent back navigation to feed without username
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 24.h),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick a unique username',
                  style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Use 3-20 lowercase letters, numbers, dot or underscore.',
                  style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                ),
                SizedBox(height: 24.h),
                InputFilled(
                  controller: _username,
                  hint: 'username',
                  icon: Icons.alternate_email,
                  keyboardType: TextInputType.text,
                  validator: (v) => validateUsername(v ?? '').error,
                ),
                SizedBox(height: 16.h),
                PrimaryButton(
                  loading: _loading,
                  onPressed: _submit,
                  child: Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
