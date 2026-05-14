import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/features/auth/domain/username_validation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:boomerang/core/utils/avatar_crop.dart';
import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

enum _NicknameAvailability { idle, checking, available, taken, invalid, error }

class SetupFlowPage extends StatefulWidget {
  const SetupFlowPage({super.key});
  static const String routeName = '/setup/flow';

  @override
  State<SetupFlowPage> createState() => _SetupFlowPageState();
}

class _SetupFlowPageState extends State<SetupFlowPage> {
  final PageController _controller = PageController();
  final _profileFormKey = GlobalKey<FormState>();
  int _index = 0;
  String _gender = 'male';
  /// Firestore `isPrivate`: default public; only explicit `true` in the doc means private.
  bool _isPrivate = false;
  DateTime _birthday = DateTime(1995, 12, 27);
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _nickname = TextEditingController();
  final TextEditingController _email = TextEditingController();

  bool _saving = false;
  bool _lockNickname = false;
  File? _avatarFile;
  _NicknameAvailability _nicknameAvailability = _NicknameAvailability.idle;
  String? _nicknameHint;
  Timer? _nicknameDebounce;
  int _nicknameCheckVersion = 0;

  @override
  void initState() {
    super.initState();
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(firebaseAuthProvider);
    final prefill = auth.currentUser?.email ?? '';
    _email.text = prefill;
    _nickname.addListener(_onNicknameChanged);
    _hydrateFromUserDoc();
  }

  @override
  void dispose() {
    _nicknameDebounce?.cancel();
    _controller.dispose();
    _fullName.dispose();
    _nickname.dispose();
    _email.dispose();
    super.dispose();
  }

  void _onNicknameChanged() {
    if (_lockNickname) return;
    _nicknameDebounce?.cancel();
    final raw = _nickname.text.trim().toLowerCase();
    final validation = validateUsername(raw);
    if (!validation.isValid) {
      setState(() {
        _nicknameAvailability = _NicknameAvailability.invalid;
        _nicknameHint = validation.error;
      });
      return;
    }
    setState(() {
      _nicknameAvailability = _NicknameAvailability.checking;
      _nicknameHint = 'Checking availability...';
    });

    final version = ++_nicknameCheckVersion;
    _nicknameDebounce = Timer(const Duration(milliseconds: 450), () {
      _checkNicknameAvailability(raw, version);
    });
  }

