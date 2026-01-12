import 'package:boomerang/features/auth/presentation/choose_username_page.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';

/// Pure redirect helper for username gating to keep testable logic out of router.
String? usernameGateRedirect({
  required bool signedIn,
  required bool hasUsername,
  required String currentPath,
}) {
  final isChoose = currentPath == ChooseUsernamePage.routeName;
  if (!signedIn) return null;
  if (!hasUsername && !isChoose) return ChooseUsernamePage.routeName;
  if (hasUsername && isChoose) return HomeShell.routeName;
  return null;
}
