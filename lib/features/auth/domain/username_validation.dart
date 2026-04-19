class UsernameValidationResult {
  const UsernameValidationResult({required this.isValid, this.error});
  final bool isValid;
  final String? error;
}

UsernameValidationResult validateUsername(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return const UsernameValidationResult(isValid: false, error: 'Username is required');
  }
  if (trimmed.length < 3) {
    return const UsernameValidationResult(
      isValid: false,
      error: 'Must be at least 3 characters',
    );
  }
  if (trimmed.length > 20) {
    return const UsernameValidationResult(
      isValid: false,
      error: 'Must be at most 20 characters',
    );
  }
  final regex = RegExp(r'^[a-z0-9._]+$');
  if (!regex.hasMatch(trimmed)) {
    return const UsernameValidationResult(
      isValid: false,
      error: 'Use lowercase letters, numbers, dot or underscore only',
    );
  }
  return const UsernameValidationResult(isValid: true);
}
