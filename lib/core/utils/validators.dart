class Validators {
  Validators._();

  static final RegExp _emailRegExp = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Required';
    if (!_emailRegExp.hasMatch(v)) return 'Enter a valid email';
    return null;
  }
}

