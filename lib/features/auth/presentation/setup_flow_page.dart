import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';

class SetupFlowPage extends StatefulWidget {
  const SetupFlowPage({super.key});
  static const String routeName = '/setup/flow';

  @override
  State<SetupFlowPage> createState() => _SetupFlowPageState();
}

class _SetupFlowPageState extends State<SetupFlowPage> {
  final PageController _controller = PageController();
  int _index = 0;
  String _gender = 'male';
  DateTime _birthday = DateTime(1995, 12, 27);
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _nickname = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _address = TextEditingController();
  bool _saving = false;
  File? _avatarFile;

  @override
  void initState() {
    super.initState();
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(firebaseAuthProvider);
    final prefill = auth.currentUser?.email ?? '';
    _email.text = prefill;
  }

  void _next() async {
    if (_index < 3) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      if (!mounted) return;
      setState(() => _saving = true);
      final container = ProviderScope.containerOf(context, listen: false);
      final repo = container.read(userProfileRepoProvider);
      String? avatarUrl;
      if (_avatarFile != null) {
        avatarUrl = await repo.uploadAvatar(_avatarFile!);
      }
      await repo.upsertCurrentUserProfile(
        gender: _gender,
        birthday: _birthday,
        fullName: _fullName.text.trim(),
        nickname: _nickname.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        avatarUrl: avatarUrl,
      );
      if (!mounted) return;
      // Show success then navigate home
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile created successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Keep buttons hidden during transition
      setState(() => _saving = false);
      context.go(HomeShell.routeName);
    }
  }

  void _skip() {
    if (context.mounted) context.go(HomeShell.routeName);
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
              onPageChanged: (i) {
                setState(() => _index = i);
                if (i == 3 && !_saving) {
                  // auto save and redirect at last step
                  _next();
                }
              },
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
                  fullName: _fullName,
                  nickname: _nickname,
                  email: _email,
                  phone: _phone,
                  address: _address,
                  onAvatarSelected: (f) => _avatarFile = f,
                ),
                const _FingerprintStep(),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
            child:
                (_saving || _index == 3)
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _skip,
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding: EdgeInsets.symmetric(vertical: 16.h),
                            ),
                            child: const Text('Skip'),
                          ),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _next,
                            style: ElevatedButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding: EdgeInsets.symmetric(vertical: 16.h),
                            ),
                            child: const Text('Continue'),
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}

class _FillProfileStep extends StatelessWidget {
  const _FillProfileStep({
    required this.fullName,
    required this.nickname,
    required this.email,
    required this.phone,
    required this.address,
    this.onAvatarSelected,
  });
  final TextEditingController fullName;
  final TextEditingController nickname;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController address;
  final ValueChanged<File?>? onAvatarSelected;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20.w),
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
          _Input(label: 'Full Name', controller: fullName),
          SizedBox(height: 12.h),
          _Input(label: 'Nickname', controller: nickname),
          SizedBox(height: 12.h),
          _Input(
            label: 'Email',
            controller: email,
            suffix: const Icon(Icons.mail_outline_rounded),
            enabled: false,
          ),
          SizedBox(height: 12.h),
          _Input(
            label: 'Phone Number',
            controller: phone,
            prefix: const Text('🇺🇸  ▾'),
          ),
          SizedBox(height: 12.h),
          _Input(
            label: 'Address',
            controller: address,
            suffix: const Icon(Icons.location_on_outlined),
          ),
        ],
      ),
    );
  }
}

class _BirthdayStep extends StatelessWidget {
  const _BirthdayStep({required this.birthday, required this.onChanged});
  final DateTime birthday;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) {
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
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (xFile == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: xFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
        ),
        IOSUiSettings(title: 'Crop Image'),
      ],
    );
    if (cropped == null) return;
    setState(() => _path = cropped.path);
    widget.onSelected?.call(File(cropped.path));
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
                  color: Colors.black.withOpacity(0.1),
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

// Old placeholder field removed

class _Input extends StatelessWidget {
  const _Input({
    required this.label,
    required this.controller,
    this.prefix,
    this.suffix,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final Widget? prefix;
  final Widget? suffix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: label,
        filled: true,
        fillColor: const Color(0xFFF6F6F6),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
        prefixIcon:
            prefix == null
                ? null
                : Padding(
                  padding: EdgeInsets.only(left: 12.w, right: 8.w),
                  child: prefix,
                ),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
