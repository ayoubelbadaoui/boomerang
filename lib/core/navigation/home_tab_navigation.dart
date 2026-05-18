import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-nav index for [HomeShell] (0=Home … 4=Profile).
final homeTabIndexProvider = StateProvider<int>((ref) => 0);
