class AuthState {
  final bool loading;
  final String? error;
  final String? success;
  const AuthState({this.loading = false, this.error, this.success});
}
