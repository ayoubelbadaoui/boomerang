import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:boomerang/core/utils/avatar_crop.dart';
import 'dart:io';
import 'dart:developer' as developer;

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
  final TextEditingController _phone = TextEditingController();

  bool _saving = false;
  bool _lockNickname = false;
  File? _avatarFile;
  _CountryCode _countryCode = _countryCodes.first;

  @override
  void initState() {
    super.initState();
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(firebaseAuthProvider);
    final prefill = auth.currentUser?.email ?? '';
    _email.text = prefill;
    _hydrateFromUserDoc();
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
        phone: '${_countryCode.dialCode} ${_phone.text.trim()}',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not finish setup: $e'),
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
                  phone: _phone,
                  onAvatarSelected: (f) => _avatarFile = f,
                  lockNickname: _lockNickname,
                  countryCode: _countryCode,
                  onCountryCodeChanged: (c) => setState(() => _countryCode = c),
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
                        onPressed: _next,
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
    required this.phone,
    required this.countryCode,
    required this.onCountryCodeChanged,
    required this.isPrivate,
    required this.onPrivateChanged,
    this.onAvatarSelected,
    this.lockNickname = false,
  });
  final GlobalKey<FormState> formKey;
  final TextEditingController fullName;
  final TextEditingController nickname;
  final TextEditingController email;
  final TextEditingController phone;
  final ValueChanged<File?>? onAvatarSelected;
  final bool lockNickname;
  final _CountryCode countryCode;
  final ValueChanged<_CountryCode> onCountryCodeChanged;
  final bool isPrivate;
  final ValueChanged<bool> onPrivateChanged;

  static String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  @override
  Widget build(BuildContext context) {
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
                    validator: _required,
                  ),
              SizedBox(height: 12.h),
              _FormInput(
                label: 'Email',
                controller: email,
                validator: _required,
                suffix: const Icon(Icons.mail_outline_rounded),
                enabled: false,
              ),
              SizedBox(height: 12.h),
              _PhoneInput(
                controller: phone,
                validator: _required,
                countryCode: countryCode,
                onCountryCodeTap:
                    () => _showCountryCodePicker(
                      context,
                      countryCode,
                      onCountryCodeChanged,
                    ),
              ),
              SizedBox(height: 8.h),
              SwitchListTile(
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
                activeThumbColor: Colors.white,
                onChanged: onPrivateChanged,
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

class _CountryCode {
  const _CountryCode(this.flag, this.dialCode, this.name);
  final String flag;
  final String dialCode;
  final String name;
}

const _countryCodes = [
  _CountryCode('🇺🇸', '+1', 'United States'),
  _CountryCode('🇬🇧', '+44', 'United Kingdom'),
  _CountryCode('🇨🇦', '+1', 'Canada'),
  _CountryCode('🇦🇺', '+61', 'Australia'),
  _CountryCode('🇮🇳', '+91', 'India'),
  _CountryCode('🇩🇪', '+49', 'Germany'),
  _CountryCode('🇫🇷', '+33', 'France'),
  _CountryCode('🇪🇸', '+34', 'Spain'),
  _CountryCode('🇮🇹', '+39', 'Italy'),
  _CountryCode('🇧🇷', '+55', 'Brazil'),
  _CountryCode('🇲🇽', '+52', 'Mexico'),
  _CountryCode('🇯🇵', '+81', 'Japan'),
  _CountryCode('🇰🇷', '+82', 'South Korea'),
  _CountryCode('🇨🇳', '+86', 'China'),
  _CountryCode('🇷🇺', '+7', 'Russia'),
  _CountryCode('🇸🇦', '+966', 'Saudi Arabia'),
  _CountryCode('🇦🇪', '+971', 'UAE'),
  _CountryCode('🇪🇬', '+20', 'Egypt'),
  _CountryCode('🇳🇬', '+234', 'Nigeria'),
  _CountryCode('🇿🇦', '+27', 'South Africa'),
  _CountryCode('🇹🇷', '+90', 'Turkey'),
  _CountryCode('🇵🇰', '+92', 'Pakistan'),
  _CountryCode('🇧🇩', '+880', 'Bangladesh'),
  _CountryCode('🇮🇩', '+62', 'Indonesia'),
  _CountryCode('🇵🇭', '+63', 'Philippines'),
  _CountryCode('🇹🇭', '+66', 'Thailand'),
  _CountryCode('🇻🇳', '+84', 'Vietnam'),
  _CountryCode('🇲🇾', '+60', 'Malaysia'),
  _CountryCode('🇸🇬', '+65', 'Singapore'),
  _CountryCode('🇳🇿', '+64', 'New Zealand'),
  _CountryCode('🇲🇦', '+212', 'Morocco'),
  _CountryCode('🇩🇿', '+213', 'Algeria'),
  _CountryCode('🇹🇳', '+216', 'Tunisia'),
];

void _showCountryCodePicker(
  BuildContext context,
  _CountryCode current,
  ValueChanged<_CountryCode> onChanged,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (ctx) => _CountryCodeSheet(
          current: current,
          onSelected: (c) {
            onChanged(c);
            Navigator.of(ctx).pop();
          },
        ),
  );
}

class _CountryCodeSheet extends StatefulWidget {
  const _CountryCodeSheet({required this.current, required this.onSelected});
  final _CountryCode current;
  final ValueChanged<_CountryCode> onSelected;

  @override
  State<_CountryCodeSheet> createState() => _CountryCodeSheetState();
}

class _CountryCodeSheetState extends State<_CountryCodeSheet> {
  String _query = '';

  List<_CountryCode> get _filtered =>
      _query.isEmpty
          ? _countryCodes
          : _countryCodes.where((c) {
            final q = _query.toLowerCase();
            return c.name.toLowerCase().contains(q) || c.dialCode.contains(q);
          }).toList();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder:
          (context, scrollController) => Column(
            children: [
              SizedBox(height: 12.h),
              Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search country...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFFF6F6F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final c = _filtered[i];
                    final selected =
                        c.dialCode == widget.current.dialCode &&
                        c.name == widget.current.name;
                    return ListTile(
                      leading: Text(c.flag, style: TextStyle(fontSize: 24.sp)),
                      title: Text(c.name),
                      trailing: Text(
                        c.dialCode,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              selected
                                  ? Theme.of(context).primaryColor
                                  : Colors.black54,
                        ),
                      ),
                      selected: selected,
                      onTap: () => widget.onSelected(c),
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }
}

class _PhoneInput extends StatelessWidget {
  const _PhoneInput({
    required this.controller,
    required this.validator,
    required this.countryCode,
    required this.onCountryCodeTap,
  });
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final _CountryCode countryCode;
  final VoidCallback onCountryCodeTap;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: TextInputType.phone,
      style: TextStyle(fontSize: 15.sp, color: Colors.black87),
      decoration: InputDecoration(
        hintText: 'Phone Number',
        filled: true,
        fillColor: const Color(0xFFF6F6F6),
        contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 18.h),
        prefixIcon: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCountryCodeTap,
          child: Padding(
            padding: EdgeInsets.only(left: 16.w, right: 12.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(countryCode.flag, style: TextStyle(fontSize: 20.sp)),
                SizedBox(width: 6.w),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20.r,
                  color: Colors.black54,
                ),
              ],
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        prefixText: '${countryCode.dialCode} ',
        prefixStyle: TextStyle(
          fontSize: 15.sp,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
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