  Future<void> _checkNicknameAvailability(String nickname, int version) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final uid = container.read(firebaseAuthProvider).currentUser?.uid ?? '';
    try {
      final doc = await container
          .read(firestoreProvider)
          .collection('login_usernames')
          .doc(nickname)
          .get();
      if (!mounted || version != _nicknameCheckVersion) return;
      final owner = doc.data()?['uid']?.toString().trim() ?? '';
      final taken = doc.exists && owner.isNotEmpty && owner != uid;
      setState(() {
        _nicknameAvailability =
            taken
                ? _NicknameAvailability.taken
                : _NicknameAvailability.available;
        _nicknameHint =
            taken ? 'Username is already taken.' : 'Username is available.';
      });
    } catch (_) {
      if (!mounted || version != _nicknameCheckVersion) return;
      setState(() {
        _nicknameAvailability = _NicknameAvailability.error;
        _nicknameHint = 'Could not verify username right now.';
      });
    }
  }

  String? _nicknameValidator(String? value) {
    if (_lockNickname) return null;
    final validation = validateUsername((value ?? '').trim().toLowerCase());
    if (!validation.isValid) return validation.error;
    if (_nicknameAvailability == _NicknameAvailability.taken) {
      return 'Username is already taken.';
    }
    if (_nicknameAvailability == _NicknameAvailability.error) {
      return 'Could not verify username. Please try again.';
    }
    if (_nicknameAvailability == _NicknameAvailability.checking) {
      return 'Checking username availability...';
    }
    if (_nicknameAvailability != _NicknameAvailability.available) {
      return 'Choose an available username.';
    }
    return null;
  }

  bool get _canContinueFromProfileStep {
    if (_saving) return false;
    if (_lockNickname) return true;
    final validation = validateUsername(_nickname.text.trim().toLowerCase());
    if (!validation.isValid) return false;
    return _nicknameAvailability == _NicknameAvailability.available;
  }

  Future<void> _hydrateFromUserDoc() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(firebaseAuthProvider);
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    final fs = container.read(firestoreProvider);
    try {
      final snap = await fs.collection('users').doc(uid).get();
      final data = snap.data();
      if (data == null) return;
      final nick = (data['nickname'] ?? data['username'] ?? '') as String;
      final full = (data['fullName'] ?? '') as String;
      if (!mounted) return;
      setState(() {
        _isPrivate = data['isPrivate'] == true;
        if (nick.trim().isNotEmpty) {
          _nickname.text = nick;
          _lockNickname = true;
          _nicknameAvailability = _NicknameAvailability.available;
          _nicknameHint = 'Current username';
        }
        if (full.trim().isNotEmpty) {
          _fullName.text = full;
        }
      });
    } catch (e, stackTrace) {
      developer.log(
        'SetupFlow: could not hydrate from user doc',
        name: 'SetupFlow',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  int _ageFromBirthday(DateTime birthday) {
    final now = DateTime.now();
    int age = now.year - birthday.year;
    if (now.month < birthday.month ||
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    return age;
  }

  void _showAgeRestrictionDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Age Requirement'),
            content: const Text(
              'You must be at least 13 years old to use Boomerang. '
              'This is required by the Children\'s Online Privacy '
              'Protection Act (COPPA).\n\n'
              'If you believe this is an error, please update your '
              'date of birth.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  void _next() {
    if (_saving) return;

    if (_index == 1) {
      final age = _ageFromBirthday(_birthday);
      if (age < 13) {
        _showAgeRestrictionDialog();
        return;
      }
    }

    if (_index == 2) {
      if (!_canContinueFromProfileStep) return;
      if (!_profileFormKey.currentState!.validate()) return;
      // Animate to the congratulations step and save in parallel so the
      // user doesn't stare at a spinner on the profile page.
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      _saveProfile();
      return;
    }

    if (_index < 3) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    if (!mounted) return;
    setState(() => _saving = true);

    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(userProfileRepoProvider);

    try {
      String? avatarUrl;
      if (_avatarFile != null) {
        developer.log('Setup: uploading avatar', name: 'SetupFlow');
        avatarUrl = await repo.uploadAvatar(_avatarFile!);
      }
      if (!mounted) return;

      developer.log('Setup: upserting user profile', name: 'SetupFlow');
      await repo.upsertCurrentUserProfile(
        gender: _gender,
        birthday: _birthday,
        fullName: _fullName.text.trim(),
        nickname: _nickname.text.trim(),
        email: _email.text.trim(),
        avatarUrl: avatarUrl,
        isPrivate: _isPrivate,
      );
      if (!mounted) return;

      // Align `meta/settings.privateAccount` with Firestore `isPrivate` so the
      // Privacy screen matches (same path as SettingsRepo).
      final uid = container.read(firebaseAuthProvider).currentUser?.uid;
      if (uid != null) {
        await container.read(firestoreProvider).collection('users').doc(uid).collection('meta').doc('settings').set(
              {'privateAccount': _isPrivate},
              SetOptions(merge: true),
            );
      }

      // Invalidate ALL relevant providers and wait for them to confirm
      // the profile is fully visible. This prevents HomeShell / router
      // redirect from seeing stale state and bouncing back to setup.
      container.invalidate(userHasNicknameProvider);
      container.invalidate(userProfileExistsProvider);
      container.invalidate(userProfileCompleteProvider);

      final (hasNickname, profileExists, profileComplete) =
          await (
            container.read(userHasNicknameProvider.future),
            container.read(userProfileExistsProvider.future),
            container.read(userProfileCompleteProvider.future),
          ).wait;
      if (!mounted) return;

      if (!hasNickname || !profileExists || !profileComplete) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        container.invalidate(userHasNicknameProvider);
        container.invalidate(userProfileExistsProvider);
        container.invalidate(userProfileCompleteProvider);
        await (
          container.read(userHasNicknameProvider.future),
          container.read(userProfileExistsProvider.future),
          container.read(userProfileCompleteProvider.future),
        ).wait;
      }
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile created successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (!mounted) return;
      context.go(HomeShell.routeName);
    } catch (e, stackTrace) {
      developer.log(
        'Setup failed: $e',
        name: 'SetupFlow',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      final message = e is StateError ? e.message.toString() : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not finish setup: $message'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        centerTitle: false,
        title: Text(
          _index == 0
              ? 'Tell Us About Yourself'
              : _index == 1
              ? 'When is Your Birthday?'
              : _index == 2
              ? 'Fill Your Profile'
              : 'Set Your Fingerprint',
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _index = i),
              children: [
                _GenderStep(
                  gender: _gender,
                  onChanged: (g) => setState(() => _gender = g),
                ),
                _BirthdayStep(
                  birthday: _birthday,
                  onChanged: (d) => setState(() => _birthday = d),
                ),
                _FillProfileStep(
                  formKey: _profileFormKey,
                  fullName: _fullName,
                  nickname: _nickname,
                  email: _email,
                  nicknameValidator: _nicknameValidator,
                  nicknameAvailability: _nicknameAvailability,
                  nicknameHint: _nicknameHint,
                  onAvatarSelected: (f) => _avatarFile = f,
                  lockNickname: _lockNickname,
                  isPrivate: _isPrivate,
                  onPrivateChanged: (v) => setState(() => _isPrivate = v),
                ),
                const _FingerprintStep(),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
            child:
                _saving
                    ? const Center(child: CircularProgressIndicator())
                    : _index == 3
                    ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveProfile,
                        style: ElevatedButton.styleFrom(
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                        ),
                        child: const Text('Retry'),
                      ),
                    )
                    : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _index == 2 && !_canContinueFromProfileStep
                                ? null
                                : _next,
                        style: ElevatedButton.styleFrom(
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                        ),
                        child: const Text('Continue'),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

class _FillProfileStep extends StatelessWidget {
  const _FillProfileStep({
    required this.formKey,
    required this.fullName,
    required this.nickname,
    required this.email,
    required this.nicknameValidator,
    required this.nicknameAvailability,
    required this.nicknameHint,
    required this.isPrivate,
    required this.onPrivateChanged,
    this.onAvatarSelected,
    this.lockNickname = false,
  });
  final GlobalKey<FormState> formKey;
  final TextEditingController fullName;
  final TextEditingController nickname;
  final TextEditingController email;
  final String? Function(String?) nicknameValidator;
  final _NicknameAvailability nicknameAvailability;
  final String? nicknameHint;
  final ValueChanged<File?>? onAvatarSelected;
  final bool lockNickname;
  final bool isPrivate;
  final ValueChanged<bool> onPrivateChanged;

  static String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final activeTrackColor =
        isDarkMode ? const Color(0xFF2B2B2B) : const Color(0xFF111111);
    final inactiveTrackColor =
        isDarkMode ? const Color(0xFF3A3A3A) : const Color(0xFFE5E5E5);
    final inactiveThumbColor =
        isDarkMode ? const Color(0xFFC8C8C8) : const Color(0xFFFAFAFA);
    final disabledTrackColor =
        isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFD0D0D0);
    final disabledThumbColor =
        isDarkMode ? const Color(0xFF7A7A7A) : const Color(0xFFB7B7B7);

    return Form(
      key: formKey,
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 24.h),
              Center(
                child: Stack(
                  children: [
                    _AvatarPicker(radius: 64.r, onSelected: onAvatarSelected),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: EdgeInsets.all(6.r),
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24.h),
              _FormInput(
                label: 'Full Name',
                controller: fullName,
                validator: _required,
              ),
              SizedBox(height: 12.h),
              lockNickname
                  ? _ReadOnlyField(label: 'Nickname', value: nickname.text)
                  : _FormInput(
                    label: 'Nickname',
                    controller: nickname,
                    validator: nicknameValidator,
                  ),
              if (!lockNickname && nicknameHint != null) ...[
                SizedBox(height: 6.h),
                Row(
                  children: [
                    Icon(
                      switch (nicknameAvailability) {
                        _NicknameAvailability.available => Icons.check_circle,
                        _NicknameAvailability.taken => Icons.cancel,
                        _NicknameAvailability.checking => Icons.hourglass_top,
                        _NicknameAvailability.error => Icons.error_outline,
                        _NicknameAvailability.invalid => Icons.info_outline,
                        _NicknameAvailability.idle => Icons.info_outline,
                      },
                      size: 16,
                      color: switch (nicknameAvailability) {
                        _NicknameAvailability.available => Colors.green,
                        _NicknameAvailability.taken => Colors.red,
                        _NicknameAvailability.error => Colors.red,
                        _NicknameAvailability.checking => Colors.black54,
                        _NicknameAvailability.invalid => Colors.black54,
                        _NicknameAvailability.idle => Colors.black54,
                      },
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        nicknameHint!,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: switch (nicknameAvailability) {
                            _NicknameAvailability.available => Colors.green,
                            _NicknameAvailability.taken => Colors.red,
                            _NicknameAvailability.error => Colors.red,
                            _NicknameAvailability.checking => Colors.black54,
                            _NicknameAvailability.invalid => Colors.black54,
                            _NicknameAvailability.idle => Colors.black54,
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 12.h),
              _FormInput(
                label: 'Email',
                controller: email,
                validator: _required,
                suffix: const Icon(Icons.mail_outline_rounded),
                enabled: false,
              ),
              SizedBox(height: 8.h),
              Theme(
                data: Theme.of(context).copyWith(
                  switchTheme: SwitchThemeData(
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return disabledThumbColor;
                      }
                      if (states.contains(WidgetState.selected)) {
                        return Colors.white;
                      }
                      return inactiveThumbColor;
                    }),
                    trackColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return disabledTrackColor;
                      }
                      if (states.contains(WidgetState.selected)) {
                        return activeTrackColor;
                      }
                      return inactiveTrackColor;
                    }),
                    trackOutlineColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                    overlayColor: WidgetStateProperty.resolveWith((states) {
                      return Colors.transparent;
                    }),
                  ),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Private account',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'When private, only followers see your posts. Default is public.',
                    style: TextStyle(fontSize: 13.sp, color: Colors.black54),
                  ),
                  value: isPrivate,
                  onChanged: onPrivateChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BirthdayStep extends StatelessWidget {
  const _BirthdayStep({required this.birthday, required this.onChanged});
  final DateTime birthday;
  final ValueChanged<DateTime> onChanged;

  int _calculatedAge() {
    final now = DateTime.now();
    int age = now.year - birthday.year;
    if (now.month < birthday.month ||
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final age = _calculatedAge();
    final isUnder13 = age < 13;
    return Padding(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 24.h),

          Text(
            'Your birthday will not be shown to the public.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isUnder13) ...[
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.red.shade400,
                    size: 18.r,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'You must be at least 13 years old to use Boomerang.',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 24.h),
          Center(
            child: Image.asset('assets/cake.png', width: 160.r, height: 160.r),
          ),

          SizedBox(height: 24.h),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: birthday,
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (picked != null) onChanged(picked);
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6),
                borderRadius: BorderRadius.circular(16.r),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${birthday.month}/${birthday.day}/${birthday.year}',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.calendar_today_rounded,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          _BirthdayPickers(birthday: birthday, onChanged: onChanged),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }
}

class _GenderStep extends StatelessWidget {
  const _GenderStep({required this.gender, required this.onChanged});
  final String gender;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 40.h),
          GestureDetector(
            onTap: () => onChanged('male'),
            child: _GenderChoice(
              label: 'Male',
              active: gender == 'male',
              icon: Icons.male,
            ),
          ),
          SizedBox(height: 40.h),
          GestureDetector(
            onTap: () => onChanged('female'),
            child: _GenderChoice(
              label: 'Female',
              active: gender == 'female',
              icon: Icons.female,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPicker extends StatefulWidget {
  const _AvatarPicker({required this.radius, this.onSelected});
  final double radius;
  final ValueChanged<File?>? onSelected;

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  String? _path;

  Future<void> _pick(ImageSource source) async {
    final file = await pickAndCropAvatar(source);
    if (file == null) return;
    setState(() => _path = file.path);
    widget.onSelected?.call(file);
  }

  void _showSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _pick(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _pick(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final image =
        _path == null
            ? null
            : DecorationImage(
              image: FileImage(File(_path!)),
              fit: BoxFit.cover,
            );

    return GestureDetector(
      onTap: _showSheet,
      child: Container(
        height: widget.radius * 2,
        width: widget.radius * 2,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1F1),
          shape: BoxShape.circle,
          image: image,
        ),
        child:
            _path == null
                ? Icon(Icons.person, size: widget.radius, color: Colors.black26)
                : null,
      ),
    );
  }
}

class _BirthdayPickers extends StatelessWidget {
  const _BirthdayPickers({required this.birthday, required this.onChanged});
  final DateTime birthday;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = List<int>.generate(now.year - 1899, (i) => 1900 + i);
    final months = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final daysInMonth = DateUtils.getDaysInMonth(birthday.year, birthday.month);
    final days = List<int>.generate(daysInMonth, (i) => i + 1);

    final monthController = FixedExtentScrollController(
      initialItem: birthday.month - 1,
    );
    final dayController = FixedExtentScrollController(
      initialItem: birthday.day - 1,
    );
    final yearController = FixedExtentScrollController(
      initialItem: birthday.year - 1900,
    );

    TextStyle itemStyle(bool isSelected) => TextStyle(
      fontSize: isSelected ? 28.sp : 20.sp,
      fontWeight: FontWeight.w700,
      color: isSelected ? Colors.black : Colors.black45,
    );

    return SizedBox(
      height: 220.h,
      child: Row(
        children: [
          Expanded(
            child: CupertinoPicker.builder(
              scrollController: monthController,
              itemExtent: 44.h,
              onSelectedItemChanged: (i) {
                final newMonth = i + 1;
                final maxDay = DateUtils.getDaysInMonth(
                  birthday.year,
                  newMonth,
                );
                final newDay = birthday.day.clamp(1, maxDay);
                onChanged(DateTime(birthday.year, newMonth, newDay));
              },
              childCount: months.length,
              itemBuilder: (context, index) {
                final selected = index == birthday.month - 1;
                return Center(
                  child: Text(months[index], style: itemStyle(selected)),
                );
              },
            ),
          ),
          Expanded(
            child: CupertinoPicker.builder(
              scrollController: dayController,
              itemExtent: 44.h,
              onSelectedItemChanged: (i) {
                final newDay = i + 1;
                onChanged(DateTime(birthday.year, birthday.month, newDay));
              },
              childCount: days.length,
              itemBuilder: (context, index) {
                final selected = index == birthday.day - 1;
                return Center(
                  child: Text('${days[index]}', style: itemStyle(selected)),
                );
              },
            ),
          ),
          Expanded(
            child: CupertinoPicker.builder(
              scrollController: yearController,
              itemExtent: 44.h,
              onSelectedItemChanged: (i) {
                final newYear = years[i];
                final maxDay = DateUtils.getDaysInMonth(
                  newYear,
                  birthday.month,
                );
                final newDay = birthday.day.clamp(1, maxDay);
                onChanged(DateTime(newYear, birthday.month, newDay));
              },
              childCount: years.length,
              itemBuilder: (context, index) {
                final y = years[index];
                final selected = y == birthday.year;
                return Center(child: Text('$y', style: itemStyle(selected)));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FingerprintStep extends StatelessWidget {
  const _FingerprintStep();
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: Colors.white)),
        Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 24.w),
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 36.r,
                  backgroundColor: Colors.black,
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Congratulations!',
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Your account is ready to use. You will be redirected to the Home page in a few seconds..',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 14.sp),
                ),
                SizedBox(height: 16.h),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GenderChoice extends StatelessWidget {
  const _GenderChoice({
    required this.label,
    required this.active,
    required this.icon,
  });
  final String label;
  final bool active;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 180.r,
          width: 180.r,
          decoration: BoxDecoration(
            color: active ? Colors.black : Colors.black26,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 64.r, color: Colors.white),
        ),
        SizedBox(height: 12.h),
        Text(
          label,
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// TextFormField with _Input-style decoration, for use inside Form with validators.
class _FormInput extends StatelessWidget {
  const _FormInput({
    required this.label,
    required this.controller,
    this.validator,
    this.suffix,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      decoration: InputDecoration(
        hintText: label,
        filled: true,
        fillColor: const Color(0xFFF6F6F6),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        SizedBox(height: 6.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F6F6),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.black12),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
